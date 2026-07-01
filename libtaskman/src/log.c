/*
 * libtaskman/src/log.c -- leveled, printf-style logging for taskman.
 *
 * Format + filter are OS-independent; the per-kernel taskman supplies
 * only the sink callback (tm_log_init).  See <tm_log.h> for the
 * contract and the --debug[=N] verbosity mapping.
 *
 * The formatter is a deliberate printf SUBSET (no float, no %n, no
 * positional args): taskman is statically linked without stdio, and
 * every consumer of a richer format spec so far turned out to be a
 * log line that didn't need it.
 *
 * Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdarg.h>
#include <tm_log.h>

static tm_log_sink_t tm_sink;                       /* NULL until tm_log_init */
static int tm_level = TM_LOG_LEVEL_DEFAULT;

void tm_log_init(tm_log_sink_t sink)
{
    tm_sink = sink;
}

void tm_log_set_level(int level)
{
    if (level < TM_LOG_ERR)
        level = TM_LOG_ERR;
    if (level > TM_LOG_TRACE)
        level = TM_LOG_TRACE;
    tm_level = level;
}

int tm_log_get_level(void)
{
    return tm_level;
}

int tm_log_enabled(int level)
{
    return level <= tm_level && tm_sink != 0;
}

void tm_log_emit(int level, const char *buf, unsigned len)
{
    if (!tm_log_enabled(level) || len == 0)
        return;

    tm_sink(buf, len);
}

/* ---- --debug[=N] command-line scan ---------------------------------- */

/* The option token.  Matched per-token (delimited by blanks), so a
 * hypothetical "--debugfs" does not false-positive. */
#define TM_DEBUG_OPT        "--debug"
#define TM_DEBUG_OPT_LEN    (sizeof TM_DEBUG_OPT - 1)

static int is_blank(char c)
{
    return c == ' ' || c == '\t';
}

int tm_log_apply_cmdline(const char *cmdline)
{
    const char *p = cmdline;

    if (p == 0)
        return tm_level;

    while (*p != '\0') {
        while (is_blank(*p))
            p++;
        if (*p == '\0')
            break;

        /* [p .. token end) is one token. */
        unsigned i = 0;
        while (i < TM_DEBUG_OPT_LEN && p[i] == TM_DEBUG_OPT[i])
            i++;
        if (i == TM_DEBUG_OPT_LEN) {
            if (p[i] == '\0' || is_blank(p[i])) {
                /* bare --debug == --debug=1 */
                tm_log_set_level(TM_LOG_DBG);
            } else if (p[i] == '=') {
                unsigned long n = 0;
                const char *d = p + i + 1;
                int any = 0;
                while (*d >= '0' && *d <= '9') {
                    n = n * 10 + (unsigned long) (*d - '0');
                    d++;
                    any = 1;
                }
                if (any && (*d == '\0' || is_blank(*d))) {
                    /* --debug=0 keeps the default; 1 adds DBG; 2 and
                     * anything higher clamps to TRACE. */
                    if (n >= 1)
                        tm_log_set_level(n >= 2 ? TM_LOG_TRACE : TM_LOG_DBG);
                }
                /* malformed value ("--debug=x"): ignore the token */
            }
        }

        while (*p != '\0' && !is_blank(*p))
            p++;
    }
    return tm_level;
}

/* ---- printf-subset formatter ----------------------------------------- */

/* Emission cursor over the fixed line buffer.  Excess output is
 * silently truncated; `pos` keeps counting so the final flush just
 * clamps once. */
struct tm_out {
    char     *buf;
    unsigned  cap;
    unsigned  pos;
};

static void out_ch(struct tm_out *o, char c)
{
    if (o->pos < o->cap)
        o->buf[o->pos] = c;
    o->pos++;
}

static void out_str(struct tm_out *o, const char *s)
{
    while (*s != '\0')
        out_ch(o, *s++);
}

/* Digits for %x.  Lowercase only -- the QSOE log idiom ("entry=0x15166"). */
static const char tm_hex_digits[] = "0123456789abcdef";

/* Worst case: 64-bit value in decimal = 20 digits (+ sign). */
#define TM_NUM_BUF      24

static void out_num(struct tm_out *o, unsigned long long v, unsigned base,
                    int negative, unsigned width, char pad)
{
    char tmp[TM_NUM_BUF];
    unsigned n = 0;

    do {
        tmp[n++] = tm_hex_digits[v % base];
        v /= base;
    } while (v != 0 && n < sizeof tmp);

    if (negative)
        tmp[n++] = '-';

    while (n < width && n < sizeof tmp)
        tmp[n++] = pad;

    while (n > 0)
        out_ch(o, tmp[--n]);
}

/* Length-modifier states for the %-spec parser below. */
enum tm_len_mod { LEN_INT, LEN_LONG, LEN_LLONG, LEN_SIZE };

static void tm_vfmt(struct tm_out *o, const char *fmt, tm_log_va_list ap)
{
    while (*fmt != '\0') {
        char c = *fmt++;
        if (c != '%') {
            out_ch(o, c);
            continue;
        }

        /* flags + width: only '0' padding and a plain decimal width */
        char pad = ' ';
        unsigned width = 0;
        if (*fmt == '0') {
            pad = '0';
            fmt++;
        }
        while (*fmt >= '0' && *fmt <= '9')
            width = width * 10 + (unsigned) (*fmt++ - '0');

        enum tm_len_mod len = LEN_INT;
        if (*fmt == 'l') {
            len = LEN_LONG;
            fmt++;
            if (*fmt == 'l') {
                len = LEN_LLONG;
                fmt++;
            }
        } else if (*fmt == 'z') {
            len = LEN_SIZE;
            fmt++;
        }

        char conv = *fmt;
        if (conv == '\0')
            break;                  /* dangling '%' at end of format */
        fmt++;

        switch (conv) {
        case 's': {
            const char *s = va_arg(ap, const char *);
            out_str(o, s != 0 ? s : "(null)");
            break;
        }
        case 'c':
            out_ch(o, (char) va_arg(ap, int));
            break;
        case 'd':
        case 'i': {
            long long v;
            if (len == LEN_LLONG)
                v = va_arg(ap, long long);
            else if (len == LEN_LONG)
                v = va_arg(ap, long);
            else if (len == LEN_SIZE)
                v = (long long) va_arg(ap, unsigned long);
            else
                v = va_arg(ap, int);
            /* Negate in unsigned space: -LLONG_MIN is UB in signed. */
            if (v < 0)
                out_num(o, 0ULL - (unsigned long long) v, 10, 1, width, pad);
            else
                out_num(o, (unsigned long long) v, 10, 0, width, pad);
            break;
        }
        case 'u':
        case 'x': {
            unsigned long long v;
            if (len == LEN_LLONG)
                v = va_arg(ap, unsigned long long);
            else if (len == LEN_LONG || len == LEN_SIZE)
                v = va_arg(ap, unsigned long);
            else
                v = va_arg(ap, unsigned int);
            out_num(o, v, conv == 'x' ? 16 : 10, 0, width, pad);
            break;
        }
        case 'p':
            out_str(o, "0x");
            out_num(o, (unsigned long long) (unsigned long) va_arg(ap, void *),
                    16, 0, 0, ' ');
            break;
        case '%':
            out_ch(o, '%');
            break;
        default:
            /* Unknown conversion: echo it visibly rather than
             * desynchronize the va_list any further. */
            out_ch(o, '%');
            out_ch(o, conv);
            break;
        }
    }
}

void tm_vlog(int level, const char *fmt, tm_log_va_list ap)
{
    if (!tm_log_enabled(level))
        return;

    char line[TM_LOG_LINE_MAX];
    struct tm_out o = { line, sizeof line, 0 };

    tm_vfmt(&o, fmt, ap);

    unsigned n = o.pos < o.cap ? o.pos : o.cap;
    tm_log_emit(level, line, n);
}

void tm_log(int level, const char *fmt, ...)
{
    if (!tm_log_enabled(level))
        return;

    tm_log_va_list ap;
    va_start(ap, fmt);
    tm_vlog(level, fmt, ap);
    va_end(ap);
}
