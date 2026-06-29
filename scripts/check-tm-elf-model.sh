#!/usr/bin/env bash
#
# Build and run the host-side fixture for libtaskman's tm_elf parser.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build/fixtures/tm-elf"
CC=${HOST_CC:-cc}

mkdir -p "$BUILD"

"$CC" -std=c11 -Wall -Wextra -I"$ROOT/libtaskman/include" \
    -o "$BUILD/tm_elf_model_test" \
    "$ROOT/tests/tm_elf_model_test.c"

"$BUILD/tm_elf_model_test"

echo "check-tm-elf-model.sh: ok"
echo "  binary: $BUILD/tm_elf_model_test"
