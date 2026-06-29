#!/usr/bin/env bash
#
# Build the Rust LQ taskman sysmap builder provider as a soft-float staticlib.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-"$ROOT/build/rust/tm-sysmap/libqsoe_tm_sysmap.a"}
MANIFEST="$ROOT/rust/Cargo.toml"
RUST_TARGET=${RUST_TARGET:-riscv64imac-unknown-none-elf}

QSOE_RUST_TM_SYSMAP=1 exec "$ROOT/scripts/build-rust-tm-providers.sh" "$OUT"

. "$ROOT/scripts/rust-env.sh"
qsoe_cargo_set_target_dir "$ROOT" taskman-rust

if ! command -v cargo >/dev/null 2>&1; then
    echo "build-rust-tm-sysmap-provider.sh: cargo not found" >&2
    exit 127
fi

if ! rustup target list --installed 2>/dev/null | grep -Fxq "$RUST_TARGET"; then
    echo "build-rust-tm-sysmap-provider.sh: Rust target not installed: $RUST_TARGET" >&2
    echo "Install it with: rustup target add $RUST_TARGET" >&2
    exit 1
fi

cargo build \
    --manifest-path "$MANIFEST" \
    -p qsoe-tm-sysmap \
    --target "$RUST_TARGET" \
    --release

staticlib="$CARGO_TARGET_DIR/$RUST_TARGET/release/libqsoe_tm_sysmap.a"
if [ ! -f "$staticlib" ]; then
    echo "build-rust-tm-sysmap-provider.sh: missing Rust staticlib: $staticlib" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")"
cp "$staticlib" "$OUT"
echo "build-rust-tm-sysmap-provider.sh: built $OUT"
