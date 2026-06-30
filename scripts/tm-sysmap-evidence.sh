#!/usr/bin/env bash
#
# Capture LQ tm_sysmap Rust-only retirement evidence.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
WORKDIR=${TM_SYSMAP_EVIDENCE_WORKDIR:-"$ROOT/build/tm-sysmap-evidence"}
RUST_PROVIDER_A=${RUST_PROVIDER_A:-"$ROOT/build/rust/tm-sysmap/libqsoe_tm_sysmap.a"}

usage() {
    cat <<'EOF'
usage: scripts/tm-sysmap-evidence.sh

Builds and audits the retired Rust LQ taskman sysmap path, verifies that C
sys/sysmap.o is absent from the taskman link plan, and checks retired selector
rejection for LQ taskman links.

Environment:
  TM_SYSMAP_EVIDENCE_WORKDIR  output directory, default build/tm-sysmap-evidence
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
        echo "tm-sysmap-evidence.sh: unknown option: $1" >&2
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
    echo "tm-sysmap-evidence.sh: no readelf tool found" >&2
    exit 127
}
NM=$(find_tool riscv64-linux-gnu-nm nm llvm-nm) || {
    echo "tm-sysmap-evidence.sh: no nm tool found" >&2
    exit 127
}

mkdir -p "$WORKDIR"

"$ROOT/scripts/apply-component-overrides.sh"

fail() {
    echo "tm-sysmap-evidence.sh: $*" >&2
    exit 1
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
    if grep -Eq '(\.(tdata|tbss|init_array|fini_array|ctors|dtors|gcc_except_table)| TLS )' "$sections"; then
        fail "$label contains unsupported TLS, constructor, or debug-frame sections"
    fi
    if grep -Fq 'Dynamic section at offset' "$dynamic"; then
        fail "$label unexpectedly has a dynamic section"
    fi
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

    for symbol in \
        tm_sysmap_build \
        tm_sysmap_get
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

capture_lq_taskman_plan() {
    local label=$1
    local rust_selected=$2
    local log="$WORKDIR/$label-taskman-dry-run.txt"

    "$MAKE" -C "$ROOT/lq/taskman" --no-print-directory -B -n all \
        LIBTASKMAN_A="$ROOT/lq/build/libtaskman/libtaskman.a" \
        LIBTASKMAN_INC="$ROOT/libtaskman/include" \
        QSOE_RUST_TM_CPIO=1 \
        QSOE_RUST_TM_CRED=0 \
        QSOE_RUST_TM_ELF=1 \
        QSOE_RUST_TM_FDT=0 \
        QSOE_RUST_TM_PROCFS=1 \
        QSOE_RUST_TM_PSEUDODEV=0 \
        QSOE_RUST_TM_RSRCDB=0 \
        QSOE_RUST_TM_SCRIPT=1 \
        QSOE_RUST_TM_SYSCFG=1 \
        QSOE_RUST_TM_SYSMAP="$rust_selected" \
        QSOE_RUST_TM_SYSFS=1 \
        > "$log"
}

require_plan_contains() {
    local label=$1
    local needle=$2
    local log="$WORKDIR/$label-taskman-dry-run.txt"

    grep -Fq "$needle" "$log" ||
        fail "$label dry-run link plan is missing $needle"
}

require_plan_omits() {
    local label=$1
    local needle=$2
    local log="$WORKDIR/$label-taskman-dry-run.txt"

    if grep -Fq "$needle" "$log"; then
        fail "$label dry-run link plan unexpectedly contains $needle"
    fi
}

build_lq_taskman() {
    local label=$1
    local rust_selected=$2

    rm -f "$ROOT/lq/build/taskman.elf"
    "$MAKE" -C "$ROOT/lq" --no-print-directory \
        QSOE_RUST_TM_CPIO=1 \
        QSOE_RUST_TM_CRED=0 \
        QSOE_RUST_TM_ELF=1 \
        QSOE_RUST_TM_FDT=0 \
        QSOE_RUST_TM_PROCFS=1 \
        QSOE_RUST_TM_PSEUDODEV=0 \
        QSOE_RUST_TM_RSRCDB=0 \
        QSOE_RUST_TM_SCRIPT=1 \
        QSOE_RUST_TM_SYSCFG=1 \
        QSOE_RUST_TM_SYSMAP="$rust_selected" \
        QSOE_RUST_TM_SYSFS=1 \
        taskman
    audit_flags "$label-taskman" "$ROOT/lq/build/taskman.elf"
}

require_retired_selector_rejected() {
    local label=$1
    shift
    local log="$WORKDIR/$label-retired-selector-rejection.txt"

    if "$@" > "$log" 2>&1; then
        fail "$label unexpectedly accepted QSOE_RUST_TM_SYSMAP=0"
    fi
    grep -Fq 'QSOE_RUST_TM_SYSMAP must be 1 after C tm_sysmap retirement' "$log" ||
        fail "$label rejection did not mention retired tm_sysmap selector"
}

echo "tm-sysmap-evidence.sh: running Rust host model tests"
"$MAKE" -C "$ROOT" --no-print-directory check-tm-sysmap-model

echo "tm-sysmap-evidence.sh: building Rust provider archive"
"$MAKE" -C "$ROOT" --no-print-directory rust-tm-sysmap-provider
audit_provider_archive

echo "tm-sysmap-evidence.sh: verifying LQ Rust-only link plan"
capture_lq_taskman_plan lq-rust-retired 1
require_plan_omits lq-rust-retired '/sys/sysmap.o'
require_plan_omits lq-rust-retired 'libqsoe_tm_sysmap.a'
require_plan_contains lq-rust-retired 'libqsoe_tm_providers.a'

echo "tm-sysmap-evidence.sh: verifying LQ Rust-only taskman link"
build_lq_taskman lq-rust-retired 1

echo "tm-sysmap-evidence.sh: verifying LQ retired selector rejection"
require_retired_selector_rejected lq \
    "$MAKE" -C "$ROOT/lq" --no-print-directory QSOE_RUST_TM_SYSMAP=0 taskman
require_retired_selector_rejected lq-taskman \
    "$MAKE" -C "$ROOT/lq/taskman" --no-print-directory QSOE_RUST_TM_SYSMAP=0

echo "tm-sysmap-evidence.sh: evidence captured in $WORKDIR"
