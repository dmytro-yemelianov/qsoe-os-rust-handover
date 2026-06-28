#!/usr/bin/env bash
#
# Validate the Rust-default host qrvfs inspector and the C rollback selector.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIXTURE="$ROOT/build/fixtures/qrvfs"
IMG="$FIXTURE/qrvfs-fixture.img"
C_TREE="$FIXTURE/tree.log"
SELECTED_TREE="$FIXTURE/treeqrvfs-selected.log"
TREEQRVFS="$ROOT/build/treeqrvfs"

if [ "${TREEQRVFS_RC_ROLLBACK:-0}" = 1 ]; then
    QSOE_RUST_TREEQRVFS=0
    mode=c-rollback
else
    QSOE_RUST_TREEQRVFS=${QSOE_RUST_TREEQRVFS:-1}
    case "$QSOE_RUST_TREEQRVFS" in
        1|true|yes)
            mode=rust-default
            ;;
        0|false|no)
            mode=c-selected
            ;;
        *)
            mode=selected
            ;;
    esac
fi
export QSOE_RUST_TREEQRVFS

"$ROOT/scripts/check-qrvfs-fixture.sh" >/dev/null
"$ROOT/scripts/treeqrvfs-artifact.sh" "$TREEQRVFS" >/dev/null

"$TREEQRVFS" "$IMG" > "$SELECTED_TREE"

if ! diff -u "$C_TREE" "$SELECTED_TREE"; then
    echo "treeqrvfs-rc-smoke.sh: selected treeqrvfs output diverges" >&2
    exit 1
fi

echo "treeqrvfs-rc-smoke.sh: $mode passed"
echo "  image:    $IMG"
echo "  c oracle: $C_TREE"
echo "  selected: $SELECTED_TREE"
