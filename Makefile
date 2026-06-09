# Makefile -- top-level QSOE umbrella build orchestrator.
#
# Goals:
#   all        build both OS variants (nq, then lq); each component
#              owns its build, this file only descends.
#   prepare    obtain the components matching this tree's release tag
#              (delegated to proj_obtain.sh, see component.list).
#
# Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
# SPDX-License-Identifier: Apache-2.0

.PHONY: all prepare

all:
	$(MAKE) -C nq
	$(MAKE) -C lq

prepare:
	./proj_obtain.sh
