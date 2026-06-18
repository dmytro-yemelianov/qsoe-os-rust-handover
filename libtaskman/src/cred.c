/*
 * libtaskman/src/cred.c -- per-process cwd / umask / uid-gid operations.
 *
 * Plain-state operations on a tm_cred_state_t the per-OS taskman owns
 * and embeds in its process record.  No kernel calls, no IPC, no
 * libtaskman_seams().  Lifted from the equivalent fragments scattered
 * across LQ taskman's proc/process.c (tm_chdir, tm_getcwd, tm_umask,
 * tm_set_cred, tm_proc_self_info -- the parts that mutate the state
 * struct only, not the per-OS process-table lookups around them).
 *
 * Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
 * SPDX-License-Identifier: Apache-2.0
 */

#include <tm_cred.h>
#include <qsoe/tm_msgs.h>      /* TM_CRED_KEEP */

void tm_cred_init(tm_cred_state_t *s)
{
    if (!s) return;
    s->cwd[0] = '/';
    s->cwd[1] = 0;
    s->umask  = 0022u;
    s->cred.ruid = s->cred.euid = s->cred.suid = 0;
    s->cred.rgid = s->cred.egid = s->cred.sgid = 0;
    s->cred.ngroups = 0;
}

int tm_cred_chdir(tm_cred_state_t *s, const char *path, unsigned path_len)
{
    if (!s || !path) return -EINVAL;
    if (path_len == 0 || path_len >= TM_CWD_MAX) return -ENAMETOOLONG;
    /* Absolute paths only.  Relative paths need cwd-relative
     * resolution against a filesystem that can verify the destination
     * exists. */
    if (path[0] != '/') return -EINVAL;
    for (unsigned i = 0; i < path_len; ++i) s->cwd[i] = path[i];
    s->cwd[path_len] = 0;
    return 0;
}

int tm_cred_getcwd(const tm_cred_state_t *s,
                   char *dst_buf, unsigned cap, unsigned *out_len)
{
    if (!s || !dst_buf || cap == 0 || !out_len) return -EINVAL;
    unsigned len = 0;
    while (s->cwd[len] != 0 && len < TM_CWD_MAX) ++len;
    if (len > cap) return -ERANGE;
    for (unsigned i = 0; i < len; ++i) dst_buf[i] = s->cwd[i];
    *out_len = len;
    return 0;
}

int tm_cred_umask(tm_cred_state_t *s, int set, unsigned *out_old)
{
    if (!s || !out_old) return -EINVAL;
    *out_old = s->umask;
    if (set >= 0) s->umask = (unsigned)set & 0777u;
    return 0;
}

int tm_cred_set(tm_cred_state_t *s,
                unsigned ruid_new, unsigned euid_new, unsigned suid_new,
                unsigned rgid_new, unsigned egid_new, unsigned sgid_new)
{
    if (!s) return -EINVAL;
    /* TM_CRED_KEEP = "leave alone".  The per-OS taskman calls
     * tm_cred_change_permitted() before us; this body just mutates. */
    if (ruid_new != TM_CRED_KEEP) s->cred.ruid = (uid_t)ruid_new;
    if (euid_new != TM_CRED_KEEP) s->cred.euid = (uid_t)euid_new;
    if (suid_new != TM_CRED_KEEP) s->cred.suid = (uid_t)suid_new;
    if (rgid_new != TM_CRED_KEEP) s->cred.rgid = (gid_t)rgid_new;
    if (egid_new != TM_CRED_KEEP) s->cred.egid = (gid_t)egid_new;
    if (sgid_new != TM_CRED_KEEP) s->cred.sgid = (gid_t)sgid_new;
    return 0;
}

/* "Held" test for one requested id against the process's matching id set
 * (real/effective/saved).  TM_CRED_KEEP ("unchanged") always passes. */
static int cred_id_held(unsigned v, uid_t a, uid_t b, uid_t c)
{
    return v == TM_CRED_KEEP || v == (unsigned)a ||
           v == (unsigned)b || v == (unsigned)c;
}

int tm_cred_change_permitted(const struct _cred_info *cur,
                             unsigned ruid_new, unsigned euid_new, unsigned suid_new,
                             unsigned rgid_new, unsigned egid_new, unsigned sgid_new)
{
    if (!cur) return 0;
    if (cur->euid == 0) return 1;          /* root: unrestricted */
    return cred_id_held(ruid_new, cur->ruid, cur->euid, cur->suid) &&
           cred_id_held(euid_new, cur->ruid, cur->euid, cur->suid) &&
           cred_id_held(suid_new, cur->ruid, cur->euid, cur->suid) &&
           cred_id_held(rgid_new, cur->rgid, cur->egid, cur->sgid) &&
           cred_id_held(egid_new, cur->rgid, cur->egid, cur->sgid) &&
           cred_id_held(sgid_new, cur->rgid, cur->egid, cur->sgid);
}

void tm_cred_self_info(const tm_cred_state_t *s,
                       struct _cred_info *out_cred)
{
    if (!s || !out_cred) return;
    *out_cred = s->cred;
}
