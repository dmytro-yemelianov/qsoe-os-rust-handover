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

.PHONY: all prepare clean nvme nvme-populate virtio fsqrv-image tree \
        check-host-tools check-qrvfs-fixture check-qrvfs-rust-fixture \
        check-gpt-fixture \
        slog-readback-smoke \
        index-c index-c-files index-c-tags index-c-cscope index-c-global \
        index-c-static index-c-compile-db \
        elf-baseline rust-fast rust-quality rust-check rust-abi rust-deep \
        rust-qsoe-link-smoke \
        container-toolchain-build container-shell container-check \
        container-index-c container-index-c-static container-index-c-compile-db \
        container-elf-baseline container-rust-fast container-rust-quality \
        container-rust-abi container-rust-deep container-rust-qsoe-link-smoke \
        container-source-build

all:
	$(MAKE) -C nq
	$(MAKE) -C lq

prepare:
	./proj_obtain.sh

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
MKFS_QRV       := build/mkfs-qrv
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
FSQRV_BINS     := quser/build/test/suite/suite.elf:suite \
                  quser/build/test/msgpass/test_msgpass.elf:test_msgpass \
                  quser/build/test/syncspace/test_syncspace.elf:test_syncspace \
                  quser/build/utils/time.elf:time \
                  quser/build/utils/sysinfo.elf:sysinfo
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

$(MKFS_QRV): host_tools/mkfs-qrv.c quser/fs/qrv/fs.h
	@mkdir -p $(dir $@)
	@cc -O2 -Wall -I quser/fs/qrv -o $@ $<

$(TREEQRVFS): host_tools/treeqrvfs.c quser/fs/qrv/fs.h
	@mkdir -p $(dir $@)
	@cc -O2 -Wall -I quser/fs/qrv -o $@ $<

# Dump the staged qrvfs image's directory tree (build it first if needed).
tree: $(TREEQRVFS) fsqrv-image
	@if [ -f $(FSQRV_IMG) ]; then "$(TREEQRVFS)" $(FSQRV_IMG); \
	else echo "make tree: $(FSQRV_IMG) not built (build quser first)"; fi

check-host-tools: check-qrvfs-fixture check-gpt-fixture

check-qrvfs-fixture:
	@scripts/check-qrvfs-fixture.sh

check-qrvfs-rust-fixture:
	@scripts/check-qrvfs-rust-fixture.sh

check-gpt-fixture:
	@scripts/check-gpt-fixture.py

slog-readback-smoke:
	@scripts/slog-readback-smoke.py

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

elf-baseline:
	@scripts/capture-elf-baseline.sh

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

rust-qsoe-link-smoke:
	@scripts/rust-qsoe-link-smoke.sh

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

container-elf-baseline:
	@scripts/container-toolchain.sh run scripts/capture-elf-baseline.sh

container-rust-fast:
	@scripts/container-toolchain.sh run make rust-fast

container-rust-quality:
	@scripts/container-toolchain.sh run make rust-quality

container-rust-abi:
	@scripts/container-toolchain.sh run make rust-abi

container-rust-deep:
	@scripts/container-toolchain.sh run make rust-deep

container-rust-qsoe-link-smoke:
	@scripts/container-toolchain.sh rust-link-smoke

container-source-build:
	@scripts/container-toolchain.sh source-build

# Build the qrvfs image once from a proto root assembled out of quser's
# build output; the staged tree becomes /usr/bin/* under the mount.  Both
# the NVMe (GPT p8) and virtio (raw whole-disk) images reuse it.  If quser
# hasn't been built yet there is nothing to stage and FSQRV_IMG is removed
# so the consumers know to leave their images alone.
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
nvme-populate: $(NVME_IMG) fsqrv-image
	@if [ -f $(FSQRV_IMG) ]; then \
		host_tools/mkgpt.py --write-part $(FSQRV_PART) $(NVME_IMG) \
			$(FSQRV_IMG) $(NVME_PARTS); \
	else \
		echo "make nvme: p8 left empty"; \
	fi

# virtio: the raw qrvfs image IS the whole disk (no GPT).
virtio: fsqrv-image
	@if [ -f $(FSQRV_IMG) ]; then \
		cp $(FSQRV_IMG) $(VIRTIO_IMG); \
		echo "make virtio: $(VIRTIO_IMG) ($(FSQRV_SIZE_MB) MiB raw qrvfs, /dev/vblk0)"; \
	else \
		echo "make virtio: $(VIRTIO_IMG) not built"; \
	fi
