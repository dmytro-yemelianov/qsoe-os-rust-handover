/*
 * tm_sysfs.c -- OS-independent /sys model shared by every QSOE taskman.
 *
 * Owns the entry table, the content snapshot, path resolution, and the
 * directory listing for the read-only /sys pseudo-filesystem.  Knows
 * nothing about how the strings were obtained (sysmap on NQ, syscfg on
 * LQ) or how reads are served (OCB on NQ, handler_kind dispatch on LQ) --
 * see tm_sysfs.h for the seam.
 *
 * Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
 * SPDX-License-Identifier: Apache-2.0
 */
#include <tm_sysfs.h>

/* Buffer sizes.  cmdline tracks FDT /chosen/bootargs (kernels cap it at
 * 256); board carries the first /compatible string.  All include room
 * for the appended '\n' and the NUL. */
#define SYSFS_CMDLINE_BUFSZ    258
#define SYSFS_BOARD_BUFSZ      130
#define SYSFS_VERSION_BUFSZ     64
#define SYSFS_BUILDDATE_BUFSZ   64
#define SYSFS_OSNAME_BUFSZ      32   /* "QSOE/N", "QSOE/L", ... + \n + NUL */

static char     s_board[SYSFS_BOARD_BUFSZ];          static unsigned s_board_len;
static char     s_builddate[SYSFS_BUILDDATE_BUFSZ];  static unsigned s_builddate_len;
static char     s_cmdline[SYSFS_CMDLINE_BUFSZ];      static unsigned s_cmdline_len;
static char     s_osname[SYSFS_OSNAME_BUFSZ];        static unsigned s_osname_len;
static char     s_version[SYSFS_VERSION_BUFSZ];      static unsigned s_version_len;

struct sysfs_entry {
    const char *name;
    char       *data;
    unsigned   *len_ptr;
};

/* Order matters: tm_sysfs_entry_name() (and thus readdir) walks this
 * array linearly. */
static const struct sysfs_entry s_entries[] = {
    { "board",     s_board,     &s_board_len     },
    { "builddate", s_builddate, &s_builddate_len },
    { "cmdline",   s_cmdline,   &s_cmdline_len   },
    { "osname",    s_osname,    &s_osname_len    },
    { "version",   s_version,   &s_version_len   },
};
#define SYSFS_NENTRIES  ((unsigned)(sizeof s_entries / sizeof s_entries[0]))

/* Copy `src` into `dst` (cap bytes incl. NUL), append '\n', NUL-
 * terminate, and return the content length (counts the '\n', not the
 * NUL).  A NULL or empty source yields a one-byte "\n". */
static unsigned sysfs_snap(char *dst, unsigned cap, const char *src)
{
    unsigned n = 0;
    if (src != 0) {
        while (n + 2 < cap && src[n] != '\0') {
            dst[n] = src[n];
            n++;
        }
    }
    dst[n]     = '\n';
    dst[n + 1] = '\0';
    return n + 1;
}

void tm_sysfs_init(const char *osname, const char *board, const char *cmdline,
                   const char *version, const char *builddate)
{
    s_osname_len    = sysfs_snap(s_osname,    SYSFS_OSNAME_BUFSZ,    osname);
    s_board_len     = sysfs_snap(s_board,     SYSFS_BOARD_BUFSZ,     board);
    s_cmdline_len   = sysfs_snap(s_cmdline,   SYSFS_CMDLINE_BUFSZ,   cmdline);
    s_version_len   = sysfs_snap(s_version,   SYSFS_VERSION_BUFSZ,   version);
    s_builddate_len = sysfs_snap(s_builddate, SYSFS_BUILDDATE_BUFSZ, builddate);
}

static int sysfs_streq(const char *a, const char *b)
{
    unsigned i = 0;
    while (a[i] != '\0' && b[i] != '\0' && a[i] == b[i]) i++;
    return (a[i] == '\0' && b[i] == '\0') ? 1 : 0;
}

int tm_sysfs_resolve(const char *path, unsigned *idx_out)
{
    /* Must start with "/sys". */
    if (path[0] != '/' || path[1] != 's' ||
        path[2] != 'y' || path[3] != 's')
        return 0;

    /* "/sys" exact, or "/sys/". */
    if (path[4] == '\0') return 1;
    if (path[4] != '/')  return 0;
    if (path[5] == '\0') return 1;

    /* "/sys/<name>". */
    const char *name = &path[5];
    for (unsigned i = 0; i < SYSFS_NENTRIES; i++) {
        if (sysfs_streq(name, s_entries[i].name)) {
            if (idx_out) *idx_out = i;
            return 2;
        }
    }
    return 0;
}

int tm_sysfs_path_exists(const char *path)
{
    unsigned idx = 0;
    int k = tm_sysfs_resolve(path, &idx);
    return (k == 1 || k == 2) ? 1 : 0;
}

const char *tm_sysfs_content(unsigned idx, unsigned *len_out)
{
    if (idx >= SYSFS_NENTRIES) {
        if (len_out) *len_out = 0;
        return 0;
    }
    if (len_out) *len_out = *s_entries[idx].len_ptr;
    return s_entries[idx].data;
}

unsigned tm_sysfs_nentries(void)
{
    return SYSFS_NENTRIES;
}

const char *tm_sysfs_entry_name(unsigned idx)
{
    return (idx < SYSFS_NENTRIES) ? s_entries[idx].name : 0;
}
