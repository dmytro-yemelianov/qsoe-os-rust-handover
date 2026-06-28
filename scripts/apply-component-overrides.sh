#!/usr/bin/env bash
#
# Apply tracked handover overrides to component checkouts obtained by
# proj_obtain.sh. The lq/ and nq/ component trees are ignored nested Git
# repositories, so Rust migration glue that must touch their Makefiles lives as
# deterministic patches in this repository.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PATCH_DIR="$ROOT/patches/components"

fail() {
    echo "apply-component-overrides.sh: $*" >&2
    exit 1
}

require_component() {
    local component=$1
    [ -d "$ROOT/$component" ] ||
        fail "missing $component component; run make prepare first"
    [ -f "$ROOT/$component/.git/HEAD" ] ||
        fail "$component is not a Git checkout"
}

apply_patch_if_possible() {
    local component=$1
    local patch_file=$2
    local patch_path="$PATCH_DIR/$patch_file"

    [ -f "$patch_path" ] || fail "missing patch $patch_path"
    if patch -d "$ROOT/$component" --forward --silent --dry-run -p1 < "$patch_path" >/dev/null 2>&1; then
        echo "apply-component-overrides.sh: applying $patch_file"
        patch -d "$ROOT/$component" --forward --silent -p1 < "$patch_path"
    elif patch -d "$ROOT/$component" --reverse --silent --dry-run -p1 < "$patch_path" >/dev/null 2>&1; then
        echo "apply-component-overrides.sh: $patch_file already applied"
    else
        patch -d "$ROOT/$component" --forward --dry-run -p1 < "$patch_path" >&2 || true
        fail "$patch_file does not apply cleanly to $component"
    fi
}

apply_optional_patch() {
    local component=$1
    local patch_file=$2
    local patch_path="$PATCH_DIR/$patch_file"

    [ -f "$patch_path" ] || fail "missing patch $patch_path"
    if patch -d "$ROOT/$component" --forward --silent --dry-run -p1 < "$patch_path" >/dev/null 2>&1; then
        echo "apply-component-overrides.sh: applying $patch_file"
        patch -d "$ROOT/$component" --forward --silent -p1 < "$patch_path"
    elif patch -d "$ROOT/$component" --reverse --silent --dry-run -p1 < "$patch_path" >/dev/null 2>&1; then
        echo "apply-component-overrides.sh: $patch_file already applied"
    fi
}

require_line() {
    local file=$1
    local needle=$2

    grep -Fq "$needle" "$file" ||
        fail "$file is missing expected override: $needle"
}

# Older self-hosted workspaces may already have the selector patch but with
# earlier link paths or timestamp-only Rust archive rules. Normalize those
# first so required full patches can be recognized as already applied.
require_component nq
require_component lq
require_component quser

apply_optional_patch nq nq-taskman-rust-tm-procfs-root-path.patch
apply_optional_patch lq lq-taskman-rust-tm-procfs-root-path.patch
apply_optional_patch nq nq-taskman-rust-tm-procfs-force-rule.patch
apply_optional_patch lq lq-taskman-rust-tm-procfs-force-rule.patch

apply_patch_if_possible nq nq-taskman-rust-tm-procfs.patch
apply_patch_if_possible lq lq-makefile-rust-tm-procfs.patch
apply_patch_if_possible lq lq-taskman-rust-tm-procfs.patch
apply_patch_if_possible lq lq-msgpass-mcs-teardown-and-bulk-copy.patch
apply_patch_if_possible quser quser-msgpass-lq-no-reply-skip.patch

require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_PROCFS ?= 0'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_PROCFS_A := $(REPO_ROOT)/build/rust/tm-procfs/libqsoe_tm_procfs.a'
require_line "$ROOT/nq/taskman/Makefile" '$(RUST_TM_PROCFS_A): FORCE'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_PROCFS=$(QSOE_RUST_TM_PROCFS)'
require_line "$ROOT/nq/taskman/Makefile" '$(BUILD)/taskman.elf: $(OBJS) $(LIBTASKMAN_A) $(TASKMAN_RUST_LIBS) taskman.ld'

require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_PROCFS ?= 0'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_PROCFS=$(QSOE_RUST_TM_PROCFS)'
require_line "$ROOT/lq/Makefile" '$(LIBTASKMAN_A): FORCE'
require_line "$ROOT/lq/Makefile" 'FORCE:'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_PROCFS ?= 0'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_PROCFS_A := $(REPO_ROOT)/build/rust/tm-procfs/libqsoe_tm_procfs.a'
require_line "$ROOT/lq/taskman/Makefile" '$(RUST_TM_PROCFS_A): FORCE'
require_line "$ROOT/lq/taskman/Makefile" 'FORCE:'
require_line "$ROOT/lq/taskman/Makefile" '$(TASKMAN_ELF): $(TASKMAN_OBJS) $(LIBTASKMAN_A) $(TASKMAN_RUST_LIBS)'
require_line "$ROOT/lq/libc/qsoe/msg.c" 'if (label == QSOE_MSG_BULK_LABEL) {'
require_line "$ROOT/lq/taskman/proc/process.c" 'tm_pathmgr_unregister_pid(target);'
require_line "$ROOT/lq/taskman/proc/spawn.c" 'tm_process_resolve_frame(src_proc, sva'
require_line "$ROOT/quser/test/suite/msgpass_test.c" 'ProcessTerminate(nr_pid, 0) == 0'

echo "apply-component-overrides.sh: component overrides ready"
