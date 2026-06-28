#!/usr/bin/env bash
#
# Build the Rust qrvfs image writer host artifact.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-"$ROOT/build/mkfs-qrv-rs"}

if ! command -v cargo >/dev/null 2>&1; then
    echo "mkfs-qrv-rs-artifact.sh: cargo not found" >&2
    exit 127
fi

. "$ROOT/scripts/rust-env.sh"
qsoe_cargo_set_target_dir "$ROOT" host

cargo build \
    --quiet \
    --manifest-path "$ROOT/rust/Cargo.toml" \
    -p qsoe-qrvfs \
    --bin mkfs-qrv-rs

mkdir -p "$(dirname "$OUT")"
cp "$CARGO_TARGET_DIR/debug/mkfs-qrv-rs" "$OUT"
chmod 755 "$OUT"
echo "mkfs-qrv-rs-artifact.sh: $OUT <- Rust mkfs-qrv-rs"
