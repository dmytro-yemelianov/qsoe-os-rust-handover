/*
 * Host tests for libtaskman's portable ELF view parser.
 *
 * These tests link the existing C implementation directly and capture the C
 * ABI/behavior before the Rust provider is wired into task-manager paths.
 */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <tm_elf.h>

#define EI_CLASS        4
#define EI_DATA         5
#define ELFCLASS64      2
#define ELFDATA2LSB     1
#define ET_EXEC         2
#define ET_DYN          3
#define EM_RISCV        243
#define PT_LOAD         1
#define PT_INTERP       3
#define ELF64_EHDR_LEN  64
#define ELF64_PHDR_LEN  56

#define CHECK(expr) do { \
    if (!(expr)) { \
        fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #expr); \
        exit(1); \
    } \
} while (0)

typedef struct {
    uint32_t type;
    uint32_t flags;
    uint64_t offset;
    uint64_t vaddr;
    uint64_t filesz;
    uint64_t memsz;
} phdr_spec_t;

static void put16(unsigned char *b, size_t off, uint16_t v)
{
    b[off] = (unsigned char) (v & 0xff);
    b[off + 1] = (unsigned char) ((v >> 8) & 0xff);
}

static void put32(unsigned char *b, size_t off, uint32_t v)
{
    b[off] = (unsigned char) (v & 0xff);
    b[off + 1] = (unsigned char) ((v >> 8) & 0xff);
    b[off + 2] = (unsigned char) ((v >> 16) & 0xff);
    b[off + 3] = (unsigned char) ((v >> 24) & 0xff);
}

static void put64(unsigned char *b, size_t off, uint64_t v)
{
    for (unsigned i = 0; i < 8; i++)
        b[off + i] = (unsigned char) ((v >> (i * 8)) & 0xff);
}

static phdr_spec_t load_segment(uint64_t vaddr, uint64_t filesz,
                                uint64_t memsz, uint32_t flags)
{
    phdr_spec_t ph = {
        .type = PT_LOAD,
        .flags = flags,
        .offset = 0x200,
        .vaddr = vaddr,
        .filesz = filesz,
        .memsz = memsz,
    };
    return ph;
}

static unsigned char *synthetic_elf(uint16_t type, const phdr_spec_t *phdrs,
                                    unsigned nphdrs, size_t *out_len)
{
    size_t len = 0x300;
    size_t phdr_end = ELF64_EHDR_LEN + nphdrs * ELF64_PHDR_LEN;
    if (len < phdr_end) len = phdr_end;
    for (unsigned i = 0; i < nphdrs; i++) {
        uint64_t end = phdrs[i].offset + phdrs[i].filesz;
        if (end > len) len = (size_t) end;
    }

    unsigned char *b = calloc(1, len);
    CHECK(b != NULL);

    b[0] = 0x7f; b[1] = 'E'; b[2] = 'L'; b[3] = 'F';
    b[EI_CLASS] = ELFCLASS64;
    b[EI_DATA] = ELFDATA2LSB;
    put16(b, 16, type);
    put16(b, 18, EM_RISCV);
    put32(b, 20, 1);
    put64(b, 24, 0x401000);
    put64(b, 32, ELF64_EHDR_LEN);
    put16(b, 52, ELF64_EHDR_LEN);
    put16(b, 54, ELF64_PHDR_LEN);
    put16(b, 56, (uint16_t) nphdrs);

    for (unsigned i = 0; i < nphdrs; i++) {
        size_t off = ELF64_EHDR_LEN + i * ELF64_PHDR_LEN;
        put32(b, off, phdrs[i].type);
        put32(b, off + 4, phdrs[i].flags);
        put64(b, off + 8, phdrs[i].offset);
        put64(b, off + 16, phdrs[i].vaddr);
        put64(b, off + 32, phdrs[i].filesz);
        put64(b, off + 40, phdrs[i].memsz);
        put64(b, off + 48, 0x1000);
    }

    *out_len = len;
    return b;
}

static void test_layout(void)
{
    CHECK(sizeof(tm_elf_phdr_t) == 40);
    CHECK(offsetof(tm_elf_view_t, blob) == 0);
    CHECK(offsetof(tm_elf_view_t, blob_size) == 8);
    CHECK(offsetof(tm_elf_view_t, entry) == 16);
    CHECK(offsetof(tm_elf_view_t, vaddr_lo) == 24);
    CHECK(offsetof(tm_elf_view_t, vaddr_hi) == 32);
    CHECK(offsetof(tm_elf_view_t, is_dyn) == 40);
    CHECK(offsetof(tm_elf_view_t, n_phdrs) == 44);
    CHECK(offsetof(tm_elf_view_t, phdrs) == 48);
    CHECK(offsetof(tm_elf_view_t, interp_path) == 368);
    CHECK(offsetof(tm_elf_view_t, phdr_count) == 394);
    CHECK(sizeof(tm_elf_view_t) == 400);
}

static void test_parse_loads_interp_and_range(void)
{
    phdr_spec_t phdrs[3] = {
        { PT_INTERP, 0, 0x180, 0, 14, 14 },
        load_segment(0x1000, 0x20, 0x40, ELF_PROT_READ | ELF_PROT_EXEC),
        load_segment(0x3000, 0x10, 0x80, ELF_PROT_READ | ELF_PROT_WRITE),
    };
    size_t len = 0;
    unsigned char *b = synthetic_elf(ET_DYN, phdrs, 3, &len);
    tm_elf_view_t view;

    memcpy(b + 0x180, "/lib/ld.so.1", 13);
    CHECK(tm_elf_parse(b, len, &view) == 0);
    CHECK(view.blob == b);
    CHECK(view.blob_size == len);
    CHECK(view.entry == 0x401000);
    CHECK(view.is_dyn == 1);
    CHECK(view.n_phdrs == 2);
    CHECK(view.vaddr_lo == 0x1000);
    CHECK(view.vaddr_hi == 0x3080);
    CHECK(view.phdr_off == ELF64_EHDR_LEN);
    CHECK(view.phdr_entsize == ELF64_PHDR_LEN);
    CHECK(view.phdr_count == 3);
    CHECK(view.interp_path == (const char *) (b + 0x180));
    CHECK(view.interp_len == 12);
    CHECK(view.phdrs[0].file_offset == 0x200);
    CHECK(view.phdrs[0].file_size == 0x20);
    CHECK(view.phdrs[0].vaddr == 0x1000);
    CHECK(view.phdrs[0].mem_size == 0x40);
    CHECK(view.phdrs[0].perms == (ELF_PROT_READ | ELF_PROT_EXEC));
    CHECK(view.phdrs[1].perms == (ELF_PROT_READ | ELF_PROT_WRITE));
    free(b);
}

static void test_zero_file_size_load_keeps_offset(void)
{
    phdr_spec_t ph = {
        .type = PT_LOAD,
        .flags = ELF_PROT_READ | ELF_PROT_WRITE,
        .offset = 0xffffffffULL,
        .vaddr = 0x8000,
        .filesz = 0,
        .memsz = 0x20,
    };
    size_t len = 0;
    unsigned char *b = synthetic_elf(ET_EXEC, &ph, 1, &len);
    tm_elf_view_t view;

    CHECK(tm_elf_parse(b, len, &view) == 0);
    CHECK(view.is_dyn == 0);
    CHECK(view.n_phdrs == 1);
    CHECK(view.phdrs[0].file_offset == 0xffffffffULL);
    free(b);
}

static void test_rejects_malformed_inputs(void)
{
    phdr_spec_t good_ph = load_segment(0x1000, 0x10, 0x20, ELF_PROT_READ);
    size_t len = 0;
    unsigned char *good = synthetic_elf(ET_EXEC, &good_ph, 1, &len);
    tm_elf_view_t view;

    good[0] = 0;
    CHECK(tm_elf_parse(good, len, &view) == -1);
    good[0] = 0x7f;

    put16(good, 18, 62);
    CHECK(tm_elf_parse(good, len, &view) == -1);
    put16(good, 18, EM_RISCV);

    put16(good, 16, 1);
    CHECK(tm_elf_parse(good, len, &view) == -1);
    put16(good, 16, ET_EXEC);

    put16(good, 54, ELF64_PHDR_LEN - 1);
    CHECK(tm_elf_parse(good, len, &view) == -1);
    put16(good, 54, ELF64_PHDR_LEN);

    put64(good, 32, len + 1);
    CHECK(tm_elf_parse(good, len, &view) == -1);
    free(good);

    phdr_spec_t filesz_gt_memsz = load_segment(0x1000, 0x30, 0x20,
                                               ELF_PROT_READ);
    unsigned char *bad = synthetic_elf(ET_EXEC, &filesz_gt_memsz, 1, &len);
    CHECK(tm_elf_parse(bad, len, &view) == -1);
    free(bad);

    phdr_spec_t interp = { PT_INTERP, 0, 0x200, 0, 4, 4 };
    bad = synthetic_elf(ET_EXEC, &interp, 1, &len);
    CHECK(tm_elf_parse(bad, len, &view) == -1);
    free(bad);
}

static void test_rejects_missing_load_and_too_many_loads(void)
{
    phdr_spec_t unknown = { 0x6474e550U, 0, 0, 0, 0, 0 };
    size_t len = 0;
    tm_elf_view_t view;
    unsigned char *b = synthetic_elf(ET_EXEC, &unknown, 1, &len);

    CHECK(tm_elf_parse(b, len, &view) == -1);
    free(b);

    phdr_spec_t many[TM_ELF_MAX_PHDRS + 1];
    for (unsigned i = 0; i < TM_ELF_MAX_PHDRS + 1; i++)
        many[i] = load_segment(0x1000, 1, 1, ELF_PROT_READ);
    b = synthetic_elf(ET_EXEC, many, TM_ELF_MAX_PHDRS + 1, &len);
    CHECK(tm_elf_parse(b, len, &view) == -1);
    free(b);
}

static void test_rejects_wrapped_segment_end(void)
{
    phdr_spec_t ph = load_segment(UINT64_MAX - 0x10, 1, 0x40,
                                  ELF_PROT_READ);
    size_t len = 0;
    tm_elf_view_t view;
    unsigned char *b = synthetic_elf(ET_EXEC, &ph, 1, &len);

    CHECK(tm_elf_parse(b, len, &view) == -1);
    free(b);
}

#include "../libtaskman/src/elf.c"

int main(void)
{
    test_layout();
    test_parse_loads_interp_and_range();
    test_zero_file_size_load_keeps_offset();
    test_rejects_malformed_inputs();
    test_rejects_missing_load_and_too_many_loads();
    test_rejects_wrapped_segment_end();
    puts("tm_elf_model_test: ok");
    return 0;
}
