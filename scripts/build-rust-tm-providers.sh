#!/usr/bin/env bash
#
# Build one soft-float staticlib containing all selected Rust taskman providers.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-"$ROOT/build/rust/tm-providers/libqsoe_tm_providers.a"}
MANIFEST="$ROOT/rust/Cargo.toml"
RUST_TARGET=${RUST_TARGET:-riscv64imac-unknown-none-elf}

. "$ROOT/scripts/rust-env.sh"
qsoe_cargo_set_target_dir "$ROOT" taskman-rust

if ! command -v cargo >/dev/null 2>&1; then
    echo "build-rust-tm-providers.sh: cargo not found" >&2
    exit 127
fi

if ! rustup target list --installed 2>/dev/null | grep -Fxq "$RUST_TARGET"; then
    echo "build-rust-tm-providers.sh: Rust target not installed: $RUST_TARGET" >&2
    echo "Install it with: rustup target add $RUST_TARGET" >&2
    exit 1
fi

features=
selected=0

case "${QSOE_RUST_TM_CPIO:-1}" in
    1|true|TRUE|yes|YES)
        QSOE_RUST_TM_CPIO=1
        ;;
    0|false|FALSE|no|NO)
        echo "build-rust-tm-providers.sh: C tm_cpio is retired; QSOE_RUST_TM_CPIO must be 1" >&2
        exit 2
        ;;
    *)
        echo "build-rust-tm-providers.sh: QSOE_RUST_TM_CPIO must be 1 after C retirement" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_ELF:-1}" in
    1|true|TRUE|yes|YES)
        QSOE_RUST_TM_ELF=1
        ;;
    0|false|FALSE|no|NO)
        echo "build-rust-tm-providers.sh: C tm_elf is retired; QSOE_RUST_TM_ELF must be 1" >&2
        exit 2
        ;;
    *)
        echo "build-rust-tm-providers.sh: QSOE_RUST_TM_ELF must be 1 after C retirement" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_PROCFS:-1}" in
    1|true|TRUE|yes|YES)
        QSOE_RUST_TM_PROCFS=1
        ;;
    0|false|FALSE|no|NO)
        echo "build-rust-tm-providers.sh: C tm_procfs is retired; QSOE_RUST_TM_PROCFS must be 1" >&2
        exit 2
        ;;
    *)
        echo "build-rust-tm-providers.sh: QSOE_RUST_TM_PROCFS must be 1 after C retirement" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_SCRIPT:-1}" in
    1|true|TRUE|yes|YES)
        QSOE_RUST_TM_SCRIPT=1
        ;;
    0|false|FALSE|no|NO)
        echo "build-rust-tm-providers.sh: C tm_script is retired; QSOE_RUST_TM_SCRIPT must be 1" >&2
        exit 2
        ;;
    *)
        echo "build-rust-tm-providers.sh: QSOE_RUST_TM_SCRIPT must be 1 after C retirement" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_SYSCFG:-1}" in
    1|true|TRUE|yes|YES)
        QSOE_RUST_TM_SYSCFG=1
        ;;
    0|false|FALSE|no|NO)
        echo "build-rust-tm-providers.sh: C tm_syscfg is retired; QSOE_RUST_TM_SYSCFG must be 1" >&2
        exit 2
        ;;
    *)
        echo "build-rust-tm-providers.sh: QSOE_RUST_TM_SYSCFG must be 1 after C retirement" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_SYSMAP:-1}" in
    1|true|TRUE|yes|YES)
        QSOE_RUST_TM_SYSMAP=1
        ;;
    0|false|FALSE|no|NO)
        echo "build-rust-tm-providers.sh: C tm_sysmap is retired; QSOE_RUST_TM_SYSMAP must be 1" >&2
        exit 2
        ;;
    *)
        echo "build-rust-tm-providers.sh: QSOE_RUST_TM_SYSMAP must be 1 after C retirement" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_SYSFS:-1}" in
    1|true|TRUE|yes|YES)
        QSOE_RUST_TM_SYSFS=1
        ;;
    0|false|FALSE|no|NO)
        echo "build-rust-tm-providers.sh: C tm_sysfs is retired; QSOE_RUST_TM_SYSFS must be 1" >&2
        exit 2
        ;;
    *)
        echo "build-rust-tm-providers.sh: QSOE_RUST_TM_SYSFS must be 1 after C retirement" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_CRED:-1}" in
    1|true|TRUE|yes|YES)
        QSOE_RUST_TM_CRED=1
        ;;
    0|false|FALSE|no|NO)
        echo "build-rust-tm-providers.sh: C tm_cred is retired; QSOE_RUST_TM_CRED must be 1" >&2
        exit 2
        ;;
    *)
        echo "build-rust-tm-providers.sh: QSOE_RUST_TM_CRED must be 1 after C retirement" >&2
        exit 2
        ;;
esac

add_feature() {
    local var=$1
    local feature=$2
    local value=${!var:-0}

    case "$value" in
        0|false|FALSE|no|NO)
            ;;
        1|true|TRUE|yes|YES)
            features="${features}${features:+ }${feature}"
            selected=$((selected + 1))
            ;;
        *)
            echo "build-rust-tm-providers.sh: $var must be 0 or 1" >&2
            exit 2
            ;;
    esac
}

add_feature QSOE_RUST_TM_CPIO tm-cpio
add_feature QSOE_RUST_TM_CRED tm-cred
add_feature QSOE_RUST_TM_ELF tm-elf
add_feature QSOE_RUST_TM_FDT tm-fdt
add_feature QSOE_RUST_TM_PATHMGR tm-pathmgr
add_feature QSOE_RUST_TM_PROCFS tm-procfs
add_feature QSOE_RUST_TM_PSEUDODEV tm-pseudodev
add_feature QSOE_RUST_TM_RSRCDB tm-rsrcdb
add_feature QSOE_RUST_TM_SCRIPT tm-script
add_feature QSOE_RUST_TM_SYSCFG tm-syscfg
add_feature QSOE_RUST_TM_SYSMAP tm-sysmap
add_feature QSOE_RUST_TM_SYSFS tm-sysfs

if [ "$selected" -eq 0 ]; then
    echo "build-rust-tm-providers.sh: select at least one taskman Rust provider" >&2
    exit 2
fi

cargo build \
    --manifest-path "$MANIFEST" \
    -p qsoe-tm-providers \
    --target "$RUST_TARGET" \
    --release \
    --no-default-features \
    --features "$features"

staticlib="$CARGO_TARGET_DIR/$RUST_TARGET/release/libqsoe_tm_providers.a"
if [ ! -f "$staticlib" ]; then
    echo "build-rust-tm-providers.sh: missing Rust staticlib: $staticlib" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")"
cp "$staticlib" "$OUT"
echo "build-rust-tm-providers.sh: built $OUT with features: $features"
