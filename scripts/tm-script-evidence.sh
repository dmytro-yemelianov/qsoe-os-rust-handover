#!/usr/bin/env bash
#
# Capture tm_script Rust-only retirement evidence.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
WORKDIR=${TM_SCRIPT_EVIDENCE_WORKDIR:-"$ROOT/build/tm-script-evidence"}
RUST_PROVIDER_A=${RUST_PROVIDER_A:-"$ROOT/build/rust/tm-script/libqsoe_tm_script.a"}

usage() {
    cat <<'EOF'
usage: scripts/tm-script-evidence.sh

Builds and audits the retired Rust tm_script path, verifies that taskman
archives no longer contain C script.o, and checks retired selector rejection
for NQ and LQ taskman links.

Environment:
  TM_SCRIPT_EVIDENCE_WORKDIR  output directory, default build/tm-script-evidence
  RUST_PROVIDER_A             Rust provider archive path
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
        echo "tm-script-evidence.sh: unknown option: $1" >&2
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
    echo "tm-script-evidence.sh: no readelf tool found" >&2
    exit 127
}
AR=$(find_tool riscv64-linux-gnu-ar ar llvm-ar) || {
    echo "tm-script-evidence.sh: no ar tool found" >&2
    exit 127
}
NM=$(find_tool riscv64-linux-gnu-nm nm llvm-nm) || {
    echo "tm-script-evidence.sh: no nm tool found" >&2
    exit 127
}

mkdir -p "$WORKDIR"

"$ROOT/scripts/apply-component-overrides.sh"

fail() {
    echo "tm-script-evidence.sh: $*" >&2
    exit 1
}

object_count() {
    local archive=$1
    local object=$2

    "$AR" t "$archive" |
        awk -v object="$object" '$0 == object { n++ } END { print n + 0 }'
}

require_script_count() {
    local label=$1
    local archive=$2
    local expected=$3
    local count

    [ -f "$archive" ] || fail "missing archive for $label: $archive"
    count=$(object_count "$archive" script.o)
    printf '%s script.o count: %s\n' "$label" "$count" |
        tee "$WORKDIR/$label-archive-membership.txt"
    [ "$count" -eq "$expected" ] ||
        fail "$label expected $expected script.o members, got $count"
}

require_retired_selector_rejected() {
    local label=$1
    shift
    local log="$WORKDIR/$label-retired-selector-rejection.txt"

    if "$@" > "$log" 2>&1; then
        fail "$label unexpectedly accepted QSOE_RUST_TM_SCRIPT=0"
    fi
    grep -Fq 'QSOE_RUST_TM_SCRIPT must be 1 after C tm_script retirement' "$log" ||
        fail "$label rejection did not mention retired tm_script selector"
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

    [ -f "$elf" ] || fail "missing ELF for $label: $elf"
    "$NM" -g --defined-only "$elf" > "$symbols"

    grep -Eq '[[:space:]]tm_script_parse_shebang$' "$symbols" ||
        fail "$label is missing linked symbol tm_script_parse_shebang"
}

audit_provider_archive() {
    local header="$WORKDIR/rust-provider-archive-readelf-header.txt"
    local sections="$WORKDIR/rust-provider-archive-readelf-sections.txt"
    local symbols="$WORKDIR/rust-provider-archive-symbols.txt"
    local total
    local soft_float

    [ -f "$RUST_PROVIDER_A" ] || fail "missing Rust provider archive: $RUST_PROVIDER_A"
    "$READELF" -h "$RUST_PROVIDER_A" > "$header"
    "$READELF" -S "$RUST_PROVIDER_A" > "$sections"
    "$NM" -g --defined-only "$RUST_PROVIDER_A" > "$symbols"

    total=$(awk '/Flags:/ { n++ } END { print n + 0 }' "$header")
    soft_float=$(awk '/Flags:/ && /RVC, soft-float ABI/ { n++ } END { print n + 0 }' "$header")
    [ "$total" -gt 0 ] || fail "Rust provider archive contains no ELF members"
    [ "$total" -eq "$soft_float" ] ||
        fail "Rust provider archive has $soft_float/$total soft-float members"

    grep -Eq '[[:space:]]tm_script_parse_shebang$' "$symbols" ||
        fail "Rust provider archive is missing symbol tm_script_parse_shebang"

    if grep -Eq '(\.(tdata|tbss|init_array|fini_array|ctors|dtors|gcc_except_table)| TLS )' "$sections"; then
        fail "Rust provider archive contains unsupported TLS or constructor sections"
    fi

    printf 'rust provider archive members: %s\n' "$total" |
        tee "$WORKDIR/rust-provider-summary.txt"
    printf 'rust provider soft-float members: %s\n' "$soft_float" |
        tee -a "$WORKDIR/rust-provider-summary.txt"
}

echo "tm-script-evidence.sh: running Rust host model tests"
"$MAKE" -C "$ROOT" --no-print-directory check-tm-script-model

echo "tm-script-evidence.sh: building Rust provider archive"
"$MAKE" -C "$ROOT" --no-print-directory rust-tm-script-provider
audit_provider_archive

echo "tm-script-evidence.sh: verifying NQ Rust-only membership"
"$MAKE" -C "$ROOT/nq/taskman" --no-print-directory \
    QSOE_RUST_TM_CPIO=1 QSOE_RUST_TM_CRED=1 QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_SCRIPT=1 QSOE_RUST_TM_SYSFS=1
require_script_count nq-rust-retired "$ROOT/nq/build/libtaskman/libtaskman.a" 0
audit_flags nq-rust-retired-taskman "$ROOT/nq/build/taskman/taskman.elf"
audit_linked_symbols nq-rust-retired-taskman "$ROOT/nq/build/taskman/taskman.elf"

echo "tm-script-evidence.sh: verifying NQ retired selector rejection"
require_retired_selector_rejected nq \
    "$MAKE" -C "$ROOT/nq/taskman" --no-print-directory QSOE_RUST_TM_SCRIPT=0

echo "tm-script-evidence.sh: verifying LQ Rust-only membership"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_CPIO=1 \
    QSOE_RUST_TM_CRED=1 \
    QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_PSEUDODEV=0 \
    QSOE_RUST_TM_SCRIPT=1 \
    QSOE_RUST_TM_SYSFS=1 \
    taskman
require_script_count lq-rust-retired "$ROOT/lq/build/libtaskman/libtaskman.a" 0
audit_flags lq-rust-retired-taskman "$ROOT/lq/build/taskman.elf"
audit_linked_symbols lq-rust-retired-taskman "$ROOT/lq/build/taskman.elf"

echo "tm-script-evidence.sh: verifying LQ retired selector rejection"
require_retired_selector_rejected lq \
    "$MAKE" -C "$ROOT/lq" --no-print-directory QSOE_RUST_TM_SCRIPT=0 taskman

echo "tm-script-evidence.sh: evidence captured in $WORKDIR"
