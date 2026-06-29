# Makefile: build libtaskman.a -- the OS-independent body of every QSOE
# taskman.  Linked into the concrete taskmen at nq/taskman and
# lq/taskman.
#
# This repository is OS-independent and names neither lq nor nq.  The
# consumer (the per-kernel taskman build) drives this Makefile with:
#
#   O          output directory for objects and libtaskman.a
#   LIBC_INC   path(s) to libc public headers (for <sys/qsoe.h>)
#   ARCHFLAGS  target arch/ABI flags (e.g. -march=... -mabi=lp64 -mcmodel=medany)
#
# A bare `make` here gives a standalone "does the body still compile?"
# health check using sensible defaults.
#
# Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
# SPDX-License-Identifier: Apache-2.0

CROSS    ?= riscv64-linux-gnu-
CC       := $(CROSS)gcc
AR       := $(CROSS)ar
QSOE_RUST_TM_CPIO ?= 0
QSOE_RUST_TM_CRED ?= 0
QSOE_RUST_TM_ELF ?= 0
QSOE_RUST_TM_PATHMGR ?= 0
QSOE_RUST_TM_PROCFS ?= 1
QSOE_RUST_TM_SCRIPT ?= 0
QSOE_RUST_TM_SYSCFG ?= 0
QSOE_RUST_TM_SYSFS ?= 0

O           ?= build
LIBC_INC    ?= ../libc/include
ARCHFLAGS   ?= -march=rv64imac_zicsr_zifencei_zicntr -mabi=lp64 -mcmodel=medany
# PIC posture: dynamic-link consumers (LQ today) pass -fPIC; static-link
# consumers (NQ taskman) override with -fno-pic.  Default is -fPIC so a
# standalone health-check `make` here matches LQ's posture.
PICFLAG     ?= -fPIC
EXTRA_CFLAGS ?=

# -nostdinc + the explicit -isystem chain keeps the host glibc out,
# same posture as libc itself.
GCC_INCLUDE := $(shell $(CC) -print-file-name=include)

CFLAGS := $(ARCHFLAGS) -std=c11 -D_XOPEN_SOURCE=700 \
          $(PICFLAG) -ffreestanding -nostdinc \
          -fno-stack-protector \
          -Wall -Wextra -Wno-unused-parameter -O2 -g \
          -MMD -MP \
          -isystem $(GCC_INCLUDE) \
          -isystem $(LIBC_INC) \
          -Iinclude \
          $(EXTRA_CFLAGS)

ifneq ($(filter $(QSOE_RUST_TM_CPIO),0 1),$(QSOE_RUST_TM_CPIO))
$(error QSOE_RUST_TM_CPIO must be 0 or 1)
endif

ifneq ($(filter $(QSOE_RUST_TM_CRED),0 1),$(QSOE_RUST_TM_CRED))
$(error QSOE_RUST_TM_CRED must be 0 or 1)
endif

ifneq ($(filter $(QSOE_RUST_TM_ELF),0 1),$(QSOE_RUST_TM_ELF))
$(error QSOE_RUST_TM_ELF must be 0 or 1)
endif

ifneq ($(filter $(QSOE_RUST_TM_PATHMGR),0 1),$(QSOE_RUST_TM_PATHMGR))
$(error QSOE_RUST_TM_PATHMGR must be 0 or 1)
endif

ifneq ($(QSOE_RUST_TM_PROCFS),1)
$(error QSOE_RUST_TM_PROCFS must be 1 after C tm_procfs retirement)
endif

ifneq ($(filter $(QSOE_RUST_TM_SCRIPT),0 1),$(QSOE_RUST_TM_SCRIPT))
$(error QSOE_RUST_TM_SCRIPT must be 0 or 1)
endif

ifneq ($(filter $(QSOE_RUST_TM_SYSCFG),0 1),$(QSOE_RUST_TM_SYSCFG))
$(error QSOE_RUST_TM_SYSCFG must be 0 or 1)
endif

ifneq ($(filter $(QSOE_RUST_TM_SYSFS),0 1),$(QSOE_RUST_TM_SYSFS))
$(error QSOE_RUST_TM_SYSFS must be 0 or 1)
endif

SRCS_ALL := $(wildcard src/*.c)
SRCS := $(SRCS_ALL)
ifeq ($(QSOE_RUST_TM_CPIO),1)
SRCS := $(filter-out src/cpio.c,$(SRCS))
endif
ifeq ($(QSOE_RUST_TM_CRED),1)
SRCS := $(filter-out src/cred.c,$(SRCS))
endif
ifeq ($(QSOE_RUST_TM_ELF),1)
SRCS := $(filter-out src/elf.c,$(SRCS))
endif
ifeq ($(QSOE_RUST_TM_PATHMGR),1)
SRCS := $(filter-out src/pathmgr.c,$(SRCS))
endif
ifeq ($(QSOE_RUST_TM_SCRIPT),1)
SRCS := $(filter-out src/script.c,$(SRCS))
endif
ifeq ($(QSOE_RUST_TM_SYSCFG),1)
SRCS := $(filter-out src/syscfg.c,$(SRCS))
endif
ifeq ($(QSOE_RUST_TM_SYSFS),1)
SRCS := $(filter-out src/tm_sysfs.c,$(SRCS))
endif
OBJS := $(addprefix $(O)/,$(notdir $(SRCS:.c=.o)))
DEPS := $(OBJS:.o=.d)

.PHONY: all clean FORCE
all: $(O)/libtaskman.a

$(O)/libtaskman.a: $(OBJS) FORCE
	rm -f $@
	$(AR) rcs $@ $(OBJS)

FORCE:

$(O)/%.o: src/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -rf $(O)

-include $(DEPS)
