#!/usr/bin/env bash
#
# Validate the retired-C Rust-only host qrvfs inspector selector.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIXTURE="$ROOT/build/fixtures/qrvfs"
IMG="$FIXTURE/qrvfs-fixture.img"
CANONICAL_TREE="$FIXTURE/tree.log"
SELECTED_TREE="$FIXTURE/treeqrvfs-selected.log"
TREEQRVFS="$ROOT/build/treeqrvfs"

case "${TREEQRVFS_RC_ROLLBACK:-0}" in
    0)
        ;;
    1)
        echo "treeqrvfs-rc-smoke.sh: C treeqrvfs rollback is retired" >&2
        exit 2
        ;;
    *)
        echo "treeqrvfs-rc-smoke.sh: TREEQRVFS_RC_ROLLBACK must be 0 after C retirement" >&2
        exit 2
        ;;
esac

QSOE_RUST_TREEQRVFS=${QSOE_RUST_TREEQRVFS:-1}
case "$QSOE_RUST_TREEQRVFS" in
    1|true|TRUE|yes|YES)
        mode=rust-only
        ;;
    0|false|FALSE|no|NO)
        echo "treeqrvfs-rc-smoke.sh: C treeqrvfs is retired; use Rust qrvfs-tree" >&2
        exit 2
        ;;
    *)
        echo "treeqrvfs-rc-smoke.sh: QSOE_RUST_TREEQRVFS must be 1 after C retirement" >&2
        exit 2
        ;;
esac
export QSOE_RUST_TREEQRVFS

"$ROOT/scripts/check-qrvfs-fixture.sh" >/dev/null
"$ROOT/scripts/treeqrvfs-artifact.sh" "$TREEQRVFS" >/dev/null

"$TREEQRVFS" "$IMG" > "$SELECTED_TREE"

if ! diff -u "$CANONICAL_TREE" "$SELECTED_TREE"; then
    echo "treeqrvfs-rc-smoke.sh: selected qrvfs-tree output diverges" >&2
    exit 1
fi

echo "treeqrvfs-rc-smoke.sh: $mode passed"
echo "  image:    $IMG"
echo "  canonical: $CANONICAL_TREE"
echo "  selected: $SELECTED_TREE"
