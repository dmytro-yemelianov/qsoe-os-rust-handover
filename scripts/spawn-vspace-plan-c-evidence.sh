#!/bin/sh
set -eu

OUT_DIR="build/spawn-vspace-plan-c-evidence"
SUMMARY="$OUT_DIR/summary.txt"
SRC="lq/taskman/proc/spawn.c"

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
echo "tm_vspace_plan C seam evidence" >> "$SUMMARY"
echo "source: $SRC" >> "$SUMMARY"

require_source "typedef struct tm_vspace_plan" "bounded vspace plan type"
require_source "typedef struct tm_vspace_op" "typed vspace operation entries"
require_source "TM_VSPACE_PLAN_MAX_OPS" "vspace operation bound"
require_source "TM_VSPACE_OP_PAGETABLE_MAP" "page-table map operation kind"
require_source "TM_VSPACE_OP_PAGE_MAP" "page map operation kind"
require_source "tm_vspace_plan_add_pt" "page-table map preparation seam"
require_source "tm_vspace_plan_add_page" "page map preparation seam"
require_source "tm_vspace_plan_commit" "C-owned vspace authority commit seam"
require_source "qsoe_riscv_pagetable_map" "page-table authority remains in C commit path"
require_source "qsoe_riscv_page_map" "page authority remains in C commit path"
require_source "spawn_record_pt(op->cap" "mapped page-table caps remain recorded by C"
require_source "spawn_record_frame(op->va" "mapped frame caps remain recorded by C"

echo "result: PASS" >> "$SUMMARY"
cat "$SUMMARY"
