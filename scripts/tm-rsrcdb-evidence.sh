#!/usr/bin/env bash
#
# Capture LQ tm_rsrcdb Rust-default RC evidence while keeping C rollback alive.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
WORKDIR=${TM_RSRCDB_EVIDENCE_WORKDIR:-"$ROOT/build/tm-rsrcdb-evidence"}
RUST_PROVIDER_A=${RUST_PROVIDER_A:-"$ROOT/build/rust/tm-rsrcdb/libqsoe_tm_rsrcdb.a"}
MANIFEST="$ROOT/rust/Cargo.toml"

usage() {
    cat <<'EOF'
usage: scripts/tm-rsrcdb-evidence.sh

Builds and audits the Rust LQ taskman resource-DB default path and verifies
that C remains available as the explicit rollback provider for sys/rsrcdb.c.

Environment:
  TM_RSRCDB_EVIDENCE_WORKDIR  output directory, default build/tm-rsrcdb-evidence
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
        echo "tm-rsrcdb-evidence.sh: unknown option: $1" >&2
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
    echo "tm-rsrcdb-evidence.sh: no readelf tool found" >&2
    exit 127
}
NM=$(find_tool riscv64-linux-gnu-nm nm llvm-nm) || {
    echo "tm-rsrcdb-evidence.sh: no nm tool found" >&2
    exit 127
}

mkdir -p "$WORKDIR"

"$ROOT/scripts/apply-component-overrides.sh"

fail() {
    echo "tm-rsrcdb-evidence.sh: $*" >&2
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
        tm_rsrc_init \
        tm_rsrc_create \
        tm_rsrc_destroy \
        tm_rsrc_attach \
        tm_rsrc_detach \
        tm_rsrc_query \
        tm_rsrc_release_pid \
        tm_rsrc_seed_from_syscfg
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
        QSOE_RUST_TM_CRED=1 \
        QSOE_RUST_TM_PROCFS=1 \
        QSOE_RUST_TM_PSEUDODEV=0 \
        QSOE_RUST_TM_RSRCDB="$rust_selected" \
        QSOE_RUST_TM_SCRIPT=1 \
        QSOE_RUST_TM_SYSCFG=1 \
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
        QSOE_RUST_TM_CRED=1 \
        QSOE_RUST_TM_PROCFS=1 \
        QSOE_RUST_TM_PSEUDODEV=0 \
        QSOE_RUST_TM_RSRCDB="$rust_selected" \
        QSOE_RUST_TM_SCRIPT=1 \
        QSOE_RUST_TM_SYSCFG=1 \
        QSOE_RUST_TM_SYSFS=1 \
        taskman
    audit_flags "$label-taskman" "$ROOT/lq/build/taskman.elf"
}

echo "tm-rsrcdb-evidence.sh: running C host model"
"$MAKE" -C "$ROOT" --no-print-directory check-tm-rsrcdb-model

echo "tm-rsrcdb-evidence.sh: running Rust host tests"
cargo test --manifest-path "$MANIFEST" -p qsoe-tm-rsrcdb --features host-tests

echo "tm-rsrcdb-evidence.sh: building Rust provider archive"
"$MAKE" -C "$ROOT" --no-print-directory rust-tm-rsrcdb-provider
audit_provider_archive

echo "tm-rsrcdb-evidence.sh: verifying LQ Rust-default link plan"
capture_lq_taskman_plan lq-rust-default 1
require_plan_omits lq-rust-default '/sys/rsrcdb.o'
require_plan_omits lq-rust-default 'libqsoe_tm_rsrcdb.a'
require_plan_contains lq-rust-default 'libqsoe_tm_providers.a'

echo "tm-rsrcdb-evidence.sh: verifying LQ Rust-default taskman link"
build_lq_taskman lq-rust-default 1

echo "tm-rsrcdb-evidence.sh: verifying LQ C-rollback link plan"
capture_lq_taskman_plan lq-c-rollback 0
require_plan_contains lq-c-rollback '/sys/rsrcdb.o'
require_plan_omits lq-c-rollback 'libqsoe_tm_rsrcdb.a'
require_plan_contains lq-c-rollback 'libqsoe_tm_providers.a'

echo "tm-rsrcdb-evidence.sh: verifying LQ C-rollback taskman link"
build_lq_taskman lq-c-rollback 0

echo "tm-rsrcdb-evidence.sh: evidence captured in $WORKDIR"
