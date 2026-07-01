#!/usr/bin/env bash
#
# Capture evidence for the Rust-default taskman logging formatter provider.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
WORKDIR=${TM_LOG_EVIDENCE_WORKDIR:-"$ROOT/build/tm-log-evidence"}
RUST_PROVIDERS_A=${RUST_PROVIDERS_A:-"$ROOT/build/rust/tm-providers/libqsoe_tm_providers.a"}

usage() {
    cat <<'EOF'
usage: scripts/tm-log-evidence.sh

Builds and audits the tm_log formatter RC/default path:

  QSOE_RUST_TM_LOG=1  selects the Rust qsoe-tm-log provider
  QSOE_RUST_TM_LOG=0  keeps the weak C fallback formatter

The exported C variadic tm_log(...) entry point remains in C. This script only
audits the typed tm_log_emit_args(...) formatter boundary.

Environment:
  TM_LOG_EVIDENCE_WORKDIR  output directory, default build/tm-log-evidence
  RUST_PROVIDERS_A         shared Rust provider archive path
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
        echo "tm-log-evidence.sh: unknown option: $1" >&2
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
    echo "tm-log-evidence.sh: no readelf tool found" >&2
    exit 127
}
NM=$(find_tool riscv64-linux-gnu-nm nm llvm-nm) || {
    echo "tm-log-evidence.sh: no nm tool found" >&2
    exit 127
}

mkdir -p "$WORKDIR"

fail() {
    echo "tm-log-evidence.sh: $*" >&2
    exit 1
}

symbol_type_count() {
    local symbols=$1
    local types=$2
    local symbol=$3

    awk -v types="$types" -v symbol="$symbol" '
        NF >= 3 && $NF == symbol && index(types, $(NF - 1)) { n++ }
        END { print n + 0 }
    ' "$symbols"
}

require_symbol_type() {
    local label=$1
    local symbols=$2
    local types=$3
    local symbol=$4
    local count

    count=$(symbol_type_count "$symbols" "$types" "$symbol")
    [ "$count" -gt 0 ] ||
        fail "$label is missing $symbol with type in [$types]"
}

require_symbol_absent() {
    local label=$1
    local symbols=$2
    local symbol=$3

    if awk -v symbol="$symbol" '$NF == symbol { found = 1 } END { exit found ? 0 : 1 }' "$symbols"; then
        fail "$label unexpectedly contains symbol $symbol"
    fi
}

capture_symbols() {
    local input=$1
    local out=$2

    [ -e "$input" ] || fail "missing symbol input: $input"
    "$NM" -g --defined-only "$input" > "$out"
}

audit_elf_flags() {
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
    local header="$WORKDIR/rust-provider-readelf-header.txt"
    local sections="$WORKDIR/rust-provider-readelf-sections.txt"
    local symbols="$WORKDIR/rust-provider-symbols.txt"
    local total
    local soft_float

    [ -f "$RUST_PROVIDERS_A" ] || fail "missing shared provider archive: $RUST_PROVIDERS_A"
    "$READELF" -h "$RUST_PROVIDERS_A" > "$header"
    "$READELF" -S "$RUST_PROVIDERS_A" > "$sections"
    capture_symbols "$RUST_PROVIDERS_A" "$symbols"

    total=$(awk '/Flags:/ { n++ } END { print n + 0 }' "$header")
    soft_float=$(awk '/Flags:/ && /RVC, soft-float ABI/ { n++ } END { print n + 0 }' "$header")
    [ "$total" -gt 0 ] || fail "shared provider archive contains no ELF members"
    [ "$total" -eq "$soft_float" ] ||
        fail "shared provider archive has $soft_float/$total soft-float members"

    require_symbol_type rust-provider "$symbols" Tt tm_log_emit_args
    require_symbol_type rust-provider "$symbols" Tt qsoe_tm_log_provider_anchor

    if grep -Eq '(\.(tdata|tbss|init_array|fini_array|ctors|dtors|gcc_except_table))' "$sections"; then
        fail "shared provider archive contains unsupported TLS or constructor sections"
    fi

    {
        printf 'rust provider archive members: %s\n' "$total"
        printf 'rust provider soft-float members: %s\n' "$soft_float"
        printf 'rust provider tm_log_emit_args strong symbols: %s\n' \
            "$(symbol_type_count "$symbols" Tt tm_log_emit_args)"
    } | tee "$WORKDIR/rust-provider-summary.txt"
}

audit_fallback_build() {
    local log_obj="$ROOT/nq/build/libtaskman/log.o"
    local log_lib="$ROOT/nq/build/libtaskman/libtaskman.a"
    local elf="$ROOT/nq/build/taskman/taskman.elf"
    local log_symbols="$WORKDIR/nq-c-fallback-log-symbols.txt"
    local elf_symbols="$WORKDIR/nq-c-fallback-taskman-symbols.txt"

    echo "tm-log-evidence.sh: building explicit C fallback selector"
    rm -f "$log_obj" "$log_lib" "$elf"
    "$MAKE" -C "$ROOT/nq/taskman" --no-print-directory QSOE_RUST_TM_LOG=0

    capture_symbols "$log_obj" "$log_symbols"
    capture_symbols "$elf" "$elf_symbols"
    require_symbol_type c-fallback-log "$log_symbols" Ww tm_log_emit_args
    require_symbol_type c-fallback-taskman "$elf_symbols" Ww tm_log_emit_args
    require_symbol_absent c-fallback-taskman "$elf_symbols" qsoe_tm_log_provider_anchor
    audit_elf_flags nq-c-fallback-taskman "$elf"
}

audit_rust_selected_build() {
    local log_obj="$ROOT/lq/build/libtaskman/log.o"
    local log_lib="$ROOT/lq/build/libtaskman/libtaskman.a"
    local elf="$ROOT/lq/build/taskman.elf"
    local log_symbols="$WORKDIR/lq-rust-selected-log-symbols.txt"
    local elf_symbols="$WORKDIR/lq-rust-selected-taskman-symbols.txt"

    echo "tm-log-evidence.sh: building default Rust-selected provider archive"
    "$MAKE" -C "$ROOT" --no-print-directory rust-tm-providers
    audit_provider_archive

    echo "tm-log-evidence.sh: building LQ image with Rust tm_log formatter selected"
    rm -f "$log_obj" "$log_lib" "$elf"
    "$MAKE" -C "$ROOT/lq" --no-print-directory QSOE_RUST_TM_LOG=1

    capture_symbols "$log_obj" "$log_symbols"
    capture_symbols "$elf" "$elf_symbols"
    require_symbol_type rust-selected-c-log "$log_symbols" Ww tm_log_emit_args
    require_symbol_type rust-selected-taskman "$elf_symbols" Tt tm_log_emit_args
    require_symbol_type rust-selected-taskman "$elf_symbols" Tt qsoe_tm_log_provider_anchor
    audit_elf_flags lq-rust-selected-taskman "$elf"
}

boot_rust_selected_lq() {
    local log="$WORKDIR/boot-smoke-lq-tm-log-rc.log"

    echo "tm-log-evidence.sh: booting LQ with Rust tm_log formatter selected"
    QSOE_BOOT_EXTRA_PATTERNS="$(printf '%s\n' 'spawning /sbin/init' 'dispatcher ready')" \
        QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
        "$ROOT/scripts/boot-smoke.sh" -k lq -t 180 -o "$log" -- --debug=1
}

"$ROOT/scripts/apply-component-overrides.sh"

audit_fallback_build
audit_rust_selected_build
boot_rust_selected_lq

echo "tm-log-evidence.sh: evidence captured in $WORKDIR"
