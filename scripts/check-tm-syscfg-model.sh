#!/usr/bin/env bash
#
# Build and run the host-side fixture for libtaskman's portable tm_syscfg model.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build/fixtures/tm-syscfg"
CC=${CC:-cc}

mkdir -p "$BUILD"

"$CC" -std=c11 -O2 -Wall -Wextra -Werror \
    -I "$ROOT/libtaskman/include" \
    -I "$ROOT/libc/include" \
    -o "$BUILD/tm_syscfg_model_test" \
    "$ROOT/tests/tm_syscfg_model_test.c" \
    "$ROOT/libtaskman/src/syscfg.c"

"$BUILD/tm_syscfg_model_test"

echo "check-tm-syscfg-model.sh: ok"
echo "  binary: $BUILD/tm_syscfg_model_test"
