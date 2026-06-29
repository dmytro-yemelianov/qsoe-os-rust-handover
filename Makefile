# Makefile -- top-level QSOE umbrella build orchestrator.
#
# Goals:
#   all        build both OS variants (nq, then lq); each component
#              owns its build, this file only descends.
#   prepare    obtain the components matching this tree's release tag
#              (delegated to proj_obtain.sh, see component.list).
#   nvme       build the QEMU NVMe test image (a GPT skeleton).  This is
#              host-side tooling shared by BOTH variants -- the disk runs
#              under QEMU on either kernel -- so the image and its builder
#              (host_tools/mkgpt.py) live here at the umbrella, not in a
#              variant.  The variants' emu.sh delegate to this target; they
#              never lay the image themselves.  (The board uses a real disk.)
#
# Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
# SPDX-License-Identifier: Apache-2.0

QSOE_RUST_SLOGGER ?= 1
QSOE_RUST_VIRTIO ?= 1
QSOE_RUST_TEST_MSGPASS ?= 1
QSOE_RUST_PIPE ?= 1
QSOE_RUST_TM_CPIO ?= 0
QSOE_RUST_TM_CRED ?= 0
QSOE_RUST_TM_ELF ?= 0
QSOE_RUST_TM_FDT ?= 0
QSOE_RUST_TM_PATHMGR ?= 0
QSOE_RUST_TM_PROCFS ?= 1
QSOE_RUST_TM_PSEUDODEV ?= 0
QSOE_RUST_TM_RSRCDB ?= 0
QSOE_RUST_TM_SCRIPT ?= 0
QSOE_RUST_TM_SYSCFG ?= 0
QSOE_RUST_TM_SYSMAP ?= 0
QSOE_RUST_TM_SYSFS ?= 0
QSOE_RUST_TREEQRVFS ?= 1
QSOE_RUST_MKFS_QRV ?= 0

TM_RUST_PROVIDER_COUNT := $(words $(filter 1,$(QSOE_RUST_TM_CPIO) $(QSOE_RUST_TM_CRED) $(QSOE_RUST_TM_ELF) $(QSOE_RUST_TM_FDT) $(QSOE_RUST_TM_PATHMGR) $(QSOE_RUST_TM_PROCFS) $(QSOE_RUST_TM_PSEUDODEV) $(QSOE_RUST_TM_RSRCDB) $(QSOE_RUST_TM_SCRIPT) $(QSOE_RUST_TM_SYSCFG) $(QSOE_RUST_TM_SYSMAP) $(QSOE_RUST_TM_SYSFS)))
ifneq ($(QSOE_RUST_TM_PROCFS),1)
$(error QSOE_RUST_TM_PROCFS must be 1 after C tm_procfs retirement)
endif

SELECTED_SLOGGER_ELF ?= build/rust/selected/sbin/slogger.elf
SELECTED_VIRTIO_ELF ?= build/rust/selected/sbin/devb-virtio.elf
SELECTED_TEST_MSGPASS_ELF ?= build/rust/selected/usr/bin/test_msgpass.elf
SELECTED_PIPE_ELF ?= build/rust/selected/sbin/pipe.elf

.PHONY: all prepare component-overrides clean nvme nvme-populate virtio fsqrv-image tree \
        treeqrvfs-artifact treeqrvfs-rc-smoke treeqrvfs-rc-rollback-smoke \
        rust-mkfs-qrv-artifact rust-mkfs-qrv-live-smoke \
        mkfs-qrv-rc-live-smoke mkfs-qrv-rc-rollback-smoke \
        check-host-tools check-qrvfs-fixture check-qrvfs-rust-fixture \
        check-qrvfs-rust-writer-fixture \
        check-qrvfs-rust-writer-production-root \
        check-elf-reloc-fixture check-gpt-fixture \
        check-tm-cpio-model check-tm-cred-model check-tm-elf-model check-tm-fdt-model check-tm-pathmgr-model check-tm-procfs-model check-tm-rsrcdb-model \
        check-tm-script-model check-tm-syscfg-model check-tm-sysmap-model check-tm-sysfs-model \
        slog-readback-smoke \
        rust-slog-readback-smoke slogger-rc-boot-smoke \
        slogger-rc-readback-smoke \
        index-c index-c-files index-c-tags index-c-cscope index-c-global \
        index-c-static index-c-compile-db tidy-c \
        elf-baseline audit-artifacts \
        rust-fast rust-quality rust-check rust-abi rust-deep rust-fuzz-smoke \
        rust-coverage \
        rust-qsoe-link-smoke rust-slogger-link-smoke \
        rust-service-example-link-smoke rust-virtio-link-smoke \
        rust-test-msgpass-link-smoke rust-pipe-link-smoke \
        slogger-artifact virtio-artifact test-msgpass-artifact pipe-artifact \
        rust-tm-cpio-provider rust-tm-cred-provider rust-tm-elf-provider rust-tm-fdt-provider rust-tm-pathmgr-provider rust-tm-procfs-provider \
        rust-tm-rsrcdb-provider rust-tm-script-provider rust-tm-syscfg-provider rust-tm-sysmap-provider rust-tm-sysfs-provider \
        rust-tm-pseudodev-provider rust-tm-providers \
        tm-cpio-evidence tm-cpio-runtime-smoke tm-cred-evidence tm-elf-evidence tm-elf-runtime-smoke tm-fdt-evidence tm-fdt-runtime-smoke tm-pathmgr-evidence tm-procfs-evidence tm-providers-evidence tm-rsrcdb-evidence tm-script-evidence tm-script-runtime-smoke \
        tm-syscfg-evidence tm-syscfg-runtime-smoke tm-sysmap-evidence tm-sysmap-runtime-smoke tm-sysfs-evidence tm-sysfs-runtime-smoke tm-pseudodev-evidence \
        rust-slogger-boot-smoke \
        rust-virtio-boot-smoke rust-virtio-file-smoke \
        virtio-rc-file-smoke \
        rust-test-msgpass-smoke test-msgpass-rc-smoke pipe-smoke rust-pipe-smoke \
        rust-pipe-data-smoke pipe-rc-data-smoke \
        procfs-smoke tm-procfs-rc-smoke \
        container-toolchain-build container-shell container-check \
        container-index-c container-index-c-static container-index-c-compile-db \
        container-tidy-c \
        container-elf-baseline container-audit-artifacts \
        container-rust-fast container-rust-quality \
        container-rust-abi container-rust-deep container-rust-fuzz-smoke \
        container-rust-coverage \
        container-rust-qsoe-link-smoke \
        container-rust-slogger-link-smoke container-rust-service-example-link-smoke \
        container-rust-virtio-link-smoke container-rust-test-msgpass-link-smoke \
        container-rust-pipe-link-smoke \
        container-slogger-artifact container-virtio-artifact \
        container-test-msgpass-artifact container-pipe-artifact \
        container-rust-tm-cpio-provider container-rust-tm-cred-provider \
        container-rust-tm-elf-provider container-rust-tm-fdt-provider container-rust-tm-pathmgr-provider container-rust-tm-procfs-provider container-rust-tm-rsrcdb-provider container-rust-tm-script-provider \
        container-rust-tm-syscfg-provider container-rust-tm-sysmap-provider container-rust-tm-sysfs-provider \
        container-rust-tm-pseudodev-provider container-rust-tm-providers \
        container-tm-cpio-evidence container-tm-cpio-runtime-smoke container-tm-cred-evidence container-tm-elf-evidence container-tm-elf-runtime-smoke container-tm-fdt-evidence container-tm-fdt-runtime-smoke container-tm-pathmgr-evidence container-tm-procfs-evidence container-tm-providers-evidence \
        container-tm-rsrcdb-evidence container-tm-script-evidence container-tm-script-runtime-smoke container-tm-syscfg-evidence container-tm-syscfg-runtime-smoke \
        container-tm-sysmap-evidence container-tm-sysmap-runtime-smoke container-tm-sysfs-evidence container-tm-sysfs-runtime-smoke container-tm-pseudodev-evidence \
        container-rust-virtio-boot-smoke \
        container-virtio-rc-file-smoke \
        container-rust-mkfs-qrv-live-smoke \
        container-mkfs-qrv-rc-live-smoke container-mkfs-qrv-rc-rollback-smoke \
        container-rust-slog-readback-smoke container-slogger-rc-boot-smoke \
        container-slogger-rc-readback-smoke \
        container-rust-test-msgpass-smoke container-test-msgpass-rc-smoke \
        container-rust-virtio-file-smoke container-pipe-smoke \
        container-rust-pipe-smoke container-rust-pipe-data-smoke \
        container-pipe-rc-data-smoke \
        container-check-qrvfs-rust-writer-fixture \
        container-check-qrvfs-rust-writer-production-root \
        container-procfs-smoke container-tm-procfs-rc-smoke \
        container-treeqrvfs-rc-smoke \
        container-treeqrvfs-rc-rollback-smoke \
        container-source-build

all: component-overrides
	$(MAKE) -C nq QSOE_RUST_TM_CPIO=$(QSOE_RUST_TM_CPIO) \
	    QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED) \
	    QSOE_RUST_TM_ELF=$(QSOE_RUST_TM_ELF) \
	    QSOE_RUST_TM_PATHMGR=$(QSOE_RUST_TM_PATHMGR) \
	    QSOE_RUST_TM_PROCFS=$(QSOE_RUST_TM_PROCFS) \
	    QSOE_RUST_TM_SCRIPT=$(QSOE_RUST_TM_SCRIPT) \
	    QSOE_RUST_TM_SYSCFG=$(QSOE_RUST_TM_SYSCFG) \
	    QSOE_RUST_TM_SYSFS=$(QSOE_RUST_TM_SYSFS)
	$(MAKE) -C lq QSOE_RUST_TM_CPIO=$(QSOE_RUST_TM_CPIO) \
	    QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED) \
	    QSOE_RUST_TM_ELF=$(QSOE_RUST_TM_ELF) \
	    QSOE_RUST_TM_FDT=$(QSOE_RUST_TM_FDT) \
	    QSOE_RUST_TM_PATHMGR=$(QSOE_RUST_TM_PATHMGR) \
	    QSOE_RUST_TM_PROCFS=$(QSOE_RUST_TM_PROCFS) \
	    QSOE_RUST_TM_PSEUDODEV=$(QSOE_RUST_TM_PSEUDODEV) \
	    QSOE_RUST_TM_RSRCDB=$(QSOE_RUST_TM_RSRCDB) \
	    QSOE_RUST_TM_SCRIPT=$(QSOE_RUST_TM_SCRIPT) \
	    QSOE_RUST_TM_SYSCFG=$(QSOE_RUST_TM_SYSCFG) \
	    QSOE_RUST_TM_SYSMAP=$(QSOE_RUST_TM_SYSMAP) \
	    QSOE_RUST_TM_SYSFS=$(QSOE_RUST_TM_SYSFS)

prepare:
	./proj_obtain.sh
	./scripts/apply-component-overrides.sh

component-overrides:
	./scripts/apply-component-overrides.sh

# Whole-tree clean: every component owns its clean; we just descend into
# each, then drop the umbrella's own build/ (disk images + host tools).
# nq/lq clean also remove their per-kernel libc/ + libtaskman/ build dirs
# (lq/build, nq/build); the libc/ and libtaskman/ cleans below cover their
# standalone build dirs.  Use this to kill any build-staleness for good.
CLEAN_DIRS := nq lq quser libc libtaskman
clean:
	@for d in $(CLEAN_DIRS); do \
	    echo "==> clean $$d"; \
	    $(MAKE) -C $$d clean || exit 1; \
	done
	rm -rf build boot/nvme_p*.dat

# ---- NVMe QEMU test image -------------------------------------------
# Eight 16-MiB partitions; p8 carries the fs-qrv type GUID (same as the
# on-disk layout on real hardware).  The GPT skeleton is idempotent: an
# existing image with a valid primary GPT ("EFI PART" at byte 512) is left
# untouched.  p8 is then (re)populated with a qrvfs image carrying the
# userspace that lives on disk rather than in the boot cpio -- today
# /bin/suite, served as /usr/bin/suite once the fs is mounted.  mkfs-qrv is
# host tooling shared by both variants, so it lives here at the umbrella.
NVME_IMG       := build/nvme.img
NVME_IMG_SIZE  := 192M
NVME_NPARTS    := 8
NVME_PARTS     := 16 16 16 16 16 16 16 16

# ---- virtio QEMU test image (QSOE/L) --------------------------------
# QSOE/L has no NVMe under QEMU (seL4 has no AIA), so it boots off a
# virtio-mmio disk instead.  Unlike the NVMe image this is a RAW whole-disk
# qrvfs (no GPT): devb-virtio serves it as /dev/vblk0 and fs-qrv mounts it
# directly.  Same userspace, same mkfs-qrv -- only the container differs.
VIRTIO_IMG     := build/virtio.img

FSQRV_PART     := 8
FSQRV_SIZE_MB  := 16
MKFS_QRV_C     := build/mkfs-qrv
MKFS_QRV_RS    := build/mkfs-qrv-rs
ifeq ($(QSOE_RUST_MKFS_QRV),1)
MKFS_QRV       := $(MKFS_QRV_RS)
else
MKFS_QRV       := $(MKFS_QRV_C)
endif
TREEQRVFS      := build/treeqrvfs
FSQRV_ROOT     := build/fsqrv-root
FSQRV_IMG      := build/fsqrv.img
# On-disk staged init: the cpio /sbin/init mounts the fs and execs
# /usr/sbin/sysinit/level1.sh from it.  Authored under quser, staged into
# the image's /sbin/sysinit by fsqrv-image.
FSQRV_SYSINIT  := quser/sbin/sysinit
# The on-disk userspace, taken from quser's build output (built by nq/lq
# before emu.sh delegates here).  Each "<src>:<name>" pair becomes
# /usr/bin/<name> under the mount.  The test binaries live here rather than
# in the boot cpio -- modpkg carries only what bring-up needs.
FSQRV_BINS     ?= quser/build/test/suite/suite.elf:suite \
                  $(SELECTED_TEST_MSGPASS_ELF):test_msgpass \
                  quser/build/test/syncspace/test_syncspace.elf:test_syncspace \
                  quser/build/utils/time.elf:time \
                  quser/build/utils/sysinfo.elf:sysinfo
FSQRV_HAS_QUSER_TEST_BINS := $(wildcard quser/build/test/suite/suite.elf quser/build/test/syncspace/test_syncspace.elf)
# On-disk /usr/sbin programs: getty + login live on the root fs, not the
# boot cpio -- they cannot do their job without /usr mounted (login reads
# /usr/conf via the /etc symlink), so a boot that can't mount /usr has
# nothing to log into.  Each "<src>:<name>" becomes /usr/sbin/<name>.
FSQRV_SBIN     := quser/build/sbin/getty/getty.elf:getty \
                  quser/build/sbin/login/login.elf:login
# Credentials shipped on the image: /usr/conf/{passwd,shadow,group},
# reached as /etc/* through the taskman /etc -> /usr/conf symlink.
FSQRV_CONF     := quser/conf
# Per-user home skeleton: quser/home/<user>/... -> /usr/home/<user>/...,
# reached as /home/<user> through the /home -> /usr/home symlink.  Ships
# user's ~/.profile so login's chdir(pw_dir) lands in a real, populated
# home instead of falling back to /.
FSQRV_HOME     := quser/home

nvme: $(NVME_IMG) nvme-populate

$(NVME_IMG): host_tools/mkgpt.py
	@mkdir -p $(dir $@)
	@if [ ! -f $@ ] || \
	    [ "$$(dd if=$@ bs=8 skip=64 count=1 2>/dev/null)" != "EFI PART" ]; then \
		truncate -s $(NVME_IMG_SIZE) $@; \
		echo "make nvme: $@ ($(NVME_IMG_SIZE), GPT, $(NVME_NPARTS) x 16 MiB, p8 = fs-qrv)"; \
		host_tools/mkgpt.py --fsqrv $(NVME_NPARTS) $@ $(NVME_PARTS); \
	fi

$(MKFS_QRV_C): host_tools/mkfs-qrv.c quser/fs/qrv/fs.h
	@mkdir -p $(dir $@)
	@cc -O2 -Wall -I quser/fs/qrv -o $@ $<

rust-mkfs-qrv-artifact:
	@scripts/mkfs-qrv-rs-artifact.sh "$(MKFS_QRV_RS)"

$(MKFS_QRV_RS): rust-mkfs-qrv-artifact

treeqrvfs-artifact:
	@scripts/treeqrvfs-artifact.sh "$(TREEQRVFS)"

$(TREEQRVFS): treeqrvfs-artifact

treeqrvfs-rc-smoke:
	@scripts/treeqrvfs-rc-smoke.sh

treeqrvfs-rc-rollback-smoke:
	@TREEQRVFS_RC_ROLLBACK=1 scripts/treeqrvfs-rc-smoke.sh

# Dump the staged qrvfs image's directory tree (build it first if needed).
tree: $(TREEQRVFS) fsqrv-image
	@if [ -f $(FSQRV_IMG) ]; then "$(TREEQRVFS)" $(FSQRV_IMG); \
	else echo "make tree: $(FSQRV_IMG) not built (build quser first)"; fi

check-host-tools: check-qrvfs-fixture check-gpt-fixture \
    check-tm-cpio-model check-tm-cred-model check-tm-elf-model check-tm-pathmgr-model check-tm-procfs-model \
    check-tm-fdt-model check-tm-rsrcdb-model check-tm-script-model check-tm-syscfg-model \
    check-tm-sysmap-model check-tm-sysfs-model

check-qrvfs-fixture:
	@scripts/check-qrvfs-fixture.sh

check-qrvfs-rust-fixture:
	@scripts/check-qrvfs-rust-fixture.sh

check-qrvfs-rust-writer-fixture:
	@scripts/check-qrvfs-rust-writer-fixture.sh

check-qrvfs-rust-writer-production-root:
	@scripts/check-qrvfs-rust-writer-production-root.sh

check-elf-reloc-fixture:
	@scripts/check-elf-reloc-fixture.sh

check-gpt-fixture:
	@scripts/check-gpt-fixture.py

check-tm-cpio-model:
	@scripts/check-tm-cpio-model.sh

check-tm-procfs-model:
	@scripts/check-tm-procfs-model.sh

check-tm-cred-model:
	@scripts/check-tm-cred-model.sh

check-tm-elf-model:
	@scripts/check-tm-elf-model.sh

check-tm-fdt-model:
	@scripts/check-tm-fdt-model.sh

check-tm-pathmgr-model:
	@scripts/check-tm-pathmgr-model.sh

check-tm-rsrcdb-model:
	@scripts/check-tm-rsrcdb-model.sh

check-tm-script-model:
	@scripts/check-tm-script-model.sh

check-tm-syscfg-model:
	@scripts/check-tm-syscfg-model.sh

check-tm-sysmap-model:
	@scripts/check-tm-sysmap-model.sh

check-tm-sysfs-model:
	@scripts/check-tm-sysfs-model.sh

slog-readback-smoke:
	@scripts/slog-readback-smoke.py

rust-slog-readback-smoke:
	@scripts/slog-readback-smoke.py --rust-slogger

slogger-rc-boot-smoke:
	@scripts/slogger-rc-boot-smoke.sh

slogger-rc-readback-smoke:
	@scripts/slog-readback-smoke.py --slogger-rc

index-c: index-c-static

index-c-files:
	@scripts/c-index.sh files

index-c-tags:
	@scripts/c-index.sh tags

index-c-cscope:
	@scripts/c-index.sh cscope

index-c-global:
	@scripts/c-index.sh global

index-c-static:
	@scripts/c-index.sh static

index-c-compile-db:
	@scripts/c-index.sh compile-db

tidy-c:
	@scripts/c-tidy.sh

elf-baseline:
	@scripts/capture-elf-baseline.sh

audit-artifacts: fsqrv-image
	@scripts/audit-artifacts.sh

rust-fast:
	@scripts/rust-workflow.sh fast

rust-quality:
	@scripts/rust-workflow.sh quality

rust-check:
	@scripts/rust-check.sh

rust-abi:
	@scripts/rust-workflow.sh abi

rust-deep:
	@scripts/rust-workflow.sh deep

rust-fuzz-smoke:
	@scripts/rust-fuzz-smoke.sh

rust-coverage:
	@scripts/rust-coverage.sh

rust-qsoe-link-smoke:
	@scripts/rust-qsoe-link-smoke.sh

rust-slogger-link-smoke:
	@RUST_PACKAGE=qsoe-slogger-rs scripts/rust-qsoe-link-smoke.sh

rust-service-example-link-smoke:
	@RUST_PACKAGE=qsoe-service-example-rs scripts/rust-qsoe-link-smoke.sh

rust-virtio-link-smoke:
	@$(MAKE) -C quser/ressrv --no-print-directory
	@RUST_PACKAGE=qsoe-devb-virtio-rs \
	    RUST_EXTRA_LDFLAGS="-L$(CURDIR)/quser/build/ressrv" \
	    RUST_EXTRA_LDLIBS="-lressrv" \
	    scripts/rust-qsoe-link-smoke.sh

rust-test-msgpass-link-smoke:
	@RUST_PACKAGE=qsoe-test-msgpass-rs scripts/rust-qsoe-link-smoke.sh

rust-pipe-link-smoke:
	@RUST_PACKAGE=qsoe-pipe-rs scripts/rust-qsoe-link-smoke.sh

slogger-artifact:
	@QSOE_RUST_SLOGGER=$(QSOE_RUST_SLOGGER) \
	    SELECTED_SLOGGER_ELF=$(SELECTED_SLOGGER_ELF) \
	    scripts/select-slogger-artifact.sh

virtio-artifact:
	@QSOE_RUST_VIRTIO=$(QSOE_RUST_VIRTIO) \
	    SELECTED_VIRTIO_ELF=$(SELECTED_VIRTIO_ELF) \
	    scripts/select-virtio-artifact.sh

test-msgpass-artifact:
	@QSOE_RUST_TEST_MSGPASS=$(QSOE_RUST_TEST_MSGPASS) \
	    LIBC_SO=$(LIBC_SO) \
	    SELECTED_TEST_MSGPASS_ELF=$(SELECTED_TEST_MSGPASS_ELF) \
	    scripts/select-test-msgpass-artifact.sh

$(SELECTED_TEST_MSGPASS_ELF): test-msgpass-artifact

pipe-artifact:
	@QSOE_RUST_PIPE=$(QSOE_RUST_PIPE) \
	    SELECTED_PIPE_ELF=$(SELECTED_PIPE_ELF) \
	    scripts/select-pipe-artifact.sh

rust-tm-cpio-provider:
	@QSOE_RUST_TM_CPIO=1 \
	    scripts/build-rust-tm-providers.sh build/rust/tm-cpio/libqsoe_tm_cpio.a

rust-tm-cred-provider:
	@QSOE_RUST_TM_CRED=1 \
	    scripts/build-rust-tm-providers.sh build/rust/tm-cred/libqsoe_tm_cred.a

rust-tm-elf-provider:
	@QSOE_RUST_TM_ELF=1 \
	    scripts/build-rust-tm-providers.sh build/rust/tm-elf/libqsoe_tm_elf.a

rust-tm-fdt-provider:
	@QSOE_RUST_TM_FDT=1 \
	    scripts/build-rust-tm-providers.sh build/rust/tm-fdt/libqsoe_tm_fdt.a

rust-tm-pathmgr-provider:
	@QSOE_RUST_TM_PATHMGR=1 \
	    scripts/build-rust-tm-providers.sh build/rust/tm-pathmgr/libqsoe_tm_pathmgr.a

rust-tm-procfs-provider:
	@QSOE_RUST_TM_PROCFS=1 \
	    scripts/build-rust-tm-providers.sh build/rust/tm-procfs/libqsoe_tm_procfs.a

rust-tm-rsrcdb-provider:
	@QSOE_RUST_TM_RSRCDB=1 \
	    scripts/build-rust-tm-providers.sh build/rust/tm-rsrcdb/libqsoe_tm_rsrcdb.a

rust-tm-script-provider:
	@QSOE_RUST_TM_SCRIPT=1 \
	    scripts/build-rust-tm-providers.sh build/rust/tm-script/libqsoe_tm_script.a

rust-tm-syscfg-provider:
	@QSOE_RUST_TM_SYSCFG=1 \
	    scripts/build-rust-tm-providers.sh build/rust/tm-syscfg/libqsoe_tm_syscfg.a

rust-tm-sysmap-provider:
	@QSOE_RUST_TM_SYSMAP=1 \
	    scripts/build-rust-tm-providers.sh build/rust/tm-sysmap/libqsoe_tm_sysmap.a

rust-tm-sysfs-provider:
	@QSOE_RUST_TM_SYSFS=1 \
	    scripts/build-rust-tm-providers.sh build/rust/tm-sysfs/libqsoe_tm_sysfs.a

rust-tm-pseudodev-provider:
	@QSOE_RUST_TM_PSEUDODEV=1 \
	    scripts/build-rust-tm-providers.sh build/rust/tm-pseudodev/libqsoe_tm_pseudodev.a

rust-tm-providers:
	@QSOE_RUST_TM_CPIO=$(QSOE_RUST_TM_CPIO) \
	    QSOE_RUST_TM_CRED=$(QSOE_RUST_TM_CRED) \
	    QSOE_RUST_TM_ELF=$(QSOE_RUST_TM_ELF) \
	    QSOE_RUST_TM_FDT=$(QSOE_RUST_TM_FDT) \
	    QSOE_RUST_TM_PATHMGR=$(QSOE_RUST_TM_PATHMGR) \
	    QSOE_RUST_TM_PROCFS=$(QSOE_RUST_TM_PROCFS) \
	    QSOE_RUST_TM_PSEUDODEV=$(QSOE_RUST_TM_PSEUDODEV) \
	    QSOE_RUST_TM_RSRCDB=$(QSOE_RUST_TM_RSRCDB) \
	    QSOE_RUST_TM_SCRIPT=$(QSOE_RUST_TM_SCRIPT) \
	    QSOE_RUST_TM_SYSCFG=$(QSOE_RUST_TM_SYSCFG) \
	    QSOE_RUST_TM_SYSMAP=$(QSOE_RUST_TM_SYSMAP) \
	    QSOE_RUST_TM_SYSFS=$(QSOE_RUST_TM_SYSFS) \
	    scripts/build-rust-tm-providers.sh

tm-cpio-evidence:
	@scripts/tm-cpio-evidence.sh

tm-cpio-runtime-smoke:
	@scripts/tm-cpio-runtime-smoke.sh

tm-cred-evidence:
	@scripts/tm-cred-evidence.sh

tm-elf-evidence:
	@scripts/tm-elf-evidence.sh

tm-elf-runtime-smoke:
	@scripts/tm-elf-runtime-smoke.sh

tm-fdt-evidence:
	@scripts/tm-fdt-evidence.sh

tm-fdt-runtime-smoke:
	@scripts/tm-fdt-runtime-smoke.sh

tm-pathmgr-evidence:
	@scripts/tm-pathmgr-evidence.sh

tm-procfs-evidence:
	@scripts/tm-procfs-evidence.sh

tm-providers-evidence:
	@scripts/tm-providers-evidence.sh

tm-rsrcdb-evidence:
	@scripts/tm-rsrcdb-evidence.sh

tm-script-evidence:
	@scripts/tm-script-evidence.sh

tm-script-runtime-smoke:
	@scripts/tm-script-runtime-smoke.sh

tm-syscfg-evidence:
	@scripts/tm-syscfg-evidence.sh

tm-syscfg-runtime-smoke:
	@scripts/tm-syscfg-runtime-smoke.sh

tm-sysmap-evidence:
	@scripts/tm-sysmap-evidence.sh

tm-sysmap-runtime-smoke:
	@scripts/tm-sysmap-runtime-smoke.sh

tm-sysfs-evidence:
	@scripts/tm-sysfs-evidence.sh

tm-sysfs-runtime-smoke:
	@scripts/tm-sysfs-runtime-smoke.sh

tm-pseudodev-evidence:
	@scripts/tm-pseudodev-evidence.sh

rust-slogger-boot-smoke:
	@scripts/rust-slogger-boot-smoke.sh

rust-virtio-boot-smoke:
	@scripts/rust-virtio-boot-smoke.sh

rust-virtio-file-smoke:
	@scripts/rust-virtio-file-smoke.sh

rust-mkfs-qrv-live-smoke:
	@scripts/rust-mkfs-qrv-live-smoke.sh

mkfs-qrv-rc-live-smoke:
	@scripts/mkfs-qrv-rc-live-smoke.sh

mkfs-qrv-rc-rollback-smoke:
	@MKFS_QRV_RC_ROLLBACK=1 scripts/mkfs-qrv-rc-live-smoke.sh

virtio-rc-file-smoke:
	@scripts/virtio-rc-file-smoke.sh

rust-test-msgpass-smoke:
	@scripts/rust-test-msgpass-smoke.sh

test-msgpass-rc-smoke:
	@scripts/test-msgpass-rc-smoke.sh

pipe-smoke:
	@scripts/pipe-smoke.sh

rust-pipe-smoke:
	@scripts/rust-pipe-smoke.sh

rust-pipe-data-smoke:
	@scripts/rust-pipe-data-smoke.sh

pipe-rc-data-smoke:
	@scripts/pipe-rc-data-smoke.sh

procfs-smoke:
	@scripts/procfs-smoke.sh

tm-procfs-rc-smoke:
	@scripts/tm-procfs-rc-smoke.sh

container-toolchain-build:
	@scripts/container-toolchain.sh build

container-shell:
	@scripts/container-toolchain.sh shell

container-check:
	@scripts/container-toolchain.sh check

container-index-c: container-index-c-static

container-index-c-static:
	@scripts/container-toolchain.sh index-c-static

container-index-c-compile-db:
	@scripts/container-toolchain.sh index-c-compile-db

container-tidy-c:
	@scripts/container-toolchain.sh tidy-c

container-elf-baseline:
	@scripts/container-toolchain.sh run scripts/capture-elf-baseline.sh

container-audit-artifacts:
	@scripts/container-toolchain.sh run make audit-artifacts

container-rust-fast:
	@scripts/container-toolchain.sh run make rust-fast

container-rust-quality:
	@scripts/container-toolchain.sh run make rust-quality

container-rust-abi:
	@scripts/container-toolchain.sh run make rust-abi

container-rust-deep:
	@scripts/container-toolchain.sh run make rust-deep

container-rust-fuzz-smoke:
	@scripts/container-toolchain.sh run make rust-fuzz-smoke

container-rust-coverage:
	@scripts/container-toolchain.sh run make rust-coverage

container-rust-qsoe-link-smoke:
	@scripts/container-toolchain.sh rust-link-smoke

container-rust-slogger-link-smoke:
	@scripts/container-toolchain.sh run make rust-slogger-link-smoke

container-rust-service-example-link-smoke:
	@scripts/container-toolchain.sh run make rust-service-example-link-smoke

container-rust-virtio-link-smoke:
	@scripts/container-toolchain.sh run make rust-virtio-link-smoke

container-rust-test-msgpass-link-smoke:
	@scripts/container-toolchain.sh run make rust-test-msgpass-link-smoke

container-rust-pipe-link-smoke:
	@scripts/container-toolchain.sh run make rust-pipe-link-smoke

container-slogger-artifact:
	@scripts/container-toolchain.sh run make slogger-artifact \
	    QSOE_RUST_SLOGGER=$(QSOE_RUST_SLOGGER) \
	    SELECTED_SLOGGER_ELF=$(SELECTED_SLOGGER_ELF)

container-virtio-artifact:
	@scripts/container-toolchain.sh run make virtio-artifact \
	    QSOE_RUST_VIRTIO=$(QSOE_RUST_VIRTIO) \
	    SELECTED_VIRTIO_ELF=$(SELECTED_VIRTIO_ELF)

container-test-msgpass-artifact:
	@scripts/container-toolchain.sh run make test-msgpass-artifact \
	    QSOE_RUST_TEST_MSGPASS=$(QSOE_RUST_TEST_MSGPASS) \
	    LIBC_SO=$(LIBC_SO) \
	    SELECTED_TEST_MSGPASS_ELF=$(SELECTED_TEST_MSGPASS_ELF)

container-pipe-artifact:
	@scripts/container-toolchain.sh run make pipe-artifact \
	    QSOE_RUST_PIPE=$(QSOE_RUST_PIPE) \
	    SELECTED_PIPE_ELF=$(SELECTED_PIPE_ELF)

container-rust-tm-cpio-provider:
	@scripts/container-toolchain.sh run make rust-tm-cpio-provider

container-rust-tm-cred-provider:
	@scripts/container-toolchain.sh run make rust-tm-cred-provider

container-rust-tm-elf-provider:
	@scripts/container-toolchain.sh run make rust-tm-elf-provider

container-rust-tm-fdt-provider:
	@scripts/container-toolchain.sh run make rust-tm-fdt-provider

container-rust-tm-pathmgr-provider:
	@scripts/container-toolchain.sh run make rust-tm-pathmgr-provider

container-rust-tm-procfs-provider:
	@scripts/container-toolchain.sh run make rust-tm-procfs-provider

container-rust-tm-rsrcdb-provider:
	@scripts/container-toolchain.sh run make rust-tm-rsrcdb-provider

container-rust-tm-script-provider:
	@scripts/container-toolchain.sh run make rust-tm-script-provider

container-rust-tm-syscfg-provider:
	@scripts/container-toolchain.sh run make rust-tm-syscfg-provider

container-rust-tm-sysmap-provider:
	@scripts/container-toolchain.sh run make rust-tm-sysmap-provider

container-rust-tm-sysfs-provider:
	@scripts/container-toolchain.sh run make rust-tm-sysfs-provider

container-rust-tm-providers:
	@scripts/container-toolchain.sh run make rust-tm-providers

container-rust-tm-pseudodev-provider:
	@scripts/container-toolchain.sh run make rust-tm-pseudodev-provider

container-tm-cpio-evidence:
	@scripts/container-toolchain.sh run make tm-cpio-evidence

container-tm-cpio-runtime-smoke:
	@scripts/container-toolchain.sh run make tm-cpio-runtime-smoke

container-tm-cred-evidence:
	@scripts/container-toolchain.sh run make tm-cred-evidence

container-tm-elf-evidence:
	@scripts/container-toolchain.sh run make tm-elf-evidence

container-tm-elf-runtime-smoke:
	@scripts/container-toolchain.sh run make tm-elf-runtime-smoke

container-tm-fdt-evidence:
	@scripts/container-toolchain.sh run make tm-fdt-evidence

container-tm-fdt-runtime-smoke:
	@scripts/container-toolchain.sh run make tm-fdt-runtime-smoke

container-tm-pathmgr-evidence:
	@scripts/container-toolchain.sh run make tm-pathmgr-evidence

container-tm-procfs-evidence:
	@scripts/container-toolchain.sh run make tm-procfs-evidence

container-tm-providers-evidence:
	@scripts/container-toolchain.sh run make tm-providers-evidence

container-tm-rsrcdb-evidence:
	@scripts/container-toolchain.sh run make tm-rsrcdb-evidence

container-tm-script-evidence:
	@scripts/container-toolchain.sh run make tm-script-evidence

container-tm-script-runtime-smoke:
	@scripts/container-toolchain.sh run make tm-script-runtime-smoke

container-tm-syscfg-evidence:
	@scripts/container-toolchain.sh run make tm-syscfg-evidence

container-tm-syscfg-runtime-smoke:
	@scripts/container-toolchain.sh run make tm-syscfg-runtime-smoke

container-tm-sysmap-evidence:
	@scripts/container-toolchain.sh run make tm-sysmap-evidence

container-tm-sysmap-runtime-smoke:
	@scripts/container-toolchain.sh run make tm-sysmap-runtime-smoke

container-tm-sysfs-evidence:
	@scripts/container-toolchain.sh run make tm-sysfs-evidence

container-tm-sysfs-runtime-smoke:
	@scripts/container-toolchain.sh run make tm-sysfs-runtime-smoke

container-tm-pseudodev-evidence:
	@scripts/container-toolchain.sh run make tm-pseudodev-evidence

container-check-qrvfs-rust-writer-fixture:
	@scripts/container-toolchain.sh run make check-qrvfs-rust-writer-fixture

container-check-qrvfs-rust-writer-production-root:
	@scripts/container-toolchain.sh run make check-qrvfs-rust-writer-production-root

container-rust-virtio-boot-smoke:
	@scripts/container-toolchain.sh run make rust-virtio-boot-smoke

container-virtio-rc-file-smoke:
	@scripts/container-toolchain.sh run make virtio-rc-file-smoke

container-rust-mkfs-qrv-live-smoke:
	@scripts/container-toolchain.sh run make rust-mkfs-qrv-live-smoke

container-mkfs-qrv-rc-live-smoke:
	@scripts/container-toolchain.sh run make mkfs-qrv-rc-live-smoke

container-mkfs-qrv-rc-rollback-smoke:
	@scripts/container-toolchain.sh run make mkfs-qrv-rc-rollback-smoke

container-rust-slog-readback-smoke:
	@scripts/container-toolchain.sh run make rust-slog-readback-smoke

container-slogger-rc-boot-smoke:
	@scripts/container-toolchain.sh run make slogger-rc-boot-smoke

container-slogger-rc-readback-smoke:
	@scripts/container-toolchain.sh run make slogger-rc-readback-smoke

container-rust-test-msgpass-smoke:
	@scripts/container-toolchain.sh run make rust-test-msgpass-smoke

container-test-msgpass-rc-smoke:
	@scripts/container-toolchain.sh run make test-msgpass-rc-smoke

container-rust-virtio-file-smoke:
	@scripts/container-toolchain.sh run make rust-virtio-file-smoke

container-pipe-smoke:
	@scripts/container-toolchain.sh run make pipe-smoke

container-rust-pipe-smoke:
	@scripts/container-toolchain.sh run make rust-pipe-smoke

container-rust-pipe-data-smoke:
	@scripts/container-toolchain.sh run make rust-pipe-data-smoke

container-pipe-rc-data-smoke:
	@scripts/container-toolchain.sh run make pipe-rc-data-smoke

container-procfs-smoke:
	@scripts/container-toolchain.sh run make procfs-smoke

container-tm-procfs-rc-smoke:
	@scripts/container-toolchain.sh run make tm-procfs-rc-smoke

container-treeqrvfs-rc-smoke:
	@scripts/container-toolchain.sh run make treeqrvfs-rc-smoke

container-treeqrvfs-rc-rollback-smoke:
	@scripts/container-toolchain.sh run make treeqrvfs-rc-rollback-smoke

container-source-build:
	@scripts/container-toolchain.sh source-build

# Build the qrvfs image once from a proto root assembled out of quser's
# build output; the staged tree becomes /usr/bin/* under the mount.  Both
# the NVMe (GPT p8) and virtio (raw whole-disk) images reuse it.  If quser
# hasn't been built yet there is nothing to stage and FSQRV_IMG is removed
# so the consumers know to leave their images alone.
ifneq ($(FSQRV_HAS_QUSER_TEST_BINS),)
fsqrv-image: $(SELECTED_TEST_MSGPASS_ELF)
endif

fsqrv-image: $(MKFS_QRV)
	@rm -rf $(FSQRV_ROOT); mkdir -p $(FSQRV_ROOT)/bin $(FSQRV_ROOT)/home; \
	have=0; \
	for pair in $(FSQRV_BINS); do \
		src=$${pair%%:*}; name=$${pair##*:}; \
		if [ -f "$$src" ]; then cp "$$src" $(FSQRV_ROOT)/bin/$$name; have=1; fi; \
	done; \
	if [ -f $(FSQRV_SYSINIT)/level1.sh ]; then \
		mkdir -p $(FSQRV_ROOT)/sbin/sysinit; \
		cp $(FSQRV_SYSINIT)/level1.sh $(FSQRV_ROOT)/sbin/sysinit/; \
		chmod +x $(FSQRV_ROOT)/sbin/sysinit/level1.sh; \
	fi; \
	mkdir -p $(FSQRV_ROOT)/sbin; \
	for pair in $(FSQRV_SBIN); do \
		src=$${pair%%:*}; name=$${pair##*:}; \
		if [ -f "$$src" ]; then cp "$$src" $(FSQRV_ROOT)/sbin/$$name; have=1; fi; \
	done; \
	if [ -d $(FSQRV_CONF) ]; then \
		mkdir -p $(FSQRV_ROOT)/conf; \
		for f in $(FSQRV_CONF)/passwd $(FSQRV_CONF)/shadow $(FSQRV_CONF)/group; do \
			[ -f "$$f" ] && cp "$$f" $(FSQRV_ROOT)/conf/; \
		done; \
		if [ -d $(FSQRV_CONF)/sysinit ]; then \
			cp -a $(FSQRV_CONF)/sysinit $(FSQRV_ROOT)/conf/; \
		fi; \
		have=1; \
	fi; \
	if [ -d $(FSQRV_HOME) ]; then \
		cp -a $(FSQRV_HOME)/. $(FSQRV_ROOT)/home/; \
		have=1; \
	fi; \
	if [ $$have = 1 ]; then \
		"$(MKFS_QRV)" -s $(FSQRV_SIZE_MB) $(FSQRV_IMG) $(FSQRV_ROOT) >/dev/null; \
		echo "make: qrvfs image $(FSQRV_IMG) <- /usr/bin from $(FSQRV_ROOT)"; \
	else \
		rm -f $(FSQRV_IMG); \
		echo "make: no fs binaries built -- qrvfs image skipped (build quser first)"; \
	fi

# NVMe: write the qrvfs image into the GPT image's p8.
nvme-populate: LIBC_SO ?= $(CURDIR)/nq/build/libc/libc.so
nvme-populate: $(NVME_IMG) fsqrv-image
	@if [ -f $(FSQRV_IMG) ]; then \
		host_tools/mkgpt.py --write-part $(FSQRV_PART) $(NVME_IMG) \
			$(FSQRV_IMG) $(NVME_PARTS); \
	else \
		echo "make nvme: p8 left empty"; \
	fi

# virtio: the raw qrvfs image IS the whole disk (no GPT).
virtio: LIBC_SO ?= $(CURDIR)/lq/build/libc/libc.so
virtio: fsqrv-image
	@if [ -f $(FSQRV_IMG) ]; then \
		cp $(FSQRV_IMG) $(VIRTIO_IMG); \
		echo "make virtio: $(VIRTIO_IMG) ($(FSQRV_SIZE_MB) MiB raw qrvfs, /dev/vblk0)"; \
	else \
		echo "make virtio: $(VIRTIO_IMG) not built"; \
	fi
