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
    if grep -Fq -- "$marker" "$marker_file"; then
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

    grep -Fq -- "$needle" "$file" ||
        fail "$file is missing expected override: $needle"
}

require_absent() {
    local file=$1
    local needle=$2

    ! grep -Fq -- "$needle" "$file" ||
        fail "$file still contains retired override text: $needle"
}

require_missing() {
    local path=$1

    [ ! -e "$path" ] ||
        fail "$path should have been removed by component overrides"
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
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-elf.patch \
    "$ROOT/nq/taskman/Makefile" \
    'RUST_TM_ELF_A := $(REPO_ROOT)/build/rust/tm-elf/libqsoe_tm_elf.a'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-pathmgr.patch \
    "$ROOT/nq/taskman/Makefile" \
    'RUST_TM_PATHMGR_A := $(REPO_ROOT)/build/rust/tm-pathmgr/libqsoe_tm_pathmgr.a'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-shared-providers.patch \
    "$ROOT/nq/taskman/Makefile" \
    'RUST_TM_PROVIDERS_A := $(REPO_ROOT)/build/rust/tm-providers/libqsoe_tm_providers.a'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-procfs-retired.patch \
    "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_PROCFS must be 1 after C tm_procfs retirement'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-cpio-retired.patch \
    "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_CPIO must be 1 after C tm_cpio retirement'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-elf-retired.patch \
    "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_ELF must be 1 after C tm_elf retirement'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-script-retired.patch \
    "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_SCRIPT must be 1 after C tm_script retirement'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-syscfg-retired.patch \
    "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_SYSCFG must be 1 after C tm_syscfg retirement'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-sysfs-retired.patch \
    "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_SYSFS must be 1 after C tm_sysfs retirement'
apply_patch_if_possible_or_present nq nq-makefile-rust-slogger-retired.patch \
    "$ROOT/nq/Makefile" \
    'SELECTED_SLOGGER_ELF ?= $(abspath ../build/rust/selected/sbin/slogger.elf)'
apply_patch_if_possible_or_present nq nq-makefile-rust-pipe-retired.patch \
    "$ROOT/nq/Makefile" \
    'SELECTED_PIPE_ELF ?= $(abspath ../build/rust/selected/sbin/pipe.elf)'
apply_patch_if_possible_or_present nq nq-makefile-rust-virtio-retired.patch \
    "$ROOT/nq/Makefile" \
    'SELECTED_VIRTIO_ELF ?= $(abspath ../build/rust/selected/sbin/devb-virtio.elf)'
apply_patch_if_possible_or_present nq nq-kernel-common-cpio.patch \
    "$ROOT/nq/Makefile" \
    '$(LIBTASKMAN_CPIO_O): ../common/cpio.c'
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
    'QSOE_RUST_TM_SYSFS=$(QSOE_RUST_TM_SYSFS)'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-cpio.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_CPIO=$(QSOE_RUST_TM_CPIO)'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-script.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SCRIPT=$(QSOE_RUST_TM_SCRIPT)'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-syscfg.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SYSCFG=$(QSOE_RUST_TM_SYSCFG)'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-rsrcdb.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_RSRCDB ?= 0'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-elf.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_ELF=$(QSOE_RUST_TM_ELF)'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-fdt.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_FDT=$(QSOE_RUST_TM_FDT)'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-sysmap.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SYSMAP=$(QSOE_RUST_TM_SYSMAP)'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-pathmgr.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_PATHMGR ?= 0'
apply_optional_patch lq lq-makefile-rust-tm-shared-providers.patch
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-procfs-retired.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_PROCFS must be 1 after C tm_procfs retirement'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-cpio-retired.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_CPIO must be 1 after C tm_cpio retirement'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-elf-retired.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_ELF must be 1 after C tm_elf retirement'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-script-retired.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SCRIPT must be 1 after C tm_script retirement'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-syscfg-retired.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SYSCFG must be 1 after C tm_syscfg retirement'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-sysmap-retired.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SYSMAP must be 1 after C tm_sysmap retirement'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-sysfs-retired.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SYSFS must be 1 after C tm_sysfs retirement'
apply_patch_if_possible_or_present lq lq-makefile-rust-slogger-retired.patch \
    "$ROOT/lq/Makefile" \
    'SELECTED_SLOGGER_ELF ?= $(abspath $(TOP)/..)/build/rust/selected/sbin/slogger.elf'
apply_patch_if_possible_or_present lq lq-makefile-rust-pipe-retired.patch \
    "$ROOT/lq/Makefile" \
    'SELECTED_PIPE_ELF ?= $(abspath $(TOP)/..)/build/rust/selected/sbin/pipe.elf'
apply_patch_if_possible_or_present lq lq-makefile-rust-virtio-retired.patch \
    "$ROOT/lq/Makefile" \
    'SELECTED_VIRTIO_ELF ?= $(abspath $(TOP)/..)/build/rust/selected/sbin/devb-virtio.elf'
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
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-elf.patch \
    "$ROOT/lq/taskman/Makefile" \
    'RUST_TM_ELF_A := $(REPO_ROOT)/build/rust/tm-elf/libqsoe_tm_elf.a'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-fdt.patch \
    "$ROOT/lq/taskman/Makefile" \
    'RUST_TM_FDT_A := $(REPO_ROOT)/build/rust/tm-fdt/libqsoe_tm_fdt.a'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-sysmap.patch \
    "$ROOT/lq/taskman/Makefile" \
    'RUST_TM_SYSMAP_A := $(REPO_ROOT)/build/rust/tm-sysmap/libqsoe_tm_sysmap.a'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-pathmgr.patch \
    "$ROOT/lq/taskman/Makefile" \
    'RUST_TM_PATHMGR_A := $(REPO_ROOT)/build/rust/tm-pathmgr/libqsoe_tm_pathmgr.a'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-shared-providers.patch \
    "$ROOT/lq/taskman/Makefile" \
    'RUST_TM_PROVIDERS_A := $(REPO_ROOT)/build/rust/tm-providers/libqsoe_tm_providers.a'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-procfs-retired.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_PROCFS must be 1 after C tm_procfs retirement'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-cpio-retired.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_CPIO must be 1 after C tm_cpio retirement'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-elf-retired.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_ELF must be 1 after C tm_elf retirement'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-script-retired.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_SCRIPT must be 1 after C tm_script retirement'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-syscfg-retired.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_SYSCFG must be 1 after C tm_syscfg retirement'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-sysmap-retired.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_SYSMAP must be 1 after C tm_sysmap retirement'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-sysfs-retired.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_SYSFS must be 1 after C tm_sysfs retirement'
apply_patch_if_possible_or_present lq lq-taskman-stack-32k.patch \
    "$ROOT/lq/taskman/start.S" \
    '    .skip 32768'
apply_patch_if_possible lq lq-msgpass-mcs-teardown-and-bulk-copy.patch
apply_patch_if_possible_or_present quser quser-retire-test-msgpass-c.patch \
    "$ROOT/quser/Makefile" \
    'test_msgpass-rs'
apply_patch_if_possible_or_present quser quser-retire-slogger-c.patch \
    "$ROOT/quser/Makefile" \
    'sbin/slogger C daemon is retired'
apply_patch_if_possible_or_present quser quser-retire-pipe-c.patch \
    "$ROOT/quser/Makefile" \
    'sbin/pipe C service is retired'
apply_patch_if_possible_or_present quser quser-retire-virtio-c.patch \
    "$ROOT/quser/Makefile" \
    'dev/virtio C block driver is retired'
apply_patch_if_possible_or_present quser quser-pathmgr-probe.patch \
    "$ROOT/quser/Makefile" \
    'test/pathmgr_probe'
apply_patch_if_possible_or_present quser quser-cred-probe.patch \
    "$ROOT/quser/Makefile" \
    'test/cred_probe'
apply_patch_if_possible_or_present quser quser-rsrcdb-probe.patch \
    "$ROOT/quser/Makefile" \
    'test/rsrcdb_probe'
apply_patch_if_possible_or_present quser quser-pseudodev-probe.patch \
    "$ROOT/quser/Makefile" \
    'test/pseudodev_probe'
apply_patch_if_possible quser quser-msgpass-lq-no-reply-skip.patch
apply_patch_if_possible quser quser-sync-unowned-unlock-public-abi.patch

apply_patch_if_possible_or_present nq nq-taskman-rust-tm-cpio-rc-default.patch \
    "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_CPIO ?= 1'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-cpio-rc-default.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_CPIO ?= 1'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-cpio-rc-default.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_CPIO ?= 1'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-script-rc-default.patch \
    "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_SCRIPT ?= 1'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-script-rc-default.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SCRIPT ?= 1'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-script-rc-default.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_SCRIPT ?= 1'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-sysfs-rc-default.patch \
    "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_SYSFS ?= 1'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-sysfs-rc-default.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SYSFS ?= 1'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-sysfs-rc-default.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_SYSFS ?= 1'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-syscfg-rc-default.patch \
    "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_SYSCFG ?= 1'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-syscfg-rc-default.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SYSCFG ?= 1'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-syscfg-rc-default.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_SYSCFG ?= 1'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-sysmap-rc-default.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SYSMAP ?= 1'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-sysmap-rc-default.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_SYSMAP ?= 1'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-elf-rc-default.patch \
    "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_ELF ?= 1'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-elf-rc-default.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_ELF ?= 1'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-elf-rc-default.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_ELF ?= 1'
apply_patch_if_possible_or_present nq nq-taskman-rust-tm-cred-rc-default.patch \
    "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_CRED ?= 1'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-cred-rc-default.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_CRED ?= 1'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-cred-rc-default.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_CRED ?= 1'
apply_patch_if_possible_or_present lq lq-makefile-rust-tm-fdt-rc-default.patch \
    "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_FDT ?= 1'
apply_patch_if_possible_or_present lq lq-taskman-rust-tm-fdt-rc-default.patch \
    "$ROOT/lq/taskman/Makefile" \
    'QSOE_RUST_TM_FDT ?= 1'

require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_CPIO ?= 1'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_CPIO must be 1 after C tm_cpio retirement'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_PROCFS ?= 1'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_PROCFS must be 1 after C tm_procfs retirement'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_ELF must be 1 after C tm_elf retirement'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SCRIPT must be 1 after C tm_script retirement'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SYSCFG must be 1 after C tm_syscfg retirement'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SYSFS must be 1 after C tm_sysfs retirement'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_CRED ?= 1'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_ELF ?= 1'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_PATHMGR ?= 0'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SCRIPT ?= 1'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SYSCFG ?= 1'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SYSFS ?= 1'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_CPIO_A := $(REPO_ROOT)/build/rust/tm-cpio/libqsoe_tm_cpio.a'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_PROCFS_A := $(REPO_ROOT)/build/rust/tm-procfs/libqsoe_tm_procfs.a'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_CRED_A := $(REPO_ROOT)/build/rust/tm-cred/libqsoe_tm_cred.a'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_ELF_A := $(REPO_ROOT)/build/rust/tm-elf/libqsoe_tm_elf.a'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_PATHMGR_A := $(REPO_ROOT)/build/rust/tm-pathmgr/libqsoe_tm_pathmgr.a'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_SCRIPT_A := $(REPO_ROOT)/build/rust/tm-script/libqsoe_tm_script.a'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_SYSCFG_A := $(REPO_ROOT)/build/rust/tm-syscfg/libqsoe_tm_syscfg.a'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_SYSFS_A := $(REPO_ROOT)/build/rust/tm-sysfs/libqsoe_tm_sysfs.a'
require_line "$ROOT/nq/taskman/Makefile" 'RUST_TM_PROVIDERS_A := $(REPO_ROOT)/build/rust/tm-providers/libqsoe_tm_providers.a'
require_line "$ROOT/nq/taskman/Makefile" 'TASKMAN_RUST_LIBS += $(RUST_TM_PROVIDERS_A)'
require_line "$ROOT/nq/taskman/Makefile" '$(RUST_TM_PROVIDERS_A): FORCE'
require_line "$ROOT/nq/taskman/Makefile" '$(REPO_ROOT)/scripts/build-rust-tm-providers.sh $@'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_CPIO=$(QSOE_RUST_TM_CPIO)'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED)'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_ELF=$(QSOE_RUST_TM_ELF)'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_PATHMGR=$(QSOE_RUST_TM_PATHMGR)'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_PROCFS=$(QSOE_RUST_TM_PROCFS)'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SCRIPT=$(QSOE_RUST_TM_SCRIPT)'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SYSCFG=$(QSOE_RUST_TM_SYSCFG)'
require_line "$ROOT/nq/taskman/Makefile" 'QSOE_RUST_TM_SYSFS=$(QSOE_RUST_TM_SYSFS)'
require_adjacent_contains "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_CPIO=$(QSOE_RUST_TM_CPIO)' \
    'QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED)'
require_adjacent_contains "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED)' \
    'QSOE_RUST_TM_ELF=$(QSOE_RUST_TM_ELF)'
require_adjacent_contains "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_ELF=$(QSOE_RUST_TM_ELF)' \
    'QSOE_RUST_TM_PATHMGR=$(QSOE_RUST_TM_PATHMGR)'
require_adjacent_contains "$ROOT/nq/taskman/Makefile" \
    'QSOE_RUST_TM_PATHMGR=$(QSOE_RUST_TM_PATHMGR)' \
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
    '$(RUST_TM_PROVIDERS_A): FORCE' \
    'FORCE:'
require_absent "$ROOT/nq/taskman/Makefile" 'select at most one taskman Rust provider until they share one staticlib'
require_line "$ROOT/nq/taskman/Makefile" '$(BUILD)/taskman.elf: $(OBJS) $(LIBTASKMAN_A) $(TASKMAN_RUST_LIBS) taskman.ld'
require_line "$ROOT/nq/Makefile" 'SELECTED_SLOGGER_ELF ?= $(abspath ../build/rust/selected/sbin/slogger.elf)'
require_line "$ROOT/nq/Makefile" 'SELECTED_PIPE_ELF ?= $(abspath ../build/rust/selected/sbin/pipe.elf)'
require_line "$ROOT/nq/Makefile" 'SELECTED_VIRTIO_ELF ?= $(abspath ../build/rust/selected/sbin/devb-virtio.elf)'
require_line "$ROOT/nq/Makefile" '$(MAKE) -C .. slogger-artifact'
require_line "$ROOT/nq/Makefile" '$(MAKE) -C .. pipe-artifact'
require_line "$ROOT/nq/Makefile" '$(MAKE) -C .. virtio-artifact'
require_line "$ROOT/nq/Makefile" 'SBIN_SLOG_ELF=$(SELECTED_SLOGGER_ELF)'
require_line "$ROOT/nq/Makefile" 'SBIN_PIPE_ELF=$(SELECTED_PIPE_ELF)'
require_line "$ROOT/nq/Makefile" 'SBIN_VIRTIO_ELF=$(SELECTED_VIRTIO_ELF)'
require_line "$ROOT/nq/Makefile" '-I../common \'
require_line "$ROOT/nq/Makefile" '$(LIBTASKMAN_CPIO_O): ../common/cpio.c'
require_absent "$ROOT/nq/Makefile" '../libtaskman/src/cpio.c'
require_line "$ROOT/nq/kernel/main.c" '#include <cpio.h>'
require_line "$ROOT/nq/kernel/main.c" 'const void *taskman_data = cpio_get_file(cpio_data, cpio_size,'

require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_CPIO ?= 1'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_CPIO must be 1 after C tm_cpio retirement'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_PROCFS ?= 1'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_PROCFS must be 1 after C tm_procfs retirement'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_ELF must be 1 after C tm_elf retirement'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SCRIPT must be 1 after C tm_script retirement'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SYSCFG must be 1 after C tm_syscfg retirement'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SYSMAP must be 1 after C tm_sysmap retirement'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SYSFS must be 1 after C tm_sysfs retirement'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_CRED ?= 1'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_ELF ?= 1'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_FDT ?= 1'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_PATHMGR ?= 0'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_PSEUDODEV ?= 0'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_RSRCDB ?= 0'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SCRIPT ?= 1'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SYSCFG ?= 1'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SYSMAP ?= 1'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SYSFS ?= 1'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_CPIO=$(QSOE_RUST_TM_CPIO)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_ELF=$(QSOE_RUST_TM_ELF)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_FDT=$(QSOE_RUST_TM_FDT)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_PATHMGR=$(QSOE_RUST_TM_PATHMGR)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_PROCFS=$(QSOE_RUST_TM_PROCFS)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_PSEUDODEV=$(QSOE_RUST_TM_PSEUDODEV)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_RSRCDB=$(QSOE_RUST_TM_RSRCDB)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SCRIPT=$(QSOE_RUST_TM_SCRIPT)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SYSCFG=$(QSOE_RUST_TM_SYSCFG)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SYSMAP=$(QSOE_RUST_TM_SYSMAP)'
require_line "$ROOT/lq/Makefile" 'QSOE_RUST_TM_SYSFS=$(QSOE_RUST_TM_SYSFS)'
require_line "$ROOT/lq/Makefile" 'SELECTED_SLOGGER_ELF ?= $(abspath $(TOP)/..)/build/rust/selected/sbin/slogger.elf'
require_line "$ROOT/lq/Makefile" 'SELECTED_PIPE_ELF ?= $(abspath $(TOP)/..)/build/rust/selected/sbin/pipe.elf'
require_line "$ROOT/lq/Makefile" 'SELECTED_VIRTIO_ELF ?= $(abspath $(TOP)/..)/build/rust/selected/sbin/devb-virtio.elf'
require_line "$ROOT/lq/Makefile" '$(MAKE) -C $(abspath $(TOP)/..) slogger-artifact'
require_line "$ROOT/lq/Makefile" '$(MAKE) -C $(abspath $(TOP)/..) pipe-artifact'
require_line "$ROOT/lq/Makefile" '$(MAKE) -C $(abspath $(TOP)/..) virtio-artifact'
require_line "$ROOT/lq/Makefile" 'SBIN_SLOG_ELF=$(SELECTED_SLOGGER_ELF)'
require_line "$ROOT/lq/Makefile" 'SBIN_PIPE_ELF=$(SELECTED_PIPE_ELF)'
require_line "$ROOT/lq/Makefile" 'SBIN_VIRTIO_ELF=$(SELECTED_VIRTIO_ELF)'
require_adjacent_contains "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_CPIO=$(QSOE_RUST_TM_CPIO)' \
    'QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED)'
require_adjacent_contains "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED)' \
    'QSOE_RUST_TM_ELF=$(QSOE_RUST_TM_ELF)'
require_adjacent_contains "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_ELF=$(QSOE_RUST_TM_ELF)' \
    'QSOE_RUST_TM_FDT=$(QSOE_RUST_TM_FDT)'
require_adjacent_contains "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_FDT=$(QSOE_RUST_TM_FDT)' \
    'QSOE_RUST_TM_PATHMGR=$(QSOE_RUST_TM_PATHMGR)'
require_adjacent_contains "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_PATHMGR=$(QSOE_RUST_TM_PATHMGR)' \
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
    'QSOE_RUST_TM_SYSMAP=$(QSOE_RUST_TM_SYSMAP)'
require_adjacent_contains "$ROOT/lq/Makefile" \
    'QSOE_RUST_TM_SYSMAP=$(QSOE_RUST_TM_SYSMAP)' \
    'QSOE_RUST_TM_SYSFS=$(QSOE_RUST_TM_SYSFS)'
require_absent "$ROOT/lq/Makefile" 'select at most one taskman Rust provider until they share one staticlib'
require_line "$ROOT/lq/Makefile" '$(LIBTASKMAN_A): FORCE'
require_line "$ROOT/lq/Makefile" 'FORCE:'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_CPIO ?= 1'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_CPIO must be 1 after C tm_cpio retirement'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_PROCFS ?= 1'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_PROCFS must be 1 after C tm_procfs retirement'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_ELF must be 1 after C tm_elf retirement'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_SCRIPT must be 1 after C tm_script retirement'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_SYSCFG must be 1 after C tm_syscfg retirement'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_SYSMAP must be 1 after C tm_sysmap retirement'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_SYSFS must be 1 after C tm_sysfs retirement'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_CRED ?= 1'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_ELF ?= 1'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_FDT ?= 1'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_PATHMGR ?= 0'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_PSEUDODEV ?= 0'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_RSRCDB ?= 0'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_SCRIPT ?= 1'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_SYSCFG ?= 1'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_SYSMAP ?= 1'
require_line "$ROOT/lq/taskman/Makefile" 'QSOE_RUST_TM_SYSFS ?= 1'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_CPIO_A := $(REPO_ROOT)/build/rust/tm-cpio/libqsoe_tm_cpio.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_PROCFS_A := $(REPO_ROOT)/build/rust/tm-procfs/libqsoe_tm_procfs.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_CRED_A := $(REPO_ROOT)/build/rust/tm-cred/libqsoe_tm_cred.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_ELF_A := $(REPO_ROOT)/build/rust/tm-elf/libqsoe_tm_elf.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_FDT_A := $(REPO_ROOT)/build/rust/tm-fdt/libqsoe_tm_fdt.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_PATHMGR_A := $(REPO_ROOT)/build/rust/tm-pathmgr/libqsoe_tm_pathmgr.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_PSEUDODEV_A := $(REPO_ROOT)/build/rust/tm-pseudodev/libqsoe_tm_pseudodev.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_RSRCDB_A := $(REPO_ROOT)/build/rust/tm-rsrcdb/libqsoe_tm_rsrcdb.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_SCRIPT_A := $(REPO_ROOT)/build/rust/tm-script/libqsoe_tm_script.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_SYSCFG_A := $(REPO_ROOT)/build/rust/tm-syscfg/libqsoe_tm_syscfg.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_SYSMAP_A := $(REPO_ROOT)/build/rust/tm-sysmap/libqsoe_tm_sysmap.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_SYSFS_A := $(REPO_ROOT)/build/rust/tm-sysfs/libqsoe_tm_sysfs.a'
require_line "$ROOT/lq/taskman/Makefile" 'RUST_TM_PROVIDERS_A := $(REPO_ROOT)/build/rust/tm-providers/libqsoe_tm_providers.a'
require_line "$ROOT/lq/taskman/Makefile" 'TASKMAN_RUST_LIBS += $(RUST_TM_PROVIDERS_A)'
require_line "$ROOT/lq/taskman/Makefile" '$(RUST_TM_PROVIDERS_A): FORCE'
require_line "$ROOT/lq/taskman/Makefile" '$(REPO_ROOT)/scripts/build-rust-tm-providers.sh $@'
require_line "$ROOT/lq/taskman/start.S" '    .skip 32768'
require_line "$ROOT/lq/taskman/Makefile" 'TASKMAN_PSEUDODEV_OBJS += $(OBJDIR)/sys/devnull.o'
require_line "$ROOT/lq/taskman/Makefile" 'TASKMAN_PSEUDODEV_OBJS += $(OBJDIR)/sys/devzero.o'
require_line "$ROOT/lq/taskman/Makefile" '$(TASKMAN_PSEUDODEV_OBJS)'
require_line "$ROOT/lq/taskman/Makefile" 'TASKMAN_RSRCDB_OBJS += $(OBJDIR)/sys/rsrcdb.o'
require_line "$ROOT/lq/taskman/Makefile" '$(TASKMAN_RSRCDB_OBJS)'
require_line "$ROOT/lq/taskman/Makefile" 'TASKMAN_FDT_OBJS += $(OBJDIR)/sys/fdt.o'
require_line "$ROOT/lq/taskman/Makefile" '$(TASKMAN_FDT_OBJS)'
require_absent "$ROOT/lq/taskman/Makefile" 'TASKMAN_SYSMAP_OBJS += $(OBJDIR)/sys/sysmap.o'
require_line "$ROOT/lq/taskman/Makefile" '$(TASKMAN_SYSMAP_OBJS)'
if [ -e "$ROOT/lq/taskman/sys/sysmap.c" ]; then
    fail "lq/taskman/sys/sysmap.c should be retired"
fi
require_line "$ROOT/libtaskman/Makefile" 'QSOE_RUST_TM_SYSFS must be 1 after C tm_sysfs retirement'
if [ -e "$ROOT/libtaskman/src/tm_sysfs.c" ]; then
    fail "libtaskman/src/tm_sysfs.c should be retired"
fi
require_absent "$ROOT/lq/taskman/Makefile" 'select at most one taskman Rust provider until they share one staticlib'
require_line "$ROOT/lq/taskman/Makefile" 'FORCE:'
require_before_contains "$ROOT/lq/taskman/Makefile" \
    '$(RUST_TM_PROVIDERS_A): FORCE' \
    '$(TASKMAN_ELF): $(TASKMAN_OBJS) $(LIBTASKMAN_A) $(TASKMAN_RUST_LIBS)'
require_line "$ROOT/lq/taskman/Makefile" '$(TASKMAN_ELF): $(TASKMAN_OBJS) $(LIBTASKMAN_A) $(TASKMAN_RUST_LIBS)'
require_line "$ROOT/lq/libc/qsoe/msg.c" 'if (label == QSOE_MSG_BULK_LABEL) {'
require_line "$ROOT/lq/taskman/proc/process.c" 'tm_pathmgr_unregister_pid(target);'
require_line "$ROOT/lq/taskman/proc/spawn.c" 'tm_process_resolve_frame(src_proc, sva'
require_line "$ROOT/quser/Makefile" 'test_msgpass-rs'
require_absent "$ROOT/quser/Makefile" '              test/msgpass \'
require_missing "$ROOT/quser/test/msgpass/Makefile"
require_missing "$ROOT/quser/test/msgpass/main.c"
require_line "$ROOT/quser/Makefile" 'sbin/slogger C daemon is retired'
require_line "$ROOT/quser/Makefile" 'SBIN_SLOG_ELF  ?= $(abspath $(QUSER)/../build/rust/selected/sbin/slogger.elf)'
require_absent "$ROOT/quser/Makefile" '              sbin/slogger \'
require_missing "$ROOT/quser/sbin/slogger/Makefile"
require_missing "$ROOT/quser/sbin/slogger/main.c"
require_line "$ROOT/quser/Makefile" 'sbin/pipe C service is retired'
require_line "$ROOT/quser/Makefile" 'SBIN_PIPE_ELF ?= $(abspath $(QUSER)/../build/rust/selected/sbin/pipe.elf)'
require_absent "$ROOT/quser/Makefile" '              sbin/pipe \'
require_missing "$ROOT/quser/sbin/pipe/Makefile"
require_missing "$ROOT/quser/sbin/pipe/main.c"
require_line "$ROOT/quser/Makefile" 'dev/virtio C block driver is retired'
require_line "$ROOT/quser/Makefile" 'SBIN_VIRTIO_ELF ?= $(abspath $(QUSER)/../build/rust/selected/sbin/devb-virtio.elf)'
require_line "$ROOT/quser/Makefile" '@cp $(SBIN_VIRTIO_ELF)            $(CPIO_ROOT)/sbin/devb-virtio'
require_absent "$ROOT/quser/Makefile" '              dev/virtio \'
require_missing "$ROOT/quser/dev/virtio/Makefile"
require_missing "$ROOT/quser/dev/virtio/main.c"
require_missing "$ROOT/quser/dev/virtio/virtio_blk.c"
require_missing "$ROOT/quser/dev/virtio/virtio_blk.h"
require_line "$ROOT/quser/Makefile" '              test/pathmgr_probe \'
require_line "$ROOT/quser/test/pathmgr_probe/Makefile" 'PROGRAM := pathmgr_probe'
require_line "$ROOT/quser/test/pathmgr_probe/main.c" 'PATHMGR_PROBE_PATH'
require_line "$ROOT/quser/Makefile" '              test/cred_probe \'
require_line "$ROOT/quser/test/cred_probe/Makefile" 'PROGRAM := cred_probe'
require_line "$ROOT/quser/test/cred_probe/main.c" 'tm-cred-runtime-smoke: credential probe ok'
require_line "$ROOT/quser/Makefile" '              test/rsrcdb_probe \'
require_line "$ROOT/quser/test/rsrcdb_probe/Makefile" 'PROGRAM := rsrcdb_probe'
require_line "$ROOT/quser/test/rsrcdb_probe/main.c" 'tm-rsrcdb-runtime-smoke: rsrcdb probe ok'
require_line "$ROOT/quser/Makefile" '              test/pseudodev_probe \'
require_line "$ROOT/quser/test/pseudodev_probe/Makefile" 'PROGRAM := pseudodev_probe'
require_line "$ROOT/quser/test/pseudodev_probe/main.c" 'tm-pseudodev-runtime-smoke: pseudodev probe ok'
require_line "$ROOT/quser/test/suite/msgpass_test.c" '(void) ProcessTerminate(nr_pid, 0);'
require_line "$ROOT/quser/test/suite/sync.c" 'rc_unlock == EOK || (rc_unlock == -1 && errno == EPERM)'

echo "apply-component-overrides.sh: component overrides ready"
