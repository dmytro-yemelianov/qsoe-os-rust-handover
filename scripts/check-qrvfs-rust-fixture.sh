#!/usr/bin/env bash
#
# Compare the selected qrvfs-tree artifact against the Rust canonical fixture.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIXTURE="$ROOT/build/fixtures/qrvfs"
IMG="$FIXTURE/qrvfs-fixture.img"
CANONICAL_TREE="$FIXTURE/tree.log"
SELECTED_TREE="$FIXTURE/rust-tree.log"
TREEQRVFS="$FIXTURE/qrvfs-tree-selected"

"$ROOT/scripts/check-qrvfs-fixture.sh" >/dev/null
"$ROOT/scripts/treeqrvfs-artifact.sh" "$TREEQRVFS" >/dev/null

"$TREEQRVFS" "$IMG" > "$SELECTED_TREE"

if ! diff -u "$CANONICAL_TREE" "$SELECTED_TREE"; then
    echo "check-qrvfs-rust-fixture.sh: selected qrvfs-tree output diverges" >&2
    exit 1
fi

echo "check-qrvfs-rust-fixture.sh: ok"
echo "  image:     $IMG"
echo "  canonical: $CANONICAL_TREE"
echo "  selected:  $SELECTED_TREE"
