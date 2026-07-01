#!/usr/bin/env bash
#
# Build the normal staged qrvfs root, then write and inspect Rust images from it.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIXTURE="$ROOT/build/fixtures/qrvfs-rust-production-root"
ROOTDIR="$ROOT/build/fsqrv-root"
PROD_IMG="$ROOT/build/fsqrv.img"
RUST_IMG="$FIXTURE/fsqrv-rust.img"
PROD_TREE="$FIXTURE/tree-production.log"
RUST_TREE="$FIXTURE/tree-rust-writer.log"
PROD_BUILD_LOG="$FIXTURE/mkfs-production.log"
RUST_BUILD_LOG="$FIXTURE/mkfs-rust.log"
MANIFEST="$ROOT/rust/Cargo.toml"

. "$ROOT/scripts/rust-env.sh"
qsoe_cargo_set_target_dir "$ROOT" host

if ! command -v cargo >/dev/null 2>&1; then
    echo "check-qrvfs-rust-writer-production-root.sh: cargo not found" >&2
    exit 127
fi

mkdir -p "$FIXTURE"

make -C "$ROOT" --no-print-directory fsqrv-image > "$PROD_BUILD_LOG"
if [ ! -f "$PROD_IMG" ] || [ ! -d "$ROOTDIR" ]; then
    echo "check-qrvfs-rust-writer-production-root.sh: fsqrv-image was not built" >&2
    echo "--- $PROD_BUILD_LOG ---" >&2
    cat "$PROD_BUILD_LOG" >&2
    exit 1
fi

cargo build \
    --quiet \
    --manifest-path "$MANIFEST" \
    -p qsoe-qrvfs \
    --bin mkfs-qrv-rs \
    --bin qrvfs-tree

"$CARGO_TARGET_DIR/debug/mkfs-qrv-rs" -s 16 "$RUST_IMG" "$ROOTDIR" > "$RUST_BUILD_LOG"
"$CARGO_TARGET_DIR/debug/qrvfs-tree" "$PROD_IMG" > "$PROD_TREE"
"$CARGO_TARGET_DIR/debug/qrvfs-tree" "$RUST_IMG" > "$RUST_TREE"

require() {
    pattern=$1
    file=$2
    if ! grep -Fq "$pattern" "$file"; then
        echo "check-qrvfs-rust-writer-production-root.sh: missing pattern in $file: $pattern" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        exit 1
    fi
}

for tree in "$PROD_TREE" "$RUST_TREE"; do
    require "qrvfs v2, 4096 blocks, 128 inodes" "$tree"
    require "home" "$tree"
    require "user" "$tree"
    require ".profile" "$tree"
    require "conf" "$tree"
    require "shadow" "$tree"
    require "group" "$tree"
    require "passwd" "$tree"
    require "sbin" "$tree"
    require "sysinit" "$tree"
    require "level1.sh" "$tree"
    require "login" "$tree"
    require "getty" "$tree"
    require "bin" "$tree"
    require "suite" "$tree"
    require "test_msgpass" "$tree"
    require "test_syncspace" "$tree"
    require "time" "$tree"
    require "sysinfo" "$tree"
    require "6 directories, 12 files" "$tree"
done

prod_count=$(tail -n 1 "$PROD_TREE")
rust_count=$(tail -n 1 "$RUST_TREE")
if [ "$prod_count" != "$rust_count" ]; then
    echo "check-qrvfs-rust-writer-production-root.sh: production/Rust tree counts diverge" >&2
    echo "Production: $prod_count" >&2
    echo "Rust:       $rust_count" >&2
    exit 1
fi

echo "check-qrvfs-rust-writer-production-root.sh: ok"
echo "  root:             $ROOTDIR"
echo "  production image: $PROD_IMG"
echo "  rebuilt image:    $RUST_IMG"
