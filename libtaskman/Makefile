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

SRCS := $(wildcard src/*.c)
OBJS := $(addprefix $(O)/,$(notdir $(SRCS:.c=.o)))
DEPS := $(OBJS:.o=.d)

.PHONY: all clean
all: $(O)/libtaskman.a

$(O)/libtaskman.a: $(OBJS)
	$(AR) rcs $@ $^

$(O)/%.o: src/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -rf $(O)

-include $(DEPS)
