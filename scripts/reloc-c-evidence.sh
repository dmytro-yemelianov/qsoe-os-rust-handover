#!/usr/bin/env bash
#
# Capture focused C relocation evidence for libtaskman/src/reloc.c.

set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAKE="${MAKE:-make}"
CC="${CC:-cc}"
WORKDIR="${RELOC_C_EVIDENCE_WORKDIR:-$ROOT/build/reloc-c-evidence}"
BOOT_LOG="$WORKDIR/boot-reloc-c-evidence.log"
SUMMARY="$WORKDIR/summary.txt"
RELOC_SRC="$ROOT/libtaskman/src/reloc.c"
RELOC_HDR="$ROOT/libtaskman/include/tm_reloc.h"
FIXTURE_C="$WORKDIR/reloc_c_fixture.c"
FIXTURE_BIN="$WORKDIR/reloc_c_fixture"
FIXTURE_LOG="$WORKDIR/reloc-c-fixture.log"

fail() {
    printf 'reloc-c-evidence: %s\n' "$*" >&2
    exit 1
}

require_source_fixed() {
    pattern="$1"
    label="$2"
    if ! grep -Fq "$pattern" "$RELOC_SRC"; then
        fail "missing source evidence: $label ($pattern)"
    fi
}

require_header_fixed() {
    pattern="$1"
    label="$2"
    if ! grep -Fq "$pattern" "$RELOC_HDR"; then
        fail "missing header evidence: $label ($pattern)"
    fi
}

require_log_regex() {
    pattern="$1"
    label="$2"
    if ! grep -Eq "$pattern" "$BOOT_LOG"; then
        fail "missing boot evidence: $label ($pattern)"
    fi
}

reject_log_fixed() {
    pattern="$1"
    label="$2"
    if grep -Fq "$pattern" "$BOOT_LOG"; then
        fail "unexpected boot evidence: $label ($pattern)"
    fi
}

mkdir -p "$WORKDIR"

"$ROOT/scripts/apply-component-overrides.sh"

require_source_fixed 'int tm_reloc_apply' 'C relocation walker entry point'
require_source_fixed 'int tm_reloc_init_resolver' 'C external resolver entry point'
require_source_fixed 'external_lookup' 'external symbol lookup path'
require_source_fixed 'R_RISCV_RELATIVE' 'relative relocation handling'
require_source_fixed 'R_RISCV_JUMP_SLOT' 'jump-slot relocation handling'
require_source_fixed 'skip_log' 'per-symbol skip logger path'
require_source_fixed 'Eager-bind: write NULL' 'unresolved external eager-null behavior'
require_header_fixed 'tm_reloc_skip_log_fn' 'skip logger API'
require_header_fixed 'out_skipped' 'unsupported relocation skip counter API'

echo "reloc-c-evidence: running existing ELF relocation type fixture"
"$MAKE" -C "$ROOT" --no-print-directory check-elf-reloc-fixture

cat > "$FIXTURE_C" <<'EOF_C'
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <tm_elf.h>
#include <tm_reloc.h>

#define PT_DYNAMIC        2u
#define DT_NULL           0
#define DT_HASH           4
#define DT_STRTAB         5
#define DT_SYMTAB         6
#define DT_RELA           7
#define DT_RELASZ         8
#define DT_RELAENT        9
#define DT_PLTRELSZ       2
#define DT_JMPREL        23

#define R_RISCV_64        2u
#define R_RISCV_RELATIVE  3u
#define R_RISCV_JUMP_SLOT 5u
#define R_RISCV_UNKNOWN   99u

#define BLOB_SIZE      4096u
#define PHDR_OFF       0x40u
#define DYN_OFF        0x200u
#define RELA_OFF       0x300u
#define JMPREL_OFF     0x400u
#define SYMTAB_OFF     0x500u
#define STRTAB_OFF     0x700u
#define HASH_OFF       0x900u
#define WRITE_BASE     0x0a00u
#define TARGET_BIAS    0x400000UL
#define RESOLVER_BIAS  0x800000UL

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

typedef struct {
    uint32_t p_type, p_flags;
    uint64_t p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align;
} elf64_file_phdr_t;

typedef struct {
    uint64_t vaddr;
    uint64_t value;
} write_record_t;

typedef struct {
    write_record_t writes[8];
    unsigned write_count;
    char skip_name[64];
    unsigned skip_count;
} fixture_state_t;

static unsigned char blob[BLOB_SIZE];

static uint64_t r_info(unsigned sym, unsigned type)
{
    return ((uint64_t)sym << 32) | (uint64_t)type;
}

static void expect(int ok, const char *msg)
{
    if (!ok) {
        fprintf(stderr, "reloc C fixture failed: %s\n", msg);
        exit(1);
    }
}

static void put_string(char *strtab, uint32_t *off, const char *s)
{
    size_t n = strlen(s) + 1;
    memcpy(strtab + *off, s, n);
    *off += (uint32_t)n;
}

static tm_elf_view_t make_view(void)
{
    memset(blob, 0, sizeof blob);

    elf64_file_phdr_t *file_phdr = (elf64_file_phdr_t *)(void *)(blob + PHDR_OFF);
    file_phdr[0].p_type = PT_DYNAMIC;
    file_phdr[0].p_offset = DYN_OFF;
    file_phdr[0].p_filesz = 8 * sizeof(elf64_dyn_t);

    elf64_dyn_t *dyn = (elf64_dyn_t *)(void *)(blob + DYN_OFF);
    dyn[0] = (elf64_dyn_t){ DT_RELA, RELA_OFF };
    dyn[1] = (elf64_dyn_t){ DT_RELASZ, 5 * sizeof(elf64_rela_t) };
    dyn[2] = (elf64_dyn_t){ DT_RELAENT, sizeof(elf64_rela_t) };
    dyn[3] = (elf64_dyn_t){ DT_JMPREL, JMPREL_OFF };
    dyn[4] = (elf64_dyn_t){ DT_PLTRELSZ, sizeof(elf64_rela_t) };
    dyn[5] = (elf64_dyn_t){ DT_SYMTAB, SYMTAB_OFF };
    dyn[6] = (elf64_dyn_t){ DT_STRTAB, STRTAB_OFF };
    dyn[7] = (elf64_dyn_t){ DT_HASH, HASH_OFF };
    dyn[8] = (elf64_dyn_t){ DT_NULL, 0 };

    char *strtab = (char *)(void *)(blob + STRTAB_OFF);
    uint32_t off = 1;
    uint32_t local_name = off;
    put_string(strtab, &off, "local_func");
    uint32_t puts_name = off;
    put_string(strtab, &off, "puts");
    uint32_t missing_name = off;
    put_string(strtab, &off, "missing_symbol");

    elf64_sym_t *sym = (elf64_sym_t *)(void *)(blob + SYMTAB_OFF);
    sym[1].st_name = local_name;
    sym[1].st_shndx = 1;
    sym[1].st_value = 0x1234;
    sym[2].st_name = puts_name;
    sym[2].st_shndx = 0;
    sym[2].st_value = 0x5678;
    sym[3].st_name = missing_name;
    sym[3].st_shndx = 0;
    sym[3].st_value = 0;

    uint32_t *hash = (uint32_t *)(void *)(blob + HASH_OFF);
    hash[0] = 1;  /* nbucket */
    hash[1] = 4;  /* nchain */

    elf64_rela_t *rela = (elf64_rela_t *)(void *)(blob + RELA_OFF);
    rela[0] = (elf64_rela_t){ WRITE_BASE + 0x00, r_info(0, R_RISCV_RELATIVE), 0x33 };
    rela[1] = (elf64_rela_t){ WRITE_BASE + 0x08, r_info(1, R_RISCV_64), 7 };
    rela[2] = (elf64_rela_t){ WRITE_BASE + 0x10, r_info(2, R_RISCV_64), 9 };
    rela[3] = (elf64_rela_t){ WRITE_BASE + 0x18, r_info(3, R_RISCV_64), 0 };
    rela[4] = (elf64_rela_t){ WRITE_BASE + 0x20, r_info(0, R_RISCV_UNKNOWN), 0 };

    elf64_rela_t *jmprel = (elf64_rela_t *)(void *)(blob + JMPREL_OFF);
    jmprel[0] = (elf64_rela_t){ WRITE_BASE + 0x28, r_info(2, R_RISCV_JUMP_SLOT), 11 };

    tm_elf_view_t view;
    memset(&view, 0, sizeof view);
    view.blob = blob;
    view.blob_size = sizeof blob;
    view.phdr_off = PHDR_OFF;
    view.phdr_count = 1;
    view.n_phdrs = 1;
    view.phdrs[0].file_offset = 0;
    view.phdrs[0].file_size = sizeof blob;
    view.phdrs[0].vaddr = 0;
    view.phdrs[0].mem_size = sizeof blob;
    view.phdrs[0].perms = ELF_PROT_READ | ELF_PROT_WRITE;
    return view;
}

static int write_q(void *user, uint64_t vaddr, uint64_t value)
{
    fixture_state_t *state = (fixture_state_t *)user;
    expect(state->write_count < 8, "too many writes");
    state->writes[state->write_count++] = (write_record_t){ vaddr, value };
    return 0;
}

static void skip_log(void *user, const char *name)
{
    fixture_state_t *state = (fixture_state_t *)user;
    state->skip_count++;
    snprintf(state->skip_name, sizeof state->skip_name, "%s", name);
}

static int find_write(const fixture_state_t *state, uint64_t vaddr, uint64_t *value)
{
    for (unsigned i = 0; i < state->write_count; ++i) {
        if (state->writes[i].vaddr == vaddr) {
            *value = state->writes[i].value;
            return 1;
        }
    }
    return 0;
}

static void expect_write(const fixture_state_t *state, uint64_t off, uint64_t expected)
{
    uint64_t actual = 0;
    expect(find_write(state, TARGET_BIAS + off, &actual), "missing expected write");
    if (actual != expected) {
        fprintf(stderr, "reloc C fixture failed: write at 0x%llx was 0x%llx, expected 0x%llx\n",
                (unsigned long long)(TARGET_BIAS + off),
                (unsigned long long)actual,
                (unsigned long long)expected);
        exit(1);
    }
}

int main(void)
{
    tm_elf_view_t view = make_view();
    tm_reloc_resolver_t resolver;
    expect(tm_reloc_init_resolver(&view, RESOLVER_BIAS, &resolver) == 0,
           "resolver init failed");
    expect(resolver.base == RESOLVER_BIAS, "resolver base mismatch");
    expect(resolver.nsyms == 4, "resolver symbol count mismatch");

    fixture_state_t state;
    memset(&state, 0, sizeof state);
    unsigned long applied = 0, total = 0, skipped = 0;
    expect(tm_reloc_apply(&view, TARGET_BIAS, &resolver, write_q, skip_log,
                          &state, &applied, &total, &skipped) == 0,
           "tm_reloc_apply failed");

    expect(total == 6, "total relocation count mismatch");
    expect(applied == 5, "applied relocation count mismatch");
    expect(skipped == 1, "unsupported relocation skip count mismatch");
    expect(state.write_count == 5, "write callback count mismatch");
    expect(state.skip_count == 1, "skip log count mismatch");
    expect(strcmp(state.skip_name, "missing_symbol") == 0,
           "skip log symbol mismatch");

    expect_write(&state, WRITE_BASE + 0x00, TARGET_BIAS + 0x33);
    expect_write(&state, WRITE_BASE + 0x08, TARGET_BIAS + 0x1234 + 7);
    expect_write(&state, WRITE_BASE + 0x10, RESOLVER_BIAS + 0x5678 + 9);
    expect_write(&state, WRITE_BASE + 0x18, 0);
    expect_write(&state, WRITE_BASE + 0x28, RESOLVER_BIAS + 0x5678 + 11);

    uint64_t ignored = 0;
    expect(!find_write(&state, TARGET_BIAS + WRITE_BASE + 0x20, &ignored),
           "unsupported relocation unexpectedly wrote");

    printf("reloc C fixture ok: total=%lu applied=%lu skipped=%lu skip=%s writes=%u\n",
           total, applied, skipped, state.skip_name, state.write_count);
    return 0;
}
EOF_C

echo "reloc-c-evidence: compiling C relocation fixture"
"$CC" -std=c11 -Wall -Wextra -Werror \
    -I "$ROOT/libtaskman/include" \
    "$FIXTURE_C" "$RELOC_SRC" \
    -o "$FIXTURE_BIN"

"$FIXTURE_BIN" > "$FIXTURE_LOG"
grep -Fq 'reloc C fixture ok: total=6 applied=5 skipped=1 skip=missing_symbol writes=5' "$FIXTURE_LOG" ||
    fail "C relocation fixture did not report expected summary"

echo "reloc-c-evidence: building LQ image for runtime relocation evidence"
"$MAKE" -C "$ROOT/lq" --no-print-directory

QSOE_BOOT_EXTRA_PATTERNS="$(printf '%s\n' \
    'spawning /sbin/init' \
    'dispatcher ready')" \
QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    "$ROOT/scripts/boot-smoke.sh" -k lq -t 180 -o "$BOOT_LOG" -- --debug=1

require_log_regex 'spawn: libc\.so relocs [0-9]+/[0-9]+ \([0-9]+ skipped\)' 'libc relocation pass'
require_log_regex 'spawn: rtld relocs [0-9]+/[0-9]+ \([0-9]+ skipped\)' 'rtld relocation pass'
require_log_regex 'spawn: main relocs [0-9]+/[0-9]+ \([0-9]+ skipped\)' 'main executable relocation pass'
require_log_regex 'spawn: .*e_type=.*interp=yes' 'dynamic ELF spawn path'

reject_log_fixed 'spawn: libc.so reloc failed' 'libc relocation failure'
reject_log_fixed 'spawn: rtld reloc failed' 'rtld relocation failure'
reject_log_fixed 'spawn: main reloc failed' 'main relocation failure'
reject_log_fixed 'spawn: libc.so resolver init failed' 'resolver init failure'
reject_log_fixed 'tm_spawn returned non-zero' 'spawn failure'

{
    printf 'reloc C evidence complete\n'
    printf 'fixture_source=%s\n' "$FIXTURE_C"
    printf 'fixture_log=%s\n' "$FIXTURE_LOG"
    printf 'boot_log=%s\n' "$BOOT_LOG"
    printf 'source=%s\n' "$RELOC_SRC"
    printf 'observed=host C RELATIVE/RISCV64/JUMP_SLOT/external/skip fixture and LQ libc/rtld/main relocation runtime logs\n'
} > "$SUMMARY"

printf 'reloc-c-evidence: wrote %s\n' "$SUMMARY"
