#!/usr/bin/env bash
#
# Build the retired-C host qrvfs tree inspector artifact.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-"$ROOT/build/treeqrvfs"}
MODE=${QSOE_RUST_TREEQRVFS:-1}

case "$MODE" in
    1|true|TRUE|yes|YES)
        ;;
    0|false|FALSE|no|NO)
        echo "treeqrvfs-artifact.sh: C treeqrvfs is retired; use Rust qrvfs-tree" >&2
        exit 2
        ;;
    *)
        echo "treeqrvfs-artifact.sh: QSOE_RUST_TREEQRVFS must be 1 after C retirement" >&2
        exit 2
        ;;
esac

if ! command -v cargo >/dev/null 2>&1; then
    echo "treeqrvfs-artifact.sh: cargo not found for Rust qrvfs-tree" >&2
    exit 127
fi

. "$ROOT/scripts/rust-env.sh"
qsoe_cargo_set_target_dir "$ROOT" host

cargo build \
    --quiet \
    --manifest-path "$ROOT/rust/Cargo.toml" \
    -p qsoe-qrvfs \
    --bin qrvfs-tree

mkdir -p "$(dirname "$OUT")"
cp "$CARGO_TARGET_DIR/debug/qrvfs-tree" "$OUT"
chmod 755 "$OUT"
echo "treeqrvfs-artifact.sh: $OUT <- Rust qrvfs-tree"
