/*
 * tm_procfs.h -- OS-independent /proc model for every QSOE taskman.
 *
 * The /proc namespace is deliberately tiny and identical on QSOE/N and
 * QSOE/L:
 *
 *     /proc                -- one directory per LIVE pid
 *     /proc/<pid>          -- directory holding a single entry
 *     /proc/<pid>/info     -- key: value text snapshot of the process
 *
 * `info` is "key: value" lines (pid, ppid, state, name) -- cat-able at
 * the shell, parseable by ps.  Thread-level detail is NOT here (that is
 * kernel knowledge, published through TM_REQ_SYSINFO).
 *
 * This core owns the portable logic: path resolution, the info text
 * format, and the readdir cursor walk.  It does NOT own the process
 * table -- that is per-kernel.  Each taskman registers two callbacks via
 * tm_procfs_init(): `get` (fetch one process by pid) and `next` (find
 * the next live pid at or above a cursor).  The core normalises each
 * record into struct tm_procfs_proc and formats from there, mirroring
 * how tm_sysfs splits the portable model from the per-OS data source.
 *
 * Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef QSOE_TM_PROCFS_H
#define QSOE_TM_PROCFS_H

/* Longest process name the model carries (basename, NUL-terminated). */
#define TM_PROCFS_NAME_MAX  32

/* Upper bound of an `info` rendering: four short "key: value" lines, the
 * longest carrying TM_PROCFS_NAME_MAX name bytes.  A caller's read buffer
 * must be at least this big; one read always drains the file. */
#define TM_PROCFS_INFO_MAX  160

/* d_type values on the readdir wire (matches cpio + sysfs: 4=DIR, 8=REG). */
#define TM_PROCFS_DT_DIR    4
#define TM_PROCFS_DT_REG    8

/* Normalised, OS-independent view of one process. */
struct tm_procfs_proc {
    int  pid;
    int  ppid;
    int  state;                       /* 0 = alive, 1 = zombie */
    char name[TM_PROCFS_NAME_MAX];    /* basename, NUL-terminated */
};

/* Seam callback: fill *out for `pid` if it is a live (or zombie) process
 * record; return 1.  Return 0 if there is no such process. */
typedef int (*tm_procfs_get_fn)(int pid, struct tm_procfs_proc *out);

/* Seam callback: find the lowest process pid >= `from`, fill *out and
 * return that pid.  Return 0 if no process exists at or above `from`. */
typedef int (*tm_procfs_next_fn)(int from, struct tm_procfs_proc *out);

/* Register the per-kernel process-table accessors.  Call once at boot. */
void tm_procfs_init(tm_procfs_get_fn get, tm_procfs_next_fn next);

/* Resolve a path:
 *   0 -- not a /proc path, unknown pid, or unknown entry
 *   1 -- "/proc" or "/proc/"            (the root directory)
 *   2 -- "/proc/<pid>" for a live pid   (*pid_out set)
 *   3 -- "/proc/<pid>/info"             (*pid_out set)                 */
int tm_procfs_resolve(const char *path, int *pid_out);

/* Convenience: non-zero if `path` resolves to anything. */
int tm_procfs_path_exists(const char *path);

/* Render /proc/<pid>/info into `dst` (cap must be >= TM_PROCFS_INFO_MAX).
 * Returns the byte count (no NUL on the wire); 0 if the pid is gone. */
unsigned tm_procfs_info(int pid, char *dst, unsigned cap);

/* readdir over the /proc root.  *cursor is the next pid to consider
 * (start at 0); on success it advances past the emitted pid.  Writes the
 * decimal pid name (NUL-terminated) into name_out, its length into
 * *namelen_out, and TM_PROCFS_DT_DIR into *d_type_out.  Returns 1 if an
 * entry was produced, 0 at end of directory. */
int tm_procfs_readdir_root(unsigned long *cursor, char *name_out,
                           unsigned *namelen_out, int *d_type_out);

/* readdir over a /proc/<pid> directory: cursor 0 yields the single
 * "info" entry (DT_REG); any higher cursor is end-of-directory. */
int tm_procfs_readdir_piddir(unsigned long cursor, char *name_out,
                             unsigned *namelen_out, int *d_type_out);

#endif /* QSOE_TM_PROCFS_H */
