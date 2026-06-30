#!/usr/bin/env bash
#
# Run the host-side tests for the retired Rust tm_pathmgr model.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

cargo test --manifest-path "$ROOT/rust/Cargo.toml" \
    -p qsoe-tm-pathmgr \
    --features host-tests

echo "check-tm-pathmgr-model.sh: ok"
