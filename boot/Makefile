#
# boot/Makefile -- U-Boot boot scripts + deployment to the RISC-V
# workstation ("freedom", SiFive Unmatched / FU740).
#
# `make`        builds the .scr images from the .txt command files.
# `make deploy` ships everything to $(REMOTE_HOST):$(REMOTE_DIR):
#   QSOE/N: skimmer.bin (objcopy'd from the kernel ELF) + modpkg.cpio
#   QSOE/L: qsoe.elf          (for U-Boot `bootelf` -- honors the
#                              elfloader's fixed 0x84000000 link addr)
#           qsoe-l-fu740.bin  (raw image for mr-bml: load + set
#                              a0=hartid/a1=DTB + jump @ 0x84000000)
#          (both embed seL4 kernel + taskman + modpkg via .incbin)
#   plus nvme_p8.dat -- the fs-qrv partition (p8) extracted from
#        build/nvme.img, ready to dd onto a real NVMe partition.  Only
#        p8 is shipped: the other partitions are empty scratch, of no
#        use on hardware (mirrors QRV, which deployed nvme_p8.dat alone).
#
# Build the QSOE/L artifacts first:  make -C ../lq PLAT=hifive
#
# Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
# SPDX-License-Identifier: Apache-2.0
#

SCRIPTS     = boot-nq.scr boot-lq.scr
REMOTE_HOST = freedom
REMOTE_DIR  = /boot/qsoe

# Artifact locations inside the umbrella tree.
NQ_KERNEL_ELF = ../nq/kernel/arch/riscv/skimmer
NQ_MODPKG     = ../nq/build/modpkg.cpio
NQ_NVME_IMG   = ../nq/build/nvme.img
LQ_QSOE_ELF   = ../lq/build/qsoe.elf
LQ_FU740_BIN  = ../lq/build/qsoe-l-fu740.bin

# Only the fs-qrv partition is useful on hardware; the rest of nvme.img is
# empty scratch.  p8 carries the fs-qrv (qrvfs) partition-type GUID --
# mirrors the canonical NVMe layout (see ../nq/host_tools/mkgpt.py).
NVME_FSQRV_PART = 8                      # 1-based partition index of fs-qrv
NVME_P8_DAT     = nvme_p8.dat            # extracted partition, shipped alone
GPTEXTRACT      = ./gptextract.py

CROSS   ?= riscv64-linux-gnu-
OBJCOPY  = $(CROSS)objcopy

all: $(SCRIPTS)

boot-nq.scr: boot-nq.txt
	mkimage -T script -A riscv -O linux -C none -n "Boot QSOE/N" -d $< $@

boot-lq.scr: boot-lq.txt
	mkimage -T script -A riscv -O linux -C none -n "Boot QSOE/L" -d $< $@

# U-Boot's booti wants a flat binary at the load PA, not an ELF.
# (The Linux RISC-V image header booti also checks is a head.S
# work item -- see the bring-up notes in boot-nq.txt.)
skimmer.bin: $(NQ_KERNEL_ELF)
	$(OBJCOPY) -O binary $< $@

# QSOE/L: wrap the raw elfloader .bin in a legacy U-Boot uImage so it
# boots via `bootm` -- which on RISC-V enters the image as
# kernel(a0=hartid, a1=DTB), exactly what the elfloader's crt0.S needs,
# WITHOUT requiring the RISC-V Linux Image header that `booti` checks.
# Load + entry are the elfloader's fixed link address (0x84000000).
LQ_UIMAGE   = qsoe-l-fu740.uImage
LQ_LOAD_ADDR = 0x84000000

$(LQ_UIMAGE): $(LQ_FU740_BIN)
	mkimage -A riscv -O linux -T kernel -C none \
	    -a $(LQ_LOAD_ADDR) -e $(LQ_LOAD_ADDR) -n "QSOE/L FU740" \
	    -d $< $@

deploy: $(SCRIPTS) skimmer.bin
	ssh $(REMOTE_HOST) mkdir -p $(REMOTE_DIR)
	scp $(SCRIPTS) $(REMOTE_HOST):$(REMOTE_DIR)/
	scp skimmer.bin $(NQ_MODPKG) $(REMOTE_HOST):$(REMOTE_DIR)/
	if test -f $(LQ_FU740_BIN); then \
	    $(MAKE) --no-print-directory $(LQ_UIMAGE) && \
	    scp $(LQ_FU740_BIN) $(LQ_UIMAGE) $(REMOTE_HOST):$(REMOTE_DIR)/ ; fi
	if test -f $(NQ_NVME_IMG); then \
	    $(GPTEXTRACT) $(NQ_NVME_IMG) $(NVME_FSQRV_PART) $(NVME_P8_DAT) && \
	    scp $(NVME_P8_DAT) $(REMOTE_HOST):$(REMOTE_DIR)/ ; fi

clean:
	rm -f $(SCRIPTS) skimmer.bin $(LQ_UIMAGE) $(NVME_P8_DAT)

.PHONY: all clean deploy
