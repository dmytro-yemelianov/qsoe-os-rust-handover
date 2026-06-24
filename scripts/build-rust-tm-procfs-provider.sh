#!/usr/bin/env bash
#
# Build the Rust tm_procfs provider as a soft-float staticlib for taskman.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-"$ROOT/build/rust/tm-procfs/libqsoe_tm_procfs.a"}
MANIFEST="$ROOT/rust/Cargo.toml"
RUST_TARGET=${RUST_TARGET:-riscv64imac-unknown-none-elf}

. "$ROOT/scripts/rust-env.sh"
qsoe_cargo_set_target_dir "$ROOT" taskman-rust

if ! command -v cargo >/dev/null 2>&1; then
    echo "build-rust-tm-procfs-provider.sh: cargo not found" >&2
    exit 127
fi

if ! rustup target list --installed 2>/dev/null | grep -Fxq "$RUST_TARGET"; then
    echo "build-rust-tm-procfs-provider.sh: Rust target not installed: $RUST_TARGET" >&2
    echo "Install it with: rustup target add $RUST_TARGET" >&2
    exit 1
fi

cargo build \
    --manifest-path "$MANIFEST" \
    -p qsoe-tm-procfs \
    --target "$RUST_TARGET" \
    --release

staticlib="$CARGO_TARGET_DIR/$RUST_TARGET/release/libqsoe_tm_procfs.a"
if [ ! -f "$staticlib" ]; then
    echo "build-rust-tm-procfs-provider.sh: missing Rust staticlib: $staticlib" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")"
cp "$staticlib" "$OUT"
echo "build-rust-tm-procfs-provider.sh: built $OUT"
