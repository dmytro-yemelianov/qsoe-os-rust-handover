/*
 * <libtaskman/tm_log.h> -- leveled, printf-style logging for taskman.
 *
 * OS-independent: formatting and level filtering live in
 * libtaskman/src/log.c; the only per-kernel piece is the sink
 * callback that pushes the finished line to the console (NQ:
 * SYS_DBGPRINT, LQ: seL4 debug write).
 *
 * The sink is installed via tm_log_init(), NOT via the
 * libtaskman_seams table: logging must be alive before anything
 * else in taskman -- including libtaskman_init() itself, whose
 * failure paths want to complain somewhere.
 *
 * Verbosity contract (taskman --debug[=N] command-line option):
 *   (absent)            ERR + WARN + INFO
 *   --debug, --debug=1  ... + DBG
 *   --debug=2 (and up)  ... + TRACE
 *
 * Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef LIBTASKMAN_LOG_H
#define LIBTASKMAN_LOG_H

/* Severity levels, ordered so "print everything up to the threshold"
 * is a single integer compare.  The order also matches the slogger
 * severity scale so a future route-to-slog is a 1:1 mapping. */
enum tm_log_level {
    TM_LOG_ERR   = 0,       /* operator must act (failed map, bad chid) */
    TM_LOG_WARN  = 1,       /* unexpected but survivable */
    TM_LOG_INFO  = 2,       /* once-per-boot operator information */
    TM_LOG_DBG   = 3,       /* per-operation diagnostics (spawn details) */
    TM_LOG_TRACE = 4        /* per-message firehose (dispatch traces) */
};

/* Threshold when taskman runs without --debug. */
#define TM_LOG_LEVEL_DEFAULT    TM_LOG_INFO

/* Push `len` finished bytes to the console.  Per-kernel. */
typedef void (*tm_log_sink_t)(const char *buf, unsigned len);

/* Install the sink.  Call FIRST, before any other tm_* entry point.
 * Until called, tm_log() drops everything silently (it has nowhere
 * to write). */
void tm_log_init(tm_log_sink_t sink);

void tm_log_set_level(int level);
int  tm_log_get_level(void);
int  tm_log_enabled(int level);

/* Scan a boot command line for the --debug[=N] token and set the
 * threshold accordingly (see the verbosity contract above).  Tokens
 * other than --debug are ignored -- the cmdline namespace stays open
 * for future options.  NULL is accepted and means "no arguments".
 * Returns the resulting threshold. */
int  tm_log_apply_cmdline(const char *cmdline);

/* Non-variadic sink boundary for already formatted bytes.  This is the
 * C-owned ABI a future Rust formatter can target without owning the
 * exported C variadic tm_log() entry point.  `buf` must point to `len`
 * bytes when `len` is non-zero; no NUL terminator is required. */
void tm_log_emit(int level, const char *buf, unsigned len);

/* C-owned va_list shim behind the public variadic wrapper.  Keep this
 * boundary in C: stable no_std Rust should not consume a C va_list. */
typedef __builtin_va_list tm_log_va_list;
void tm_vlog(int level, const char *fmt, tm_log_va_list ap)
    __attribute__((format(printf, 2, 0)));

/* The exported workhorse.  printf-subset format support:
 *   %s %c %d %i %u %x %p %%   with  l / ll / z  length modifiers
 *   and  zero-pad + field width  (e.g. %08lx).
 * No floating point, no %n, no positional args.  Lines longer than
 * TM_LOG_LINE_MAX bytes are truncated.  The caller supplies the
 * trailing \n, exactly as with printf. */
void tm_log(int level, const char *fmt, ...)
    __attribute__((format(printf, 2, 3)));

/* One formatted log line, including the NUL.  Longer output is
 * truncated; raise if a call site legitimately needs more. */
#define TM_LOG_LINE_MAX         256

#define tm_err(...)     tm_log(TM_LOG_ERR,   __VA_ARGS__)
#define tm_warn(...)    tm_log(TM_LOG_WARN,  __VA_ARGS__)
#define tm_info(...)    tm_log(TM_LOG_INFO,  __VA_ARGS__)
#define tm_dbg(...)     tm_log(TM_LOG_DBG,   __VA_ARGS__)
#define tm_trace(...)   tm_log(TM_LOG_TRACE, __VA_ARGS__)

#endif /* LIBTASKMAN_LOG_H */
