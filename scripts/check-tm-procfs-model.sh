#!/usr/bin/env bash
#
# Build and run the host-side fixture for libtaskman's portable tm_procfs model.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build/fixtures/tm-procfs"
CC=${CC:-cc}

mkdir -p "$BUILD"

"$CC" -std=c11 -O2 -Wall -Wextra -Werror \
    -I "$ROOT/libtaskman/include" \
    -o "$BUILD/tm_procfs_model_test" \
    "$ROOT/tests/tm_procfs_model_test.c" \
    "$ROOT/libtaskman/src/tm_procfs.c"

"$BUILD/tm_procfs_model_test"

echo "check-tm-procfs-model.sh: ok"
echo "  binary: $BUILD/tm_procfs_model_test"
