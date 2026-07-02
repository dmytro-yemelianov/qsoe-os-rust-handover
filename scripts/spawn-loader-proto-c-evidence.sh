#!/bin/sh
set -eu

OUT_DIR="build/spawn-loader-proto-c-evidence"
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
echo "tm_loader_proto C seam evidence" >> "$SUMMARY"
echo "source: $SRC" >> "$SUMMARY"

require_source "typedef struct tm_loader_proto" "bounded loader protocol type"
require_source "tm_loader_proto_admit_dynamic" "dynamic loader protocol admission seam"
require_source "proto->main_phdr_va" "AT_PHDR state recorded in protocol"
require_source "proto->rtld_load_base" "AT_BASE state recorded in protocol"
require_source "proto->entry_pc" "entry PC recorded in protocol"
require_source "proto->dyn_link" "dynamic-link mode recorded in protocol"
require_source "tm_loader_proto_admit_dynamic(&loader_proto" "C-owned dynamic admission call site"
require_source "tm_reloc_apply(&main_view" "relocation authority remains in C before protocol admission"
require_source "loader_proto.dyn_link" "auxv emission gated by protocol state"
require_source "loader_proto.main_phdr_va" "AT_PHDR auxv consumes protocol state"
require_source "loader_proto.rtld_load_base" "AT_BASE auxv consumes protocol state"
require_source "loader_proto.entry_pc" "AT_ENTRY and TCB PC consume protocol state"
require_source "qsoe_tcb_write_registers" "TCB authority remains in C commit path"

echo "result: PASS" >> "$SUMMARY"
cat "$SUMMARY"
