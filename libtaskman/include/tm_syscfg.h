/*
 * <libtaskman/syscfg.h> -- system-configuration blob builder + walker.
 *
 * Each QSOE taskman that needs a TLV platform blob ("syscfg") --
 * timebase Hz, memory regions, PCI ECAM base, etc. -- builds it with
 * this module.  The BLOB FORMAT is the QSOE-neutral ABI in
 * <qsoe/syscfg.h>; this module builds and walks it.  Source of truth
 * for the platform data (FDT on QEMU, hard-coded for testbeds, board
 * firmware on real HW) is the per-OS taskman: it iterates that
 * source, calls our emit_* helpers to lay down tags, and serves the
 * blob to consumers (libc's hwi_*, in-process clock-freq init, PCI
 * ECAM mapping, ...).
 *
 * NQ today reaches the same goal via the kernel-built sysmap page
 * mapped read-only in every process; the syscfg path lives on for
 * LQ and for taskman-internal callers that need TLV emit/find
 * primitives.
 *
 * Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef LIBTASKMAN_SYSCFG_H
#define LIBTASKMAN_SYSCFG_H

#include <sys/qsoe.h>
#include <qsoe/syscfg.h>     /* TM_SYSCFG_TAG_*, TM_SYSCFG_MAX */

typedef struct tm_syscfg_state {
    unsigned char *buf;       /* caller-provided storage */
    unsigned       cap;
    unsigned       len;       /* bytes used so far */
    int            ready;     /* 1 once tm_syscfg_finalize() ran */
} tm_syscfg_state_t;

/* ---- Builder side --------------------------------------------------
 * Caller supplies a buffer big enough for the expected blob (typically
 * TM_SYSCFG_MAX = 864 bytes).  Emit tags in any order during boot;
 * call finalize() once when done -- it appends the END sentinel and
 * locks the blob for serving.  Every emit returns -1 if the blob
 * would overflow `cap` (caller should bump the buffer or skip tags).
 */
void tm_syscfg_init(tm_syscfg_state_t *s, void *buf, unsigned cap);

int tm_syscfg_emit(tm_syscfg_state_t *s, uint16_t id,
                   const void *payload, unsigned len);
int tm_syscfg_emit_u32(tm_syscfg_state_t *s, uint16_t id, uint32_t v);
int tm_syscfg_emit_u64(tm_syscfg_state_t *s, uint16_t id, uint64_t v);
int tm_syscfg_emit_asciz(tm_syscfg_state_t *s, uint16_t id, const char *str);

int tm_syscfg_finalize(tm_syscfg_state_t *s);

/* ---- Walker side --------------------------------------------------
 * All find_* functions are read-only and stateless w.r.t. the blob.
 * They return 0 on a hit, -1 on miss / not-finalized.
 */
int tm_syscfg_get(const tm_syscfg_state_t *s,
                  const void **out_blob, unsigned *out_len);

int tm_syscfg_find(const tm_syscfg_state_t *s, unsigned tag_id,
                   const void **out_ptr, unsigned *out_len);

int tm_syscfg_find_u32(const tm_syscfg_state_t *s, unsigned tag_id,
                       uint32_t *out);
int tm_syscfg_find_u64(const tm_syscfg_state_t *s, unsigned tag_id,
                       uint64_t *out);

#endif /* LIBTASKMAN_SYSCFG_H */
