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

apply_patch_if_possible_or_present() {
    local component=$1
    local patch_file=$2
    local marker_file=$3
    local marker=$4
    local patch_path="$PATCH_DIR/$patch_file"

    [ -f "$patch_path" ] || fail "missing patch $patch_path"
    if grep -Fq "$marker" "$marker_file"; then
        echo "apply-component-overrides.sh: $patch_file already represented"
    elif patch -d "$ROOT/$component" --forward --silent --dry-run -p1 < "$patch_path" >/dev/null 2>&1; then
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

require_adjacent_contains() {
    local file=$1
    local first=$2
    local second=$3

    awk -v first="$first" -v second="$second" '
        index(prev, first) && index($0, second) { found = 1 }
        { prev = $0 }
        END { exit found ? 0 : 1 }
    ' "$file" ||
        fail "$file is missing expected adjacent override: $first -> $second"
}

require_before_contains() {
    local file=$1
    local first=$2
    local second=$3

    awk -v first="$first" -v second="$second" '
        index($0, first) { seen = 1 }
        index($0, second) { found_second = 1; ok = seen; exit }
        END { exit (found_second && ok) ? 0 : 1 }
    ' "$file" ||
        fail "$file is missing expected override order: $first before $second"
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

apply_patch_if_possible_or_present nq nq-taskman-rust-tm-procfs.patch \
    "$ROOT/nq/taskman/Makefile" \
    'RUST_TM_PROCFS_A := $(REPO_ROOT)/build/rust/tm-procfs/libqsoe_tm_procfs.a'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-cred.patch \
    "$ROOT/nq/taskman/Makefile" \
    'RUST_TM_CRED_A := $(REPO_ROOT)/build/rust/tm-cred/libqsoe_tm_cred.a'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-provider-exclusive.patch \
    "$ROOT/nq/taskman/Makefile" \
    'TM_RUST_PROVIDER_COUNT :='
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-sysfs.patch \
    "$ROOT/nq/taskman/Makefile" \
    'RUST_TM_SYSFS_A := $(REPO_ROOT)/build/rust/tm-sysfs/libqsoe_tm_sysfs.a'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-cpio.patch \
    "$ROOT/nq/taskman/Makefile" \
    'RUST_TM_CPIO_A := $(REPO_ROOT)/build/rust/tm-cpio/libqsoe_tm_cpio.a'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-script.patch \
    "$ROOT/nq/taskman/Makefile" \
    'RUST_TM_SCRIPT_A := $(REPO_ROOT)/build/rust/tm-script/libqsoe_tm_script.a'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-syscfg.patch \
    "$ROOT/nq/taskman/Makefile" \
    'RUST_TM_SYSCFG_A := $(REPO_ROOT)/build/rust/tm-syscfg/libqsoe_tm_syscfg.a'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-procfs.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_PROCFS=$(QSOE_RUST_TM_PROCFS)'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-cred.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED)'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-provider-exclusive.patch \
    "$ROOT/lq/Makefile" \
    'TM_RUST_PROVIDER_COUNT :='
apply_patch_if_possible_or_present lq lq-makefile-force-target.patch \
    "$ROOT/lq/Makefile" \
    'FORCE:'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-pseudodev.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_PSEUDODEV ?= 0'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-sysfs.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SYSFS ?= 0'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-cpio.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_CPIO ?= 0'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-script.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SCRIPT ?= 0'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-syscfg.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SYSCFG ?= 0'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-rsrcdb.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_RSRCDB ?= 0'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-procfs.patch \
    "$ROOT/lq/taskman/Makefile" \
    'RUST_TM_PROCFS_A := $(REPO_ROOT)/build/rust/tm-procfs/libqsoe_tm_procfs.a'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-cred.patch \
    "$ROOT/lq/taskman/Makefile" \
    'RUST_TM_CRED_A := $(REPO_ROOT)/build/rust/tm-cred/libqsoe_tm_cred.a'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-provider-exclusive.patch \
    "$ROOT/lq/taskman/Makefile" \
    'TM_RUST_PROVIDER_COUNT :='
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-pseudodev.patch \
    "$ROOT/lq/taskman/Makefile" \
    'RUST_TM_PSEUDODEV_A := $(REPO_ROOT)/build/rust/tm-pseudodev/libqsoe_tm_pseudodev.a'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-sysfs.patch \
    "$ROOT/lq/taskman/Makefile" \
    'RUST_TM_SYSFS_A := $(REPO_ROOT)/build/rust/tm-sysfs/libqsoe_tm_sysfs.a'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-cpio.patch \
    "$ROOT/lq/taskman/Makefile" \
    'RUST_TM_CPIO_A := $(REPO_ROOT)/build/rust/tm-cpio/libqsoe_tm_cpio.a'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-script.patch \
    "$ROOT/lq/taskman/Makefile" \
    'RUST_TM_SCRIPT_A := $(REPO_ROOT)/build/rust/tm-script/libqsoe_tm_script.a'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-syscfg.patch \
    "$ROOT/lq/taskman/Makefile" \
    'RUST_TM_SYSCFG_A := $(REPO_ROOT)/build/rust/tm-syscfg/libqsoe_tm_syscfg.a'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-rsrcdb.patch \
    "$ROOT/lq/taskman/Makefile" \
    'RUST_TM_RSRCDB_A := $(REPO_ROOT)/build/rust/tm-rsrcdb/libqsoe_tm_rsrcdb.a'
apply_patch_if_possible lq lq-msgpass-mcs-teardown-and-bulk-copy.patch
apply_patch_if_possible quser quser-msgpass-lq-no-reply-skip.patch

require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_CPIO ?= 0'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_PROCFS ?= 0'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_CRED ?= 0'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SCRIPT ?= 0'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SYSCFG ?= 0'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SYSFS ?= 0'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_CPIO_A := $(REPO_ROOT)/build/rust/tm-cpio/libqsoe_tm_cpio.a'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_PROCFS_A := $(REPO_ROOT)/build/rust/tm-procfs/libqsoe_tm_procfs.a'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_CRED_A := $(REPO_ROOT)/build/rust/tm-cred/libqsoe_tm_cred.a'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_SCRIPT_A := $(REPO_ROOT)/build/rust/tm-script/libqsoe_tm_script.a'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_SYSCFG_A := $(REPO_ROOT)/build/rust/tm-syscfg/libqsoe_tm_syscfg.a'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_SYSFS_A := $(REPO_ROOT)/build/rust/tm-sysfs/libqsoe_tm_sysfs.a'
require_line "$ROOT/nq/taskman/Makefile" '$(RUST_TM_CPIO_A): FORCE'
require_line "$ROOT/nq/taskman/Makefile" '$(RUST_TM_PROCFS_A): FORCE'
require_line "$ROOT/nq/taskman/Makefile" '$(RUST_TM_CRED_A): FORCE'
require_line "$ROOT/nq/taskman/Makefile" '$(RUST_TM_SCRIPT_A): FORCE'
require_line "$ROOT/nq/taskman/Makefile" '$(RUST_TM_SYSCFG_A): FORCE'
require_line "$ROOT/nq/taskman/Makefile" '$(RUST_TM_SYSFS_A): FORCE'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_CPIO=$(QSOE_RUST_TM_CPIO)'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED)'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_PROCFS=$(QSOE_RUST_TM_PROCFS)'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SCRIPT=$(QSOE_RUST_TM_SCRIPT)'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SYSCFG=$(QSOE_RUST_TM_SYSCFG)'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SYSFS=$(QSOE_RUST_TM_SYSFS)'
require_adjacent_contains "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_CPIO=$(QSOE_RUST_TM_CPIO)' \
    'QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED)'
require_adjacent_contains "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED)' \
    'QSOE_RUST_TM_PROCFS=$(QSOE_RUST_TM_PROCFS)'
require_adjacent_contains "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_PROCFS=$(QSOE_RUST_TM_PROCFS)' \
    'QSOE_RUST_TM_SCRIPT=$(QSOE_RUST_TM_SCRIPT)'
require_adjacent_contains "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_SCRIPT=$(QSOE_RUST_TM_SCRIPT)' \
    'QSOE_RUST_TM_SYSCFG=$(QSOE_RUST_TM_SYSCFG)'
require_adjacent_contains "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_SYSCFG=$(QSOE_RUST_TM_SYSCFG)' \
    'QSOE_RUST_TM_SYSFS=$(QSOE_RUST_TM_SYSFS)'
require_before_contains "$ROOT/nq/taskman/Makefile" \
    '$(RUST_TM_SYSFS_A): FORCE' \
    'FORCE:'
require_before_contains "$ROOT/nq/taskman/Makefile" \
    '$(RUST_TM_CPIO_A): FORCE' \
    'FORCE:'
require_before_contains "$ROOT/nq/taskman/Makefile" \
    '$(RUST_TM_SCRIPT_A): FORCE' \
    'FORCE:'
require_before_contains "$ROOT/nq/taskman/Makefile" \
    '$(RUST_TM_SYSCFG_A): FORCE' \
    'FORCE:'
require_line "$ROOT/nq/taskman/Makefile" 'select at most one taskman Rust provider until they share one staticlib'
require_line "$ROOT/nq/taskman/Makefile" '$(BUILD)/taskman.elf: $(OBJS) $(LIBTASKMAN_A) $(TASKMAN_RUST_LIBS) taskman.ld'

require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_CPIO ?= 0'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_PROCFS ?= 0'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_CRED ?= 0'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_PSEUDODEV ?= 0'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_RSRCDB ?= 0'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SCRIPT ?= 0'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SYSCFG ?= 0'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SYSFS ?= 0'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_CPIO=$(QSOE_RUST_TM_CPIO)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_PROCFS=$(QSOE_RUST_TM_PROCFS)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_PSEUDODEV=$(QSOE_RUST_TM_PSEUDODEV)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_RSRCDB=$(QSOE_RUST_TM_RSRCDB)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SCRIPT=$(QSOE_RUST_TM_SCRIPT)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SYSCFG=$(QSOE_RUST_TM_SYSCFG)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SYSFS=$(QSOE_RUST_TM_SYSFS)'
require_adjacent_contains "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_CPIO=$(QSOE_RUST_TM_CPIO)' \
    'QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED)'
require_adjacent_contains "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED)' \
    'QSOE_RUST_TM_PROCFS=$(QSOE_RUST_TM_PROCFS)'
require_adjacent_contains "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_PROCFS=$(QSOE_RUST_TM_PROCFS)' \
    'QSOE_RUST_TM_PSEUDODEV=$(QSOE_RUST_TM_PSEUDODEV)'
require_adjacent_contains "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_PSEUDODEV=$(QSOE_RUST_TM_PSEUDODEV)' \
    'QSOE_RUST_TM_RSRCDB=$(QSOE_RUST_TM_RSRCDB)'
require_adjacent_contains "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_RSRCDB=$(QSOE_RUST_TM_RSRCDB)' \
    'QSOE_RUST_TM_SCRIPT=$(QSOE_RUST_TM_SCRIPT)'
require_adjacent_contains "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SCRIPT=$(QSOE_RUST_TM_SCRIPT)' \
    'QSOE_RUST_TM_SYSCFG=$(QSOE_RUST_TM_SYSCFG)'
require_adjacent_contains "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SYSCFG=$(QSOE_RUST_TM_SYSCFG)' \
    'QSOE_RUST_TM_SYSFS=$(QSOE_RUST_TM_SYSFS)'
require_line "$ROOT/lq/Makefile" 'select at most one taskman Rust provider until they share one staticlib'
require_line "$ROOT/lq/Makefile" '$(LIBTASKMAN_A): FORCE'
require_line "$ROOT/lq/Makefile" 'FORCE:'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_CPIO ?= 0'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_PROCFS ?= 0'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_CRED ?= 0'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_PSEUDODEV ?= 0'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_RSRCDB ?= 0'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_SCRIPT ?= 0'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_SYSCFG ?= 0'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_SYSFS ?= 0'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_CPIO_A := $(REPO_ROOT)/build/rust/tm-cpio/libqsoe_tm_cpio.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_PROCFS_A := $(REPO_ROOT)/build/rust/tm-procfs/libqsoe_tm_procfs.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_CRED_A := $(REPO_ROOT)/build/rust/tm-cred/libqsoe_tm_cred.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_PSEUDODEV_A := $(REPO_ROOT)/build/rust/tm-pseudodev/libqsoe_tm_pseudodev.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_RSRCDB_A := $(REPO_ROOT)/build/rust/tm-rsrcdb/libqsoe_tm_rsrcdb.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_SCRIPT_A := $(REPO_ROOT)/build/rust/tm-script/libqsoe_tm_script.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_SYSCFG_A := $(REPO_ROOT)/build/rust/tm-syscfg/libqsoe_tm_syscfg.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_SYSFS_A := $(REPO_ROOT)/build/rust/tm-sysfs/libqsoe_tm_sysfs.a'
require_line "$ROOT/lq/taskman/Makefile" '$(RUST_TM_CPIO_A): FORCE'
require_line "$ROOT/lq/taskman/Makefile" '$(RUST_TM_PROCFS_A): FORCE'
require_line "$ROOT/lq/taskman/Makefile" '$(RUST_TM_CRED_A): FORCE'
require_line "$ROOT/lq/taskman/Makefile" '$(RUST_TM_PSEUDODEV_A): FORCE'
require_line "$ROOT/lq/taskman/Makefile" '$(RUST_TM_RSRCDB_A): FORCE'
require_line "$ROOT/lq/taskman/Makefile" '$(RUST_TM_SCRIPT_A): FORCE'
require_line "$ROOT/lq/taskman/Makefile" '$(RUST_TM_SYSCFG_A): FORCE'
require_line "$ROOT/lq/taskman/Makefile" '$(RUST_TM_SYSFS_A): FORCE'
require_line "$ROOT/lq/taskman/Makefile" 'TASKMAN_PSEUDODEV_OBJS += $(OBJDIR)/sys/devnull.o'
require_line "$ROOT/lq/taskman/Makefile" 'TASKMAN_PSEUDODEV_OBJS += $(OBJDIR)/sys/devzero.o'
require_line "$ROOT/lq/taskman/Makefile" '$(TASKMAN_PSEUDODEV_OBJS)'
require_line "$ROOT/lq/taskman/Makefile" 'TASKMAN_RSRCDB_OBJS += $(OBJDIR)/sys/rsrcdb.o'
require_line "$ROOT/lq/taskman/Makefile" '$(TASKMAN_RSRCDB_OBJS)'
require_line "$ROOT/lq/taskman/Makefile" 'select at most one taskman Rust provider until they share one staticlib'
require_line "$ROOT/lq/taskman/Makefile" 'FORCE:'
require_before_contains "$ROOT/lq/taskman/Makefile" \
    '$(RUST_TM_CPIO_A): FORCE' \
    '$(TASKMAN_ELF): $(TASKMAN_OBJS) $(LIBTASKMAN_A) $(TASKMAN_RUST_LIBS)'
require_before_contains "$ROOT/lq/taskman/Makefile" \
    '$(RUST_TM_CRED_A): FORCE' \
    '$(TASKMAN_ELF): $(TASKMAN_OBJS) $(LIBTASKMAN_A) $(TASKMAN_RUST_LIBS)'
require_before_contains "$ROOT/lq/taskman/Makefile" \
    '$(RUST_TM_PSEUDODEV_A): FORCE' \
    '$(TASKMAN_ELF): $(TASKMAN_OBJS) $(LIBTASKMAN_A) $(TASKMAN_RUST_LIBS)'
require_before_contains "$ROOT/lq/taskman/Makefile" \
    '$(RUST_TM_RSRCDB_A): FORCE' \
    '$(TASKMAN_ELF): $(TASKMAN_OBJS) $(LIBTASKMAN_A) $(TASKMAN_RUST_LIBS)'
require_before_contains "$ROOT/lq/taskman/Makefile" \
    '$(RUST_TM_SCRIPT_A): FORCE' \
    '$(TASKMAN_ELF): $(TASKMAN_OBJS) $(LIBTASKMAN_A) $(TASKMAN_RUST_LIBS)'
require_before_contains "$ROOT/lq/taskman/Makefile" \
    '$(RUST_TM_SYSCFG_A): FORCE' \
    '$(TASKMAN_ELF): $(TASKMAN_OBJS) $(LIBTASKMAN_A) $(TASKMAN_RUST_LIBS)'
require_before_contains "$ROOT/lq/taskman/Makefile" \
    '$(RUST_TM_SYSFS_A): FORCE' \
    '$(TASKMAN_ELF): $(TASKMAN_OBJS) $(LIBTASKMAN_A) $(TASKMAN_RUST_LIBS)'
require_line "$ROOT/lq/taskman/Makefile" '$(TASKMAN_ELF): $(TASKMAN_OBJS) $(LIBTASKMAN_A) $(TASKMAN_RUST_LIBS)'
require_line "$ROOT/lq/libc/qsoe/msg.c" 'if (label == QSOE_MSG_BULK_LABEL) {'
require_line "$ROOT/lq/taskman/proc/process.c" 'tm_pathmgr_unregister_pid(target);'
require_line "$ROOT/lq/taskman/proc/spawn.c" 'tm_process_resolve_frame(src_proc, sva'
require_line "$ROOT/quser/test/suite/msgpass_test.c" '(void) ProcessTerminate(nr_pid, 0);'

echo "apply-component-overrides.sh: component overrides ready"
