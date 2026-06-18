/*
 * <libtaskman/pathmgr.h> -- taskman's path namespace registry.
 *
 * Prefix-tree of nodes, one node per path component.  Each node may
 * carry an attached "object" identifying which server (pid, chid)
 * handles requests on that prefix.  Lookup is longest-prefix:
 * tm_pathmgr_resolve walks the tree component-by-component and
 * returns the deepest node with an attached object plus the number of
 * path bytes that matched (so future resmgrs can serve subtrees).
 *
 * Storage is a fixed pool; nodes are bump-allocated.  Sufficient for
 * the early-system server registrations taskman makes (a few dozen);
 * a freelist becomes necessary once a writable filesystem adds and
 * removes leaves at runtime.
 *
 * Inspired by QRV's tNode (~/proj/QRV-OS/taskman/include/pathmgr_node.h)
 * but written from scratch.  Public surface here is OS-independent:
 * pid_t and int only, nothing kernel-specific.
 *
 * Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef LIBTASKMAN_PATHMGR_H
#define LIBTASKMAN_PATHMGR_H

#include <stdint.h>       /* uint8_t, uint64_t */
#include <sys/qsoe.h>     /* pid_t */

/* Handler kinds.  HANDLER_EXTERNAL is the production case (a real
 * resmgr process serves the prefix).  The TASKMAN_* slots let taskman
 * itself handle a prefix in-process during early boot before the
 * corresponding resmgr is up. */
#define PATHMGR_HANDLER_EXTERNAL        0
#define PATHMGR_HANDLER_TASKMAN_CONSOLE 1
#define PATHMGR_HANDLER_TASKMAN_CPIOFS  2
#define PATHMGR_HANDLER_TASKMAN_NULL    3
#define PATHMGR_HANDLER_TASKMAN_ZERO    4
#define PATHMGR_HANDLER_TASKMAN_PMDIR   5
#define PATHMGR_HANDLER_TASKMAN_SYSFS   6   /* synthetic read-only /sys */
#define PATHMGR_HANDLER_TASKMAN_PROCFS  7   /* synthetic read-only /proc */

typedef struct tm_pathmgr_obj {
    pid_t    server_pid;
    int      server_chid;
    unsigned flags;
    unsigned handler_kind;
} tm_pathmgr_obj_t;

/* Initialise registry.  Allocates the root node.  Call once at boot. */
void tm_pathmgr_init(void);

/* Register obj at the given absolute path (must start with '/').  The
 * tree is grown on demand.  Returns 0 on success, -errno on failure
 * (-EINVAL bad path or path already taken, -ENOMEM pool exhausted). */
int tm_pathmgr_register(const char *path, const tm_pathmgr_obj_t *obj);

/* Drop every EXTERNAL registration owned by `pid`.  Called from the
 * taskman proc-detach path so a server's registrations don't outlive
 * it: a stale entry makes clients resolve a ghost (pid, chid) pair
 * and park forever in MsgSend, and blocks the relaunched server's
 * re-register with -EINVAL.  Nodes stay in the bump pool and are
 * reused by name on the next register.  Taskman-internal handlers
 * (console/cpiofs/null/...) are never dropped.  Returns the number of
 * attachments removed. */
int tm_pathmgr_unregister_pid(pid_t pid);

/* Longest-prefix lookup.  On match, fills *out with the deepest
 * matching object and *out_consumed_bytes with the number of bytes in
 * `path` that the prefix covered.  Returns 0 on match, -ENOENT if no
 * node along the path carried an object. */
int tm_pathmgr_resolve(const char *path,
                       tm_pathmgr_obj_t *out,
                       unsigned *out_consumed_bytes);

/* Update an existing path's attached object to point at a different
 * server.  Used to swap /dev/console between handlers after a real
 * driver comes up.  Returns 0 on success, -ENOENT if the path doesn't
 * exist, -EINVAL on bad input.  The path must already be registered;
 * this isn't a create-or-update. */
int tm_pathmgr_repath(const char *path, const tm_pathmgr_obj_t *new_obj);

/* Create a pathmgr symlink.  After this call, resolving `link_path`
 * walks the registered target_path and returns whatever IT resolves
 * to -- i.e. a symlink to /dev/console follows the console wherever
 * it's repath'd.  Maximum one redirection per resolve (no chained
 * symlinks).  Returns 0 on success, -EINVAL on bad input, -ENOMEM if
 * the pool is full, -EEXIST if link_path is already registered with
 * a different attachment. */
int tm_pathmgr_symlink(const char *link_path, const char *target_path);

/* Like tm_pathmgr_expand_symlink, but the symlink lives in the boot cpio
 * (a top-level cross-fs mount link such as /etc -> /usr/conf, declared
 * once as an `ln -sf` symlink in the modpkg recipe).  If the FIRST
 * component of `path` names a cpio symlink, splice its target + the
 * remainder into `out` (NUL-terminated, clamped to `cap`) and return 1;
 * else return 0 and leave the caller to use the original path.  One
 * level only.  The cpio is the single source of truth for these links --
 * no in-memory node is registered, so they appear in `ls` (real cpio
 * inode) without duplicating in the readdir merge. */
int tm_pathmgr_expand_symlink_cpio(const uint8_t *cpio, uint64_t size,
                                   const char *path,
                                   char *out, unsigned cap);

/* Expand a leading pathmgr symlink in `path`.  If some prefix of `path`
 * names a registered symlink, write target+remainder to `out` (NUL-
 * terminated, clamped to out_cap) and return 1.  If no symlink lies
 * along the path, or the result would overflow, return 0 and leave the
 * caller to use the original path.  One level only (no chained links).
 *
 * This is what makes a cross-fs link like /etc -> /usr/conf work for an
 * EXTERNAL resmgr: tm_pathmgr_resolve already redirects /etc/passwd to
 * the /usr mount's (pid,chid), but the server keys on the path string it
 * receives -- so the open path must be rewritten to /usr/conf/passwd
 * before it reaches the fs server.  Taskman-internal handlers re-resolve
 * the path themselves and don't need this. */
int tm_pathmgr_expand_symlink(const char *path, char *out, unsigned out_cap);

/* Enumerate direct children of the pathmgr node at `path`.  `idx` is
 * zero-based; on a match the child's name (NUL-terminated) is written
 * to `name_out` (caller-sized; clamped to cap) and *namelen gets its
 * length.  Returns 0 on hit, -ENOENT past the end, -EINVAL for a bad
 * path / unknown node.  Used by tm_pmdir_readdir (for /dev) and by
 * tm_cpiofs_readdir (to merge pathmgr children of "/" with CPIO
 * entries so ls / sees "dev" alongside "bin", "sbin"). */
int tm_pathmgr_child_at(const char *path, unsigned idx,
                        char *name_out, unsigned name_cap,
                        unsigned *out_namelen);

#endif /* LIBTASKMAN_PATHMGR_H */
