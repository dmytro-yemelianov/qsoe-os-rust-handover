/*
 * <libtaskman/cred.h> -- per-process credential / cwd / umask state.
 *
 * Every QSOE process carries this small state record.  The per-OS
 * taskman owns the process table and embeds tm_cred_state_t inside
 * each row; libtaskman provides the operations (chdir / getcwd /
 * umask / set_cred / self_info) that mutate it.  No kernel calls,
 * no IPC marshalling -- the caller hands us the relevant state
 * pointer and the absolute path / numeric arg.
 *
 * Wire-side glue (reading the path bytes out of the IPC buffer,
 * staging reply bytes) stays per-OS in each concrete taskman because
 * the message structure differs slightly between dispatchers and
 * because the path may need pre-validation against the resmgr the
 * caller's open() was speaking to.
 *
 * Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef LIBTASKMAN_CRED_H
#define LIBTASKMAN_CRED_H

#include <sys/qsoe.h>     /* pid_t, uid_t, gid_t, struct _cred_info */

#define TM_CWD_MAX  256

typedef struct tm_cred_state {
    char              cwd[TM_CWD_MAX];   /* NUL-terminated absolute path */
    unsigned          umask;             /* 0..0777 */
    struct _cred_info cred;              /* r/e/s uid + gid */
} tm_cred_state_t;

/* Initialise a state struct.  cwd = "/", umask = 0022, cred = all-root. */
void tm_cred_init(tm_cred_state_t *s);

/* Set cwd to `path` (absolute, NUL-terminated; length already known
 * from the caller).  Returns 0 on success, -ENAMETOOLONG if too long,
 * -EINVAL if not absolute.  No filesystem existence check -- the path
 * is taken on faith. */
int tm_cred_chdir(tm_cred_state_t *s, const char *path, unsigned path_len);

/* Copy cwd into *dst_buf (caller-sized), set *out_len to the byte
 * count written (excluding any NUL).  Returns 0; -ERANGE if cap is
 * too small for the cwd (no bytes written in that case). */
int tm_cred_getcwd(const tm_cred_state_t *s,
                   char *dst_buf, unsigned cap, unsigned *out_len);

/* Exchange-and-set umask.  *out_old gets the previous value; `set`
 * becomes the new value (clamped to 0777).  Pass set < 0 to leave
 * the mask unchanged (pure query). */
int tm_cred_umask(tm_cred_state_t *s, int set, unsigned *out_old);

/* Update credentials.  Pass 0xFFFFFFFF for any field to leave it
 * unchanged.  Returns 0 always; permission checks are the per-OS
 * taskman's responsibility (we just mutate the struct). */
int tm_cred_set(tm_cred_state_t *s,
                unsigned ruid_new, unsigned euid_new, unsigned suid_new,
                unsigned rgid_new, unsigned egid_new, unsigned sgid_new);

/* Snapshot accessor: copy out (pid, ppid, cred) for self-info
 * queries.  `pid` and `ppid` are passed in (looked up by the per-OS
 * taskman in its process table); `out_cred` reads our struct. */
void tm_cred_self_info(const tm_cred_state_t *s,
                       struct _cred_info *out_cred);

#endif /* LIBTASKMAN_CRED_H */
