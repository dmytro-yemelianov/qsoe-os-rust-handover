#!/usr/bin/env bash
#
# Capture evidence that multiple Rust taskman providers link through one
# shared static archive with a single Rust runtime.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
WORKDIR=${TM_PROVIDERS_EVIDENCE_WORKDIR:-"$ROOT/build/tm-providers-evidence"}
RUST_PROVIDERS_A=${RUST_PROVIDERS_A:-"$ROOT/build/rust/tm-providers/libqsoe_tm_providers.a"}

usage() {
    cat <<'EOF'
usage: scripts/tm-providers-evidence.sh

Builds Rust tm_cpio + tm_procfs into one taskman provider archive, links NQ
and LQ taskman with both selected, audits the ELFs, and runs the /proc smoke.

Environment:
  TM_PROVIDERS_EVIDENCE_WORKDIR  output directory, default build/tm-providers-evidence
  RUST_PROVIDERS_A               shared Rust provider archive path
EOF
}

case "${1:-}" in
    -h|--help|help)
        usage
        exit 0
        ;;
    '')
        ;;
    *)
        echo "tm-providers-evidence.sh: unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
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

READELF=$(find_tool riscv64-linux-gnu-readelf readelf llvm-readelf) || {
    echo "tm-providers-evidence.sh: no readelf tool found" >&2
    exit 127
}
AR=$(find_tool riscv64-linux-gnu-ar ar llvm-ar) || {
    echo "tm-providers-evidence.sh: no ar tool found" >&2
    exit 127
}
NM=$(find_tool riscv64-linux-gnu-nm nm llvm-nm) || {
    echo "tm-providers-evidence.sh: no nm tool found" >&2
    exit 127
}

mkdir -p "$WORKDIR"

fail() {
    echo "tm-providers-evidence.sh: $*" >&2
    exit 1
}

object_count() {
    local archive=$1
    local object=$2

    "$AR" t "$archive" |
        awk -v object="$object" '$0 == object { n++ } END { print n + 0 }'
}

require_absent_object() {
    local label=$1
    local archive=$2
    local object=$3
    local count

    [ -f "$archive" ] || fail "missing archive for $label: $archive"
    count=$(object_count "$archive" "$object")
    printf '%s %s count: %s\n' "$label" "$object" "$count" |
        tee "$WORKDIR/$label-$object-membership.txt"
    [ "$count" -eq 0 ] || fail "$label still contains $object"
}

audit_elf() {
    local label=$1
    local elf=$2
    local header="$WORKDIR/$label-readelf-header.txt"
    local sections="$WORKDIR/$label-readelf-sections.txt"
    local dynamic="$WORKDIR/$label-readelf-dynamic.txt"
    local symbols="$WORKDIR/$label-symbols.txt"

    [ -f "$elf" ] || fail "missing ELF for $label: $elf"
    "$READELF" -h "$elf" > "$header"
    "$READELF" -S "$elf" > "$sections"
    "$READELF" -d "$elf" > "$dynamic" 2>&1 || true
    "$NM" -g --defined-only "$elf" > "$symbols"

    grep -Eq 'Flags:.*RVC, soft-float ABI' "$header" ||
        fail "$label does not report RVC soft-float ELF flags"
    if grep -Eq '(\.(tdata|tbss|init_array|fini_array|ctors|dtors|gcc_except_table|debug_frame))' "$sections"; then
        fail "$label contains unsupported TLS, constructor, or debug-frame sections"
    fi
    if grep -Fq 'Dynamic section at offset' "$dynamic"; then
        fail "$label unexpectedly has a dynamic section"
    fi

    for symbol in \
        tm_cpio_check_valid \
        tm_cpio_find_file \
        tm_procfs_init \
        tm_procfs_resolve
    do
        grep -Eq "[[:space:]]$symbol$" "$symbols" ||
            fail "$label is missing linked symbol $symbol"
    done

    awk '/rust_begin_unwind/ { n++ } END { print n + 0 }' "$symbols" |
        tee "$WORKDIR/$label-rust-panic-symbol-count.txt"
}

audit_provider_archive() {
    local header="$WORKDIR/shared-provider-readelf-header.txt"
    local sections="$WORKDIR/shared-provider-readelf-sections.txt"
    local symbols="$WORKDIR/shared-provider-symbols.txt"
    local total
    local soft_float
    local panic_count

    [ -f "$RUST_PROVIDERS_A" ] || fail "missing shared provider archive: $RUST_PROVIDERS_A"
    "$READELF" -h "$RUST_PROVIDERS_A" > "$header"
    "$READELF" -S "$RUST_PROVIDERS_A" > "$sections"
    "$NM" -g --defined-only "$RUST_PROVIDERS_A" > "$symbols"

    total=$(awk '/Flags:/ { n++ } END { print n + 0 }' "$header")
    soft_float=$(awk '/Flags:/ && /RVC, soft-float ABI/ { n++ } END { print n + 0 }' "$header")
    [ "$total" -gt 0 ] || fail "shared provider archive contains no ELF members"
    [ "$total" -eq "$soft_float" ] ||
        fail "shared provider archive has $soft_float/$total soft-float members"

    for symbol in \
        tm_cpio_check_valid \
        tm_cpio_find_file \
        tm_procfs_init \
        tm_procfs_resolve \
        qsoe_tm_providers_archive_anchor
    do
        grep -Eq "[[:space:]]$symbol$" "$symbols" ||
            fail "shared provider archive is missing symbol $symbol"
    done

    panic_count=$(awk '/rust_begin_unwind/ { n++ } END { print n + 0 }' "$symbols")
    [ "$panic_count" -le 1 ] ||
        fail "shared provider archive has duplicate rust_begin_unwind symbols: $panic_count"

    if grep -Eq '(\.(tdata|tbss|init_array|fini_array|ctors|dtors|gcc_except_table))' "$sections"; then
        fail "shared provider archive contains unsupported TLS or constructor sections"
    fi

    {
        printf 'shared provider archive members: %s\n' "$total"
        printf 'shared provider soft-float members: %s\n' "$soft_float"
        printf 'shared provider rust_begin_unwind symbols: %s\n' "$panic_count"
    } | tee "$WORKDIR/shared-provider-summary.txt"
}

"$ROOT/scripts/apply-component-overrides.sh"

echo "tm-providers-evidence.sh: building shared Rust provider archive"
QSOE_RUST_TM_CPIO=1 \
QSOE_RUST_TM_PROCFS=1 \
    "$MAKE" -C "$ROOT" --no-print-directory rust-tm-providers
audit_provider_archive

echo "tm-providers-evidence.sh: linking NQ taskman with tm_cpio + tm_procfs"
"$MAKE" -C "$ROOT/nq/taskman" --no-print-directory \
    QSOE_RUST_TM_CPIO=1 \
    QSOE_RUST_TM_PROCFS=1
require_absent_object nq-dual "$ROOT/nq/build/libtaskman/libtaskman.a" cpio.o
require_absent_object nq-dual "$ROOT/nq/build/libtaskman/libtaskman.a" tm_procfs.o
audit_elf nq-dual-taskman "$ROOT/nq/build/taskman/taskman.elf"

echo "tm-providers-evidence.sh: linking LQ taskman with tm_cpio + tm_procfs"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_CPIO=1 \
    QSOE_RUST_TM_PROCFS=1 \
    taskman
require_absent_object lq-dual "$ROOT/lq/build/libtaskman/libtaskman.a" cpio.o
require_absent_object lq-dual "$ROOT/lq/build/libtaskman/libtaskman.a" tm_procfs.o
audit_elf lq-dual-taskman "$ROOT/lq/build/taskman.elf"

echo "tm-providers-evidence.sh: running dual-provider /proc smoke"
QSOE_RUST_TM_CPIO=1 \
QSOE_RUST_TM_PROCFS=1 \
PROCFS_SMOKE_WORKDIR="$WORKDIR/procfs-smoke" \
    "$MAKE" -C "$ROOT" --no-print-directory procfs-smoke

echo "tm-providers-evidence.sh: evidence captured in $WORKDIR"
