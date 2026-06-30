#!/usr/bin/env bash
#
# Compiler-name preserving wrapper for container-level sccache opt-in.

set -eu

compiler=$(basename "$0")

if [ -n "${QSOE_SCCACHE_ORIG_PATH:-}" ]; then
    export PATH="$QSOE_SCCACHE_ORIG_PATH"
fi

exec sccache "$compiler" "$@"
