/*
 * tm_sysfs.h -- OS-independent /sys model for every QSOE taskman.
 *
 * The read-only /sys pseudo-filesystem ("the kernel describes itself")
 * is identical in shape across QSOE/N and QSOE/L: the same four entries,
 * the same path-resolution and directory-listing rules.  Only two things
 * differ per kernel and stay OUT of this module:
 *
 *   1. Where the strings come from -- NQ snapshots them from the
 *      kernel-built sysmap page; LQ reads taskman's syscfg blob.  Each
 *      taskman gathers board/cmdline/version/builddate its own way and
 *      hands them to tm_sysfs_init().
 *   2. How the entries are served -- NQ wires the OCB framework, LQ wires
 *      its path/io.c handler_kind dispatch.  Both call tm_sysfs_resolve()
 *      / tm_sysfs_content() / the directory accessors below.
 *
 * Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef TM_SYSFS_H
#define TM_SYSFS_H

/* Snapshot the four /sys file contents into this module's own buffers.
 * Each source string is copied verbatim and a trailing '\n' appended so
 * `cat /sys/<x>` looks right at the shell; a NULL or empty source yields
 * a one-byte "\n".  Idempotent -- safe to call again after a syscfg/
 * sysmap update. */
void tm_sysfs_init(const char *osname, const char *board, const char *cmdline,
                   const char *version, const char *builddate);

/* Resolve an absolute path against the /sys tree:
 *   1 -- path is "/sys" or "/sys/" (the root directory)
 *   2 -- path is "/sys/<name>" for a known entry; *idx_out is set
 *   0 -- not a /sys path, or an unknown /sys entry  */
int tm_sysfs_resolve(const char *path, unsigned *idx_out);

/* Convenience: nonzero if the path is the /sys root or a known entry. */
int tm_sysfs_path_exists(const char *path);

/* File content for entry `idx` (from tm_sysfs_resolve == 2).  Returns the
 * data pointer and sets *len_out to its byte length (includes the
 * trailing '\n').  Returns NULL for an out-of-range index. */
const char *tm_sysfs_content(unsigned idx, unsigned *len_out);

/* Directory listing, in readdir order. */
unsigned    tm_sysfs_nentries(void);
const char *tm_sysfs_entry_name(unsigned idx);

#endif /* TM_SYSFS_H */
