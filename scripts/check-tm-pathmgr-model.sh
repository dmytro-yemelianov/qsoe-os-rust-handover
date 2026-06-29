#!/usr/bin/env bash
#
# Build and run the host-side fixture for libtaskman's portable tm_pathmgr model.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build/fixtures/tm-pathmgr"
CC=${CC:-cc}

mkdir -p "$BUILD"

"$CC" -std=c11 -O2 -Wall -Wextra -Werror \
    -I "$ROOT/libtaskman/include" \
    -I "$ROOT/libc/include" \
    -include errno.h \
    -o "$BUILD/tm_pathmgr_model_test" \
    "$ROOT/tests/tm_pathmgr_model_test.c" \
    "$ROOT/libtaskman/src/pathmgr.c"

"$BUILD/tm_pathmgr_model_test"

echo "check-tm-pathmgr-model.sh: ok"
echo "  binary: $BUILD/tm_pathmgr_model_test"
