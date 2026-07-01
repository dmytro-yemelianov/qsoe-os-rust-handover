#!/usr/bin/env bash
#
# Capture opt-in Rust tm_reloc provider evidence while keeping C default.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
WORKDIR=${TM_RELOC_PROVIDER_EVIDENCE_WORKDIR:-"$ROOT/build/tm-reloc-provider-evidence"}
RUST_PROVIDER_A=${RUST_PROVIDER_A:-"$ROOT/build/rust/tm-reloc/libqsoe_tm_reloc.a"}
BOOT_LOG="$WORKDIR/boot-tm-reloc-provider.log"
SUMMARY="$WORKDIR/summary.txt"

usage() {
    cat <<'EOU'
usage: scripts/tm-reloc-provider-evidence.sh

Builds and audits the opt-in Rust tm_reloc provider, runs host parity tests,
verifies LQ links the Rust provider without C reloc.o when QSOE_RUST_TM_RELOC=1,
and boots LQ to require libc.so/rtld/main relocation logs.
EOU
}

case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
    '') ;;
    *) echo "tm-reloc-provider-evidence.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
esac

find_tool() {
    local tool
    for tool in "$@"; do
        if command -v "$tool" >/dev/null 2>&1; then
            command -v "$tool"
            return 0
        fi
    done
    return 1
}

READELF=$(find_tool riscv64-linux-gnu-readelf readelf llvm-readelf) || { echo "tm-reloc-provider-evidence.sh: no readelf tool found" >&2; exit 127; }
AR=$(find_tool riscv64-linux-gnu-ar ar llvm-ar) || { echo "tm-reloc-provider-evidence.sh: no ar tool found" >&2; exit 127; }
NM=$(find_tool riscv64-linux-gnu-nm nm llvm-nm) || { echo "tm-reloc-provider-evidence.sh: no nm tool found" >&2; exit 127; }

fail() {
    echo "tm-reloc-provider-evidence.sh: $*" >&2
    exit 1
}

require_log_regex() {
    local pattern=$1
    local label=$2
    grep -Eq "$pattern" "$BOOT_LOG" || fail "missing boot evidence: $label ($pattern)"
}

reject_log_fixed() {
    local pattern=$1
    local label=$2
    if grep -Fq "$pattern" "$BOOT_LOG"; then
        fail "unexpected boot evidence: $label ($pattern)"
    fi
}

object_count() {
    local archive=$1
    local object=$2
    "$AR" t "$archive" | awk -v object="$object" '$0 == object { n++ } END { print n + 0 }'
}

audit_provider_archive() {
    local header="$WORKDIR/rust-provider-archive-readelf-header.txt"
    local sections="$WORKDIR/rust-provider-archive-readelf-sections.txt"
    local dynamic="$WORKDIR/rust-provider-archive-readelf-dynamic.txt"
    local symbols="$WORKDIR/rust-provider-archive-symbols.txt"
    local total
    local soft_float

    [ -f "$RUST_PROVIDER_A" ] || fail "missing Rust provider archive: $RUST_PROVIDER_A"
    "$READELF" -h "$RUST_PROVIDER_A" > "$header"
    "$READELF" -S "$RUST_PROVIDER_A" > "$sections"
    "$READELF" -d "$RUST_PROVIDER_A" > "$dynamic" 2>&1 || true
    "$NM" -g --defined-only "$RUST_PROVIDER_A" > "$symbols"

    total=$(awk '/Flags:/ { n++ } END { print n + 0 }' "$header")
    soft_float=$(awk '/Flags:/ && /RVC, soft-float ABI/ { n++ } END { print n + 0 }' "$header")
    [ "$total" -gt 0 ] || fail "Rust provider archive contains no ELF members"
    [ "$total" -eq "$soft_float" ] || fail "Rust provider archive has $soft_float/$total soft-float members"

    grep -Eq '[[:space:]]tm_reloc_apply$' "$symbols" || fail "Rust provider archive is missing symbol tm_reloc_apply"
    grep -Eq '[[:space:]]tm_reloc_init_resolver$' "$symbols" || fail "Rust provider archive is missing symbol tm_reloc_init_resolver"

    if grep -Eq '(\.(tdata|tbss|init_array|fini_array|ctors|dtors|gcc_except_table|eh_frame|debug_frame)| TLS )' "$sections"; then
        fail "Rust provider archive contains unsupported TLS, constructor, or unwind sections"
    fi
    if grep -Fq 'Dynamic section at offset' "$dynamic"; then
        fail "Rust provider archive unexpectedly has a dynamic section"
    fi

    printf 'rust provider archive members: %s\n' "$total" | tee "$WORKDIR/rust-provider-summary.txt"
    printf 'rust provider soft-float members: %s\n' "$soft_float" | tee -a "$WORKDIR/rust-provider-summary.txt"
}

audit_lq_opt_in_link() {
    local libtaskman="$ROOT/lq/build/libtaskman/libtaskman.a"
    local taskman="$ROOT/lq/build/taskman.elf"
    local membership="$WORKDIR/lq-libtaskman-membership.txt"
    local symbols="$WORKDIR/lq-taskman-symbols.txt"
    local reloc_count

    [ -f "$libtaskman" ] || fail "missing LQ libtaskman archive: $libtaskman"
    [ -f "$taskman" ] || fail "missing LQ taskman ELF: $taskman"

    reloc_count=$(object_count "$libtaskman" reloc.o)
    printf 'lq rust tm_reloc reloc.o count: %s\n' "$reloc_count" | tee "$membership"
    [ "$reloc_count" -eq 0 ] || fail "LQ opt-in expected 0 C reloc.o members, got $reloc_count"

    "$NM" -g --defined-only "$taskman" > "$symbols"
    grep -Eq '[[:space:]]tm_reloc_apply$' "$symbols" || fail "LQ taskman is missing linked Rust symbol tm_reloc_apply"
    grep -Eq '[[:space:]]tm_reloc_init_resolver$' "$symbols" || fail "LQ taskman is missing linked Rust symbol tm_reloc_init_resolver"
}

mkdir -p "$WORKDIR"

"$ROOT/scripts/apply-component-overrides.sh"

printf 'tm-reloc-provider-evidence.sh: running Rust host parity tests\n'
. "$ROOT/scripts/rust-env.sh"
qsoe_cargo_set_target_dir "$ROOT" taskman-reloc-host
cargo test --manifest-path "$ROOT/rust/Cargo.toml" -p qsoe-tm-reloc --features host-tests

printf 'tm-reloc-provider-evidence.sh: building Rust provider archive\n'
QSOE_RUST_TM_RELOC=1 "$MAKE" -C "$ROOT" --no-print-directory rust-tm-reloc-provider
audit_provider_archive

printf 'tm-reloc-provider-evidence.sh: building LQ with opt-in Rust tm_reloc\n'
"$MAKE" -C "$ROOT/lq" --no-print-directory QSOE_RUST_TM_RELOC=1
audit_lq_opt_in_link

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
    printf 'tm_reloc Rust provider evidence complete\n'
    printf 'provider_archive=%s\n' "$RUST_PROVIDER_A"
    printf 'boot_log=%s\n' "$BOOT_LOG"
    printf 'selector=QSOE_RUST_TM_RELOC=1\n'
    printf 'observed=Rust host parity tests, provider ABI symbols, LQ no C reloc.o, and LQ libc/rtld/main relocation runtime logs\n'
} > "$SUMMARY"

printf 'tm-reloc-provider-evidence.sh: wrote %s\n' "$SUMMARY"
