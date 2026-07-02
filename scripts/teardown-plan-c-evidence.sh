#!/bin/sh
set -eu

OUT_DIR="build/teardown-plan-c-evidence"
SUMMARY="$OUT_DIR/summary.txt"
SRC="lq/taskman/proc/process.c"

mkdir -p "$OUT_DIR"

require_source() {
    pattern="$1"
    description="$2"
    if ! grep -Fq "$pattern" "$SRC"; then
        echo "missing: $description ($pattern)" >&2
        exit 1
    fi
    echo "present: $description" >> "$SUMMARY"
}

: > "$SUMMARY"
echo "tm_teardown_plan C seam evidence" >> "$SUMMARY"
echo "source: $SRC" >> "$SUMMARY"

require_source "typedef struct tm_teardown_plan" "bounded teardown plan type"
require_source "typedef struct tm_teardown_op" "typed teardown operation entries"
require_source "TM_TEARDOWN_PLAN_MAX_OPS" "teardown operation bound"
require_source "TM_TEARDOWN_REVOKE_DELETE_FREE" "revoke/delete/free operation kind"
require_source "TM_TEARDOWN_DELETE_FREE" "delete/free operation kind"
require_source "TM_TEARDOWN_FREE_ONLY" "free-only operation kind"
require_source "tm_teardown_plan_add" "teardown plan preparation seam"
require_source "tm_teardown_plan_commit" "C-owned teardown authority commit seam"
require_source "qsoe_cnode_revoke(s_cnode_root" "revoke authority remains in C commit path"
require_source "qsoe_cnode_delete(s_cnode_root" "delete authority remains in C commit path"
require_source "taskman_free_slot(op->slot" "slot free remains in C commit path"

echo "result: PASS" >> "$SUMMARY"
cat "$SUMMARY"
