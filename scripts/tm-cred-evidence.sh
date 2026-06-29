#!/usr/bin/env bash
#
# Capture tm_cred Rust opt-in evidence without changing the default provider.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
WORKDIR=${TM_CRED_EVIDENCE_WORKDIR:-"$ROOT/build/tm-cred-evidence"}
RUST_PROVIDER_A=${RUST_PROVIDER_A:-"$ROOT/build/rust/tm-cred/libqsoe_tm_cred.a"}
MANIFEST="$ROOT/rust/Cargo.toml"

usage() {
    cat <<'EOF'
usage: scripts/tm-cred-evidence.sh

Builds and audits the Rust tm_cred opt-in path and verifies C rollback archive
membership for NQ and LQ taskman links.

Environment:
  TM_CRED_EVIDENCE_WORKDIR  output directory, default build/tm-cred-evidence
  RUST_PROVIDER_A           Rust provider archive path
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
        echo "tm-cred-evidence.sh: unknown option: $1" >&2
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
    echo "tm-cred-evidence.sh: no readelf tool found" >&2
    exit 127
}
AR=$(find_tool riscv64-linux-gnu-ar ar llvm-ar) || {
    echo "tm-cred-evidence.sh: no ar tool found" >&2
    exit 127
}
NM=$(find_tool riscv64-linux-gnu-nm nm llvm-nm) || {
    echo "tm-cred-evidence.sh: no nm tool found" >&2
    exit 127
}

mkdir -p "$WORKDIR"

"$ROOT/scripts/apply-component-overrides.sh"

fail() {
    echo "tm-cred-evidence.sh: $*" >&2
    exit 1
}

object_count() {
    local archive=$1
    local object=$2

    "$AR" t "$archive" |
        awk -v object="$object" '$0 == object { n++ } END { print n + 0 }'
}

require_cred_count() {
    local label=$1
    local archive=$2
    local expected=$3
    local count

    [ -f "$archive" ] || fail "missing archive for $label: $archive"
    count=$(object_count "$archive" cred.o)
    printf '%s cred.o count: %s\n' "$label" "$count" |
        tee "$WORKDIR/$label-archive-membership.txt"
    [ "$count" -eq "$expected" ] ||
        fail "$label expected $expected cred.o members, got $count"
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
        tm_cred_init \
        tm_cred_chdir \
        tm_cred_getcwd \
        tm_cred_umask \
        tm_cred_set \
        tm_cred_change_permitted \
        tm_cred_self_info
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

echo "tm-cred-evidence.sh: running C host model fixture"
"$MAKE" -C "$ROOT" --no-print-directory check-tm-cred-model

echo "tm-cred-evidence.sh: running Rust host tests"
cargo test --manifest-path "$MANIFEST" -p qsoe-tm-cred --features host-tests

echo "tm-cred-evidence.sh: building Rust provider archive"
"$MAKE" -C "$ROOT" --no-print-directory rust-tm-cred-provider
audit_provider_archive

echo "tm-cred-evidence.sh: verifying NQ C rollback membership"
"$MAKE" -C "$ROOT/nq/taskman" --no-print-directory \
    QSOE_RUST_TM_CRED=0 QSOE_RUST_TM_PROCFS=1
require_cred_count nq-c-default "$ROOT/nq/build/libtaskman/libtaskman.a" 1
audit_flags nq-c-default-taskman "$ROOT/nq/build/taskman/taskman.elf"

echo "tm-cred-evidence.sh: verifying NQ Rust-selected membership"
"$MAKE" -C "$ROOT/nq/taskman" --no-print-directory \
    QSOE_RUST_TM_CRED=1 QSOE_RUST_TM_PROCFS=1
require_cred_count nq-rust-selected "$ROOT/nq/build/libtaskman/libtaskman.a" 0
audit_flags nq-rust-selected-taskman "$ROOT/nq/build/taskman/taskman.elf"

echo "tm-cred-evidence.sh: verifying LQ C rollback membership"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_CRED=0 QSOE_RUST_TM_PROCFS=1 taskman
require_cred_count lq-c-default "$ROOT/lq/build/libtaskman/libtaskman.a" 1
audit_flags lq-c-default-taskman "$ROOT/lq/build/taskman.elf"

echo "tm-cred-evidence.sh: verifying LQ Rust-selected membership"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_CRED=1 QSOE_RUST_TM_PROCFS=1 taskman
require_cred_count lq-rust-selected "$ROOT/lq/build/libtaskman/libtaskman.a" 0
audit_flags lq-rust-selected-taskman "$ROOT/lq/build/taskman.elf"

echo "tm-cred-evidence.sh: evidence captured in $WORKDIR"
