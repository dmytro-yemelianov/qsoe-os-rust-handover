#!/usr/bin/env bash
#
# Build and run the host-side fixture for LQ taskman's rsrcdb model.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build/fixtures/tm-rsrcdb"
CC=${CC:-cc}

mkdir -p "$BUILD"

"$CC" -std=c11 -O2 -Wall -Wextra -Werror \
    -I "$ROOT/libc/include" \
    -I "$ROOT/lq/taskman" \
    -o "$BUILD/tm_rsrcdb_model_test" \
    "$ROOT/tests/tm_rsrcdb_model_test.c"

"$BUILD/tm_rsrcdb_model_test"

echo "check-tm-rsrcdb-model.sh: ok"
echo "  binary: $BUILD/tm_rsrcdb_model_test"
