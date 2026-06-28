#!/usr/bin/env bash
#
# Select the host qrvfs tree inspector artifact.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-"$ROOT/build/treeqrvfs"}
MODE=${QSOE_RUST_TREEQRVFS:-1}
CC=${CC:-cc}

case "$MODE" in
    1|true|yes)
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
        ;;
    0|false|no)
        mkdir -p "$(dirname "$OUT")"
        "$CC" -O2 -Wall -Wno-unused-variable -I "$ROOT/quser/fs/qrv" \
            -o "$OUT" "$ROOT/host_tools/treeqrvfs.c"
        echo "treeqrvfs-artifact.sh: $OUT <- C treeqrvfs"
        ;;
    *)
        echo "treeqrvfs-artifact.sh: unsupported QSOE_RUST_TREEQRVFS=$MODE" >&2
        exit 2
        ;;
esac
