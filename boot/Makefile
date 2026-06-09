#
# boot/Makefile -- U-Boot boot scripts + deployment to the RISC-V
# workstation ("freedom", SiFive Unmatched / FU740).
#
# `make`        builds the .scr images from the .txt command files.
# `make deploy` ships everything to $(REMOTE_HOST):$(REMOTE_DIR):
#   QSOE/N: skimmer.bin (objcopy'd from the kernel ELF) + modpkg.cpio
#   QSOE/L: qsoe.elf    (one file -- the modpkg.cpio is .incbin'ed
#                        into taskman inside the elfloader image)
#   plus build/nvme.img, handy for dd'ing onto a real NVMe partition.
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

deploy: $(SCRIPTS) skimmer.bin
	ssh $(REMOTE_HOST) mkdir -p $(REMOTE_DIR)
	scp $(SCRIPTS) $(REMOTE_HOST):$(REMOTE_DIR)/
	scp skimmer.bin $(NQ_MODPKG) $(REMOTE_HOST):$(REMOTE_DIR)/
	if test -f $(LQ_QSOE_ELF); then scp $(LQ_QSOE_ELF) $(REMOTE_HOST):$(REMOTE_DIR)/ ; fi
	if test -f $(NQ_NVME_IMG); then scp $(NQ_NVME_IMG) $(REMOTE_HOST):$(REMOTE_DIR)/ ; fi

clean:
	rm -f $(SCRIPTS) skimmer.bin

.PHONY: all clean deploy
