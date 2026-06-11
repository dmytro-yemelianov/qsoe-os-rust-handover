/*
 * tm_procfs.c -- OS-independent /proc model (see tm_procfs.h).
 *
 * Owns path resolution, the `info` text format, and the readdir cursor
 * walk.  The process data comes from the per-kernel taskman through the
 * two callbacks registered with tm_procfs_init().
 *
 * Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
 * SPDX-License-Identifier: Apache-2.0
 */
#include <tm_procfs.h>

static tm_procfs_get_fn  s_get;
static tm_procfs_next_fn s_next;

void tm_procfs_init(tm_procfs_get_fn get, tm_procfs_next_fn next)
{
    s_get  = get;
    s_next = next;
}

/* ---- tiny formatting helpers (libtaskman links no libc printf) ---- */

static unsigned put_str(char *dst, unsigned pos, const char *s)
{
    while (*s != '\0')
        dst[pos++] = *s++;
    return pos;
}

static unsigned put_dec(char *dst, unsigned pos, long v)
{
    char tmp[24];
    unsigned n = 0;
    if (v < 0) {
        dst[pos++] = '-';
        v = -v;
    }
    do {
        tmp[n++] = (char)('0' + (v % 10));
        v /= 10;
    } while (v != 0);
    while (n > 0)
        dst[pos++] = tmp[--n];
    return pos;
}

unsigned tm_procfs_info(int pid, char *dst, unsigned cap)
{
    struct tm_procfs_proc p;
    if (!s_get || cap < TM_PROCFS_INFO_MAX || !s_get(pid, &p))
        return 0;

    unsigned n = 0;
    n = put_str(dst, n, "pid: ");
    n = put_dec(dst, n, (long)p.pid);
    n = put_str(dst, n, "\nppid: ");
    n = put_dec(dst, n, (long)p.ppid);
    n = put_str(dst, n, "\nstate: ");
    n = put_str(dst, n, p.state ? "zombie" : "alive");
    n = put_str(dst, n, "\nname: ");
    n = put_str(dst, n, p.name);
    n = put_str(dst, n, "\n");
    return n;
}

/* ---- path resolution ---- */

int tm_procfs_resolve(const char *path, int *pid_out)
{
    if (path[0] != '/' || path[1] != 'p' || path[2] != 'r' ||
        path[3] != 'o' || path[4] != 'c')
        return 0;
    if (path[5] == '\0')
        return 1;
    if (path[5] != '/')
        return 0;
    if (path[6] == '\0')
        return 1;

    /* Decimal pid component. */
    unsigned i = 6;
    long pid = 0;
    if (path[i] < '0' || path[i] > '9')
        return 0;
    while (path[i] >= '0' && path[i] <= '9') {
        pid = pid * 10 + (path[i] - '0');
        if (pid > 0x7fffffffL)
            return 0;
        i++;
    }
    struct tm_procfs_proc tmp;
    if (!s_get || !s_get((int)pid, &tmp))
        return 0;
    if (pid_out)
        *pid_out = (int)pid;

    if (path[i] == '\0')
        return 2;
    if (path[i] != '/')
        return 0;
    i++;
    if (path[i] == '\0')
        return 2;

    /* The single per-pid entry: "info". */
    if (path[i] == 'i' && path[i+1] == 'n' && path[i+2] == 'f' &&
        path[i+3] == 'o' && path[i+4] == '\0')
        return 3;
    return 0;
}

int tm_procfs_path_exists(const char *path)
{
    int pid = 0;
    return tm_procfs_resolve(path, &pid) != 0;
}

/* ---- readdir ---- */

int tm_procfs_readdir_root(unsigned long *cursor, char *name_out,
                           unsigned *namelen_out, int *d_type_out)
{
    if (!s_next)
        return 0;
    struct tm_procfs_proc p;
    int pid = s_next((int)*cursor, &p);
    if (pid <= 0)
        return 0;                       /* end of directory */

    *cursor = (unsigned long)pid + 1;
    unsigned n = put_dec(name_out, 0, (long)pid);
    name_out[n] = '\0';
    *namelen_out = n;
    *d_type_out  = TM_PROCFS_DT_DIR;
    return 1;
}

int tm_procfs_readdir_piddir(unsigned long cursor, char *name_out,
                             unsigned *namelen_out, int *d_type_out)
{
    if (cursor >= 1)
        return 0;                       /* one entry only */
    name_out[0] = 'i'; name_out[1] = 'n'; name_out[2] = 'f';
    name_out[3] = 'o'; name_out[4] = '\0';
    *namelen_out = 4;
    *d_type_out  = TM_PROCFS_DT_REG;
    return 1;
}
