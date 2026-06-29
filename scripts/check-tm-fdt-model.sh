#!/usr/bin/env bash
#
# Build and run the host-side fixture for LQ taskman's FDT parser model.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build/fixtures/tm-fdt"
CC=${CC:-cc}

mkdir -p "$BUILD"

"$CC" -std=c11 -O2 -Wall -Wextra -Werror \
    -I "$ROOT/libc/include" \
    -I "$ROOT/lq/taskman" \
    -o "$BUILD/tm_fdt_model_test" \
    "$ROOT/tests/tm_fdt_model_test.c" \
    "$ROOT/lq/taskman/sys/fdt.c"

"$BUILD/tm_fdt_model_test"

echo "check-tm-fdt-model.sh: ok"
echo "  binary: $BUILD/tm_fdt_model_test"
