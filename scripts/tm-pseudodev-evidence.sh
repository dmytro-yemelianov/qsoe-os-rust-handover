#!/usr/bin/env bash
#
# Capture LQ tm_pseudodev Rust opt-in evidence without changing the default.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
WORKDIR=${TM_PSEUDODEV_EVIDENCE_WORKDIR:-"$ROOT/build/tm-pseudodev-evidence"}
RUST_PROVIDER_A=${RUST_PROVIDER_A:-"$ROOT/build/rust/tm-pseudodev/libqsoe_tm_pseudodev.a"}
MANIFEST="$ROOT/rust/Cargo.toml"

usage() {
    cat <<'EOF'
usage: scripts/tm-pseudodev-evidence.sh

Builds and audits the Rust LQ taskman pseudo-device opt-in path and verifies
that C remains the default rollback provider for /dev/null and /dev/zero.

Environment:
  TM_PSEUDODEV_EVIDENCE_WORKDIR  output directory, default build/tm-pseudodev-evidence
  RUST_PROVIDER_A                Rust provider archive path
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
        echo "tm-pseudodev-evidence.sh: unknown option: $1" >&2
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
    echo "tm-pseudodev-evidence.sh: no readelf tool found" >&2
    exit 127
}
NM=$(find_tool riscv64-linux-gnu-nm nm llvm-nm) || {
    echo "tm-pseudodev-evidence.sh: no nm tool found" >&2
    exit 127
}

mkdir -p "$WORKDIR"

"$ROOT/scripts/apply-component-overrides.sh"

fail() {
    echo "tm-pseudodev-evidence.sh: $*" >&2
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
    if grep -Eq '(\.(tdata|tbss|init_array|fini_array|ctors|dtors|gcc_except_table|debug_frame)| TLS )' "$sections"; then
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
        tm_devnull_write \
        tm_devnull_read \
        tm_devnull_stat \
        tm_devzero_write \
        tm_devzero_read \
        tm_devzero_stat
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
        QSOE_RUST_TM_CRED=0 \
        QSOE_RUST_TM_PROCFS=1 \
        QSOE_RUST_TM_PSEUDODEV="$rust_selected" \
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
        QSOE_RUST_TM_CRED=0 \
        QSOE_RUST_TM_PROCFS=1 \
        QSOE_RUST_TM_PSEUDODEV="$rust_selected" \
        taskman
    audit_flags "$label-taskman" "$ROOT/lq/build/taskman.elf"
}

echo "tm-pseudodev-evidence.sh: running Rust host tests"
cargo test --manifest-path "$MANIFEST" -p qsoe-tm-pseudodev --features host-tests

echo "tm-pseudodev-evidence.sh: building Rust provider archive"
"$MAKE" -C "$ROOT" --no-print-directory rust-tm-pseudodev-provider
audit_provider_archive

echo "tm-pseudodev-evidence.sh: verifying LQ C-default link plan"
capture_lq_taskman_plan lq-c-default 0
require_plan_contains lq-c-default '/sys/devnull.o'
require_plan_contains lq-c-default '/sys/devzero.o'
require_plan_omits lq-c-default 'libqsoe_tm_pseudodev.a'
require_plan_contains lq-c-default 'libqsoe_tm_providers.a'

echo "tm-pseudodev-evidence.sh: verifying LQ C-default taskman link"
build_lq_taskman lq-c-default 0

echo "tm-pseudodev-evidence.sh: verifying LQ Rust-selected link plan"
capture_lq_taskman_plan lq-rust-selected 1
require_plan_omits lq-rust-selected '/sys/devnull.o'
require_plan_omits lq-rust-selected '/sys/devzero.o'
require_plan_omits lq-rust-selected 'libqsoe_tm_pseudodev.a'
require_plan_contains lq-rust-selected 'libqsoe_tm_providers.a'

echo "tm-pseudodev-evidence.sh: verifying LQ Rust-selected taskman link"
build_lq_taskman lq-rust-selected 1

echo "tm-pseudodev-evidence.sh: evidence captured in $WORKDIR"
