#!/usr/bin/env bash
#
# Capture tm_pathmgr Rust-only retirement evidence.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
WORKDIR=${TM_PATHMGR_EVIDENCE_WORKDIR:-"$ROOT/build/tm-pathmgr-evidence"}
RUST_PROVIDER_A=${RUST_PROVIDER_A:-"$ROOT/build/rust/tm-pathmgr/libqsoe_tm_pathmgr.a"}

usage() {
    cat <<'EOF'
usage: scripts/tm-pathmgr-evidence.sh

Builds and audits the retired Rust tm_pathmgr path, verifies that NQ/LQ
taskman archives no longer contain C pathmgr.o, and checks retired selector
rejection for NQ, LQ, standalone libtaskman, and provider archive builds.

Environment:
  TM_PATHMGR_EVIDENCE_WORKDIR  output directory, default build/tm-pathmgr-evidence
  RUST_PROVIDER_A              Rust provider archive path
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
        echo "tm-pathmgr-evidence.sh: unknown option: $1" >&2
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
    echo "tm-pathmgr-evidence.sh: no readelf tool found" >&2
    exit 127
}
AR=$(find_tool riscv64-linux-gnu-ar ar llvm-ar) || {
    echo "tm-pathmgr-evidence.sh: no ar tool found" >&2
    exit 127
}
NM=$(find_tool riscv64-linux-gnu-nm nm llvm-nm) || {
    echo "tm-pathmgr-evidence.sh: no nm tool found" >&2
    exit 127
}

mkdir -p "$WORKDIR"

"$ROOT/scripts/apply-component-overrides.sh"

fail() {
    echo "tm-pathmgr-evidence.sh: $*" >&2
    exit 1
}

object_count() {
    local archive=$1
    local object=$2

    "$AR" t "$archive" |
        awk -v object="$object" '$0 == object { n++ } END { print n + 0 }'
}

require_pathmgr_count() {
    local label=$1
    local archive=$2
    local expected=$3
    local count

    [ -f "$archive" ] || fail "missing archive for $label: $archive"
    count=$(object_count "$archive" pathmgr.o)
    printf '%s pathmgr.o count: %s\n' "$label" "$count" |
        tee "$WORKDIR/$label-archive-membership.txt"
    [ "$count" -eq "$expected" ] ||
        fail "$label expected $expected pathmgr.o members, got $count"
}

require_retired_selector_rejected() {
    local label=$1
    shift
    local log="$WORKDIR/$label-retired-selector-rejection.txt"

    if "$@" > "$log" 2>&1; then
        fail "$label unexpectedly accepted QSOE_RUST_TM_PATHMGR=0"
    fi
    if ! grep -Fq 'QSOE_RUST_TM_PATHMGR must be 1 after C tm_pathmgr retirement' "$log" &&
        ! grep -Fq 'C tm_pathmgr is retired; QSOE_RUST_TM_PATHMGR must be 1' "$log"; then
        fail "$label rejection did not mention retired tm_pathmgr selector"
    fi
}

audit_flags() {
    local label=$1
    local elf=$2
    local header="$WORKDIR/$label-readelf-header.txt"
    local sections="$WORKDIR/$label-readelf-sections.txt"
    local dynamic="$WORKDIR/$label-readelf-dynamic.txt"

    [ -f "$elf" ] || fail "missing ELF for $label: $elf"
    "$READELF" -h "$elf" > "$header"
    "$READELF" -S "$elf" > "$sections"
    "$READELF" -d "$elf" > "$dynamic" 2>&1 || true

    grep -Eq 'Flags:.*RVC, soft-float ABI' "$header" ||
        fail "$label does not report RVC soft-float ELF flags"
    if grep -Eq '(\.(tdata|tbss|init_array|fini_array|ctors|dtors|gcc_except_table|debug_frame)| TLS )' "$sections"; then
        fail "$label contains unsupported TLS, constructor, or debug-frame sections"
    fi
    if grep -Fq 'Dynamic section at offset' "$dynamic"; then
        fail "$label unexpectedly has a dynamic section"
    fi
}

audit_linked_symbols() {
    local label=$1
    local elf=$2
    local symbols="$WORKDIR/$label-symbols.txt"
    local symbol

    [ -f "$elf" ] || fail "missing ELF for $label: $elf"
    "$NM" -g --defined-only "$elf" > "$symbols"

    for symbol in \
        tm_pathmgr_init \
        tm_pathmgr_register \
        tm_pathmgr_unregister_pid \
        tm_pathmgr_resolve \
        tm_pathmgr_repath \
        tm_pathmgr_symlink \
        tm_pathmgr_expand_symlink_cpio \
        tm_pathmgr_expand_symlink \
        tm_pathmgr_child_at
    do
        grep -Eq "[[:space:]]$symbol$" "$symbols" ||
            fail "$label is missing linked symbol $symbol"
    done
}

audit_provider_archive() {
    local header="$WORKDIR/rust-provider-archive-readelf-header.txt"
    local sections="$WORKDIR/rust-provider-archive-readelf-sections.txt"
    local symbols="$WORKDIR/rust-provider-archive-symbols.txt"
    local total
    local soft_float
    local symbol

    [ -f "$RUST_PROVIDER_A" ] || fail "missing Rust provider archive: $RUST_PROVIDER_A"
    "$READELF" -h "$RUST_PROVIDER_A" > "$header"
    "$READELF" -S "$RUST_PROVIDER_A" > "$sections"
    "$NM" -g --defined-only "$RUST_PROVIDER_A" > "$symbols"

    total=$(awk '/Flags:/ { n++ } END { print n + 0 }' "$header")
    soft_float=$(awk '/Flags:/ && /RVC, soft-float ABI/ { n++ } END { print n + 0 }' "$header")
    [ "$total" -gt 0 ] || fail "Rust provider archive contains no ELF members"
    [ "$total" -eq "$soft_float" ] ||
        fail "Rust provider archive has $soft_float/$total soft-float members"

    for symbol in \
        tm_pathmgr_init \
        tm_pathmgr_register \
        tm_pathmgr_unregister_pid \
        tm_pathmgr_resolve \
        tm_pathmgr_repath \
        tm_pathmgr_symlink \
        tm_pathmgr_expand_symlink_cpio \
        tm_pathmgr_expand_symlink \
        tm_pathmgr_child_at
    do
        grep -Eq "[[:space:]]$symbol$" "$symbols" ||
            fail "Rust provider archive is missing symbol $symbol"
    done

    if grep -Eq '(\.(tdata|tbss|init_array|fini_array|ctors|dtors|gcc_except_table)| TLS )' "$sections"; then
        fail "Rust provider archive contains unsupported TLS or constructor sections"
    fi

    printf 'rust provider archive members: %s\n' "$total" |
        tee "$WORKDIR/rust-provider-summary.txt"
    printf 'rust provider soft-float members: %s\n' "$soft_float" |
        tee -a "$WORKDIR/rust-provider-summary.txt"
}

[ ! -e "$ROOT/libtaskman/src/pathmgr.c" ] ||
    fail "libtaskman/src/pathmgr.c should be retired"

echo "tm-pathmgr-evidence.sh: running Rust host model tests"
"$MAKE" -C "$ROOT" --no-print-directory check-tm-pathmgr-model

echo "tm-pathmgr-evidence.sh: building Rust provider archive"
"$MAKE" -C "$ROOT" --no-print-directory rust-tm-pathmgr-provider
audit_provider_archive

echo "tm-pathmgr-evidence.sh: verifying NQ Rust-only membership"
"$MAKE" -C "$ROOT/nq/taskman" --no-print-directory \
    QSOE_RUST_TM_PATHMGR=1 \
    QSOE_RUST_TM_PROCFS=1
require_pathmgr_count nq-rust-retired "$ROOT/nq/build/libtaskman/libtaskman.a" 0
audit_flags nq-rust-retired-taskman "$ROOT/nq/build/taskman/taskman.elf"
audit_linked_symbols nq-rust-retired-taskman "$ROOT/nq/build/taskman/taskman.elf"

echo "tm-pathmgr-evidence.sh: verifying NQ retired selector rejection"
require_retired_selector_rejected nq \
    "$MAKE" -C "$ROOT/nq/taskman" --no-print-directory QSOE_RUST_TM_PATHMGR=0

echo "tm-pathmgr-evidence.sh: verifying LQ Rust-only membership"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_PATHMGR=1 \
    QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_PSEUDODEV=1 \
    QSOE_RUST_TM_RSRCDB=1 \
    taskman
require_pathmgr_count lq-rust-retired "$ROOT/lq/build/libtaskman/libtaskman.a" 0
audit_flags lq-rust-retired-taskman "$ROOT/lq/build/taskman.elf"
audit_linked_symbols lq-rust-retired-taskman "$ROOT/lq/build/taskman.elf"

echo "tm-pathmgr-evidence.sh: verifying LQ retired selector rejection"
require_retired_selector_rejected lq \
    "$MAKE" -C "$ROOT/lq" --no-print-directory QSOE_RUST_TM_PATHMGR=0 taskman

echo "tm-pathmgr-evidence.sh: verifying standalone libtaskman retired selector rejection"
require_retired_selector_rejected libtaskman \
    "$MAKE" -C "$ROOT/libtaskman" --no-print-directory QSOE_RUST_TM_PATHMGR=0

echo "tm-pathmgr-evidence.sh: verifying provider archive retired selector rejection"
require_retired_selector_rejected rust-providers \
    env QSOE_RUST_TM_PATHMGR=0 "$ROOT/scripts/build-rust-tm-providers.sh" "$WORKDIR/retired-selector/libqsoe_tm_providers.a"

echo "tm-pathmgr-evidence.sh: evidence captured in $WORKDIR"
