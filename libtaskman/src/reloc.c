/*
 * libtaskman/src/reloc.c -- RV64 relocation walker, shared.
 *
 * See <libtaskman/reloc.h> for the API and design rationale.  This
 * file is pure byte arithmetic over the caller's file blob; memory
 * writes go through a callback so per-kernel taskmen can plug in
 * their own "write 8 bytes at child VA X" implementation.
 *
 * Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
 * SPDX-License-Identifier: Apache-2.0
 */

#include <tm_reloc.h>

/* ELF64 dynamic / reloc / sym structs.  Kept local so libtaskman
 * stays freestanding (no <elf.h> dependency). */
#define PT_DYNAMIC        2
#define DT_NULL           0
#define DT_HASH           4
#define DT_STRTAB         5
#define DT_SYMTAB         6
#define DT_RELA           7
#define DT_RELASZ         8
#define DT_RELAENT        9
#define DT_PLTRELSZ       2
#define DT_JMPREL        23
#define DT_GNU_HASH 0x6ffffef5

#define R_RISCV_64        2
#define R_RISCV_RELATIVE  3
#define R_RISCV_JUMP_SLOT 5

typedef struct {
    int64_t  d_tag;
    uint64_t d_val;
} elf64_dyn_t;

typedef struct {
    uint64_t r_offset;
    uint64_t r_info;
    int64_t  r_addend;
} elf64_rela_t;

typedef struct {
    uint32_t      st_name;
    unsigned char st_info, st_other;
    uint16_t      st_shndx;
    uint64_t      st_value;
    uint64_t      st_size;
} elf64_sym_t;

/* The file phdr table -- not in tm_elf_view_t.phdrs (which only
 * lists PT_LOADs), so we walk the file directly to find PT_DYNAMIC. */
typedef struct {
    uint32_t p_type, p_flags;
    uint64_t p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align;
} elf64_file_phdr_t;

/* Resolve a runtime VA back to a byte inside the caller's file blob.
 * Works by walking PT_LOAD's: the byte at runtime VA `v` lives at
 *   file_offset = (v - bias - load.vaddr) + load.file_offset
 * within the PT_LOAD whose vaddr-range covers (v - bias).  Returns
 * NULL if no PT_LOAD covers v or the resulting file offset would
 * land past blob_size. */
static const unsigned char *
va_to_blob(const tm_elf_view_t *view, unsigned long bias, uint64_t v)
{
    uint64_t rel = v - bias;
    for (unsigned i = 0; i < view->n_phdrs; i++) {
        const tm_elf_phdr_t *ld = &view->phdrs[i];
        if (rel >= ld->vaddr && rel < ld->vaddr + ld->file_size) {
            uint64_t fo = (rel - ld->vaddr) + ld->file_offset;
            if (fo >= view->blob_size) return 0;
            return (const unsigned char *) view->blob + fo;
        }
    }
    return 0;
}

static int s_streq(const char *a, const char *b)
{
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

/* Linear walk over an external resolver's dynsym.  Returns the
 * runtime VA of `name`, or 0 if not present / undefined locally
 * in the resolver image. */
static unsigned long
external_lookup(const tm_reloc_resolver_t *ext, const char *name)
{
    if (!ext || !ext->symtab || !ext->strtab) return 0;
    const elf64_sym_t *symtab = ext->symtab;
    const char *strtab = ext->strtab;
    for (unsigned long i = 1; i < ext->nsyms; i++) {
        if (symtab[i].st_value == 0) continue;
        if (s_streq(strtab + symtab[i].st_name, name))
            return ext->base + symtab[i].st_value;
    }
    return 0;
}

/* Locate PT_DYNAMIC's contents in the file blob.  Returns a pointer
 * to the first elf64_dyn_t entry, or NULL if the image has no
 * PT_DYNAMIC (static-linked ET_EXEC). */
static const elf64_dyn_t *
find_dynamic_in_blob(const tm_elf_view_t *view)
{
    const unsigned char *bp = (const unsigned char *) view->blob;
    const elf64_file_phdr_t *phdrs =
        (const elf64_file_phdr_t *) (bp + view->phdr_off);
    for (unsigned i = 0; i < view->phdr_count; i++) {
        if (phdrs[i].p_type == PT_DYNAMIC) {
            if (phdrs[i].p_offset + phdrs[i].p_filesz > view->blob_size)
                return 0;
            return (const elf64_dyn_t *) (bp + phdrs[i].p_offset);
        }
    }
    return 0;
}

/* Walk DT_HASH (preferred) or DT_GNU_HASH to derive the dynsym entry
 * count.  Returns 0 on failure -- caller handles. */
static unsigned long
derive_nsyms(const elf64_dyn_t *dyn, const tm_elf_view_t *view,
             unsigned long bias)
{
    uint64_t hash_va = 0, gnu_hash_va = 0;
    for (const elf64_dyn_t *d = dyn; d->d_tag != DT_NULL; d++) {
        if (d->d_tag == DT_HASH)     hash_va     = d->d_val;
        if (d->d_tag == DT_GNU_HASH) gnu_hash_va = d->d_val;
    }
    if (hash_va) {
        const uint32_t *h = (const uint32_t *) va_to_blob(view, bias,
                                                          hash_va + bias);
        if (!h) return 0;
        return h[1];   /* nchain */
    }
    if (gnu_hash_va) {
        const uint32_t *h = (const uint32_t *) va_to_blob(view, bias,
                                                          gnu_hash_va + bias);
        if (!h) return 0;
        uint32_t nbuckets   = h[0];
        uint32_t symoffset  = h[1];
        uint32_t bloom_size = h[2];
        const uint32_t *buckets = (const uint32_t *)
            ((const unsigned char *) h + 16 + bloom_size * 8);
        const uint32_t *chain = buckets + nbuckets;
        uint32_t max_bucket = 0;
        for (uint32_t i = 0; i < nbuckets; i++)
            if (buckets[i] > max_bucket) max_bucket = buckets[i];
        if (max_bucket < symoffset) return symoffset;
        uint32_t i = max_bucket - symoffset;
        while ((chain[i] & 1) == 0) i++;
        return max_bucket + (i - (max_bucket - symoffset)) + 1;
    }
    return 0;
}

int tm_reloc_init_resolver(const tm_elf_view_t *view, unsigned long bias,
                            tm_reloc_resolver_t *out)
{
    if (!view || !out) return -1;
    const elf64_dyn_t *dyn = find_dynamic_in_blob(view);
    if (!dyn) return -1;

    uint64_t symtab_va = 0, strtab_va = 0;
    for (const elf64_dyn_t *d = dyn; d->d_tag != DT_NULL; d++) {
        if (d->d_tag == DT_SYMTAB) symtab_va = d->d_val;
        if (d->d_tag == DT_STRTAB) strtab_va = d->d_val;
    }
    if (!symtab_va || !strtab_va) return -1;

    const void *symtab = va_to_blob(view, bias, symtab_va + bias);
    const char *strtab = (const char *) va_to_blob(view, bias,
                                                   strtab_va + bias);
    if (!symtab || !strtab) return -1;

    unsigned long nsyms = derive_nsyms(dyn, view, bias);
    if (nsyms == 0) return -1;

    out->base   = bias;
    out->symtab = symtab;
    out->strtab = strtab;
    out->nsyms  = nsyms;
    return 0;
}

int tm_reloc_apply(const tm_elf_view_t *view,
                    unsigned long bias,
                    const tm_reloc_resolver_t *ext,
                    tm_reloc_write_q_fn write_cb,
                    tm_reloc_skip_log_fn skip_log,
                    void *user,
                    unsigned long *out_applied,
                    unsigned long *out_total,
                    unsigned long *out_skipped)
{
    unsigned long applied = 0, total = 0, skipped = 0;
    int rc = 0;

    const elf64_dyn_t *dyn = find_dynamic_in_blob(view);
    if (!dyn) goto done;   /* no PT_DYNAMIC -- nothing to do, not an error */

    uint64_t rela_va = 0, rela_sz = 0, rela_ent = sizeof(elf64_rela_t);
    uint64_t jmprel_va = 0, jmprel_sz = 0;
    uint64_t symtab_va = 0, strtab_va = 0;
    for (const elf64_dyn_t *d = dyn; d->d_tag != DT_NULL; d++) {
        switch (d->d_tag) {
        case DT_RELA:     rela_va   = d->d_val; break;
        case DT_RELASZ:   rela_sz   = d->d_val; break;
        case DT_RELAENT:  rela_ent  = d->d_val; break;
        case DT_JMPREL:   jmprel_va = d->d_val; break;
        case DT_PLTRELSZ: jmprel_sz = d->d_val; break;
        case DT_SYMTAB:   symtab_va = d->d_val; break;
        case DT_STRTAB:   strtab_va = d->d_val; break;
        }
    }

    const elf64_sym_t *symtab = symtab_va ?
        (const elf64_sym_t *) va_to_blob(view, bias, symtab_va + bias) : 0;
    const char *strtab = strtab_va ?
        (const char *) va_to_blob(view, bias, strtab_va + bias) : 0;

    /* Walk a single Rela vector. */
#define WALK_RELA(blob_va, blob_sz, entsize)                                \
    do {                                                                    \
        if (!(blob_va) || !(blob_sz)) break;                                \
        const elf64_rela_t *rela = (const elf64_rela_t *)                   \
            va_to_blob(view, bias, (blob_va) + bias);                       \
        if (!rela) { rc = -1; goto done; }                                  \
        unsigned long n = (unsigned long) ((blob_sz) / (entsize));          \
        total += n;                                                         \
        for (unsigned long i = 0; i < n; i++) {                             \
            unsigned type = (unsigned) (rela[i].r_info & 0xffffffffu);      \
            unsigned sidx = (unsigned) (rela[i].r_info >> 32);              \
            uint64_t loc_va = rela[i].r_offset + bias;                      \
            uint64_t val = 0;                                               \
            int will_apply = 1;                                             \
            switch (type) {                                                 \
            case R_RISCV_RELATIVE:                                          \
                val = (uint64_t)((int64_t) bias + rela[i].r_addend);        \
                break;                                                      \
            case R_RISCV_64:                                                \
            case R_RISCV_JUMP_SLOT: {                                       \
                if (!symtab || !strtab) { will_apply = 0; break; }          \
                int is_extern = (symtab[sidx].st_shndx == 0);               \
                uint64_t resolved = 0;                                      \
                if (!is_extern && symtab[sidx].st_value != 0)               \
                    resolved = symtab[sidx].st_value + bias;                \
                else if (ext)                                               \
                    resolved = external_lookup(ext,                         \
                                strtab + symtab[sidx].st_name);             \
                if (resolved == 0) {                                        \
                    if (skip_log)                                           \
                        skip_log(user,                                      \
                                 strtab + symtab[sidx].st_name);            \
                    /* Eager-bind: write NULL (val is already 0) instead    \
                     * of leaving the raw link-time bytes.  A lazy PLT      \
                     * slot's initial value is this object's own PLT[0]     \
                     * offset; left unbiased it sends a call to a low       \
                     * address (the pre-eager-binding crash).  0 makes a    \
                     * weak undefined read as NULL and a missing strong     \
                     * call fault cleanly at PC=0 -- name already logged    \
                     * above.  Deferring to first-call is unacceptable for  \
                     * hard-real-time, so nothing is left unbound. */       \
                    break;                                                  \
                }                                                           \
                val = resolved + (uint64_t) rela[i].r_addend;               \
                break;                                                      \
            }                                                               \
            default:                                                        \
                will_apply = 0;                                             \
                break;                                                      \
            }                                                               \
            if (will_apply) {                                               \
                if (write_cb(user, loc_va, val) != 0) {                     \
                    rc = -1; goto done;                                     \
                }                                                           \
                applied++;                                                  \
            } else {                                                        \
                skipped++;                                                  \
            }                                                               \
        }                                                                   \
    } while (0)

    WALK_RELA(rela_va,   rela_sz,   rela_ent);
    WALK_RELA(jmprel_va, jmprel_sz, sizeof(elf64_rela_t));

#undef WALK_RELA

done:
    if (out_applied) *out_applied = applied;
    if (out_total)   *out_total   = total;
    if (out_skipped) *out_skipped = skipped;
    return rc;
}
