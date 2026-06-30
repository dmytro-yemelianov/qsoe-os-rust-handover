#!/usr/bin/env bash
#
# Run the host-side tests for the retired Rust tm_script model.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cargo test --manifest-path "$ROOT/rust/Cargo.toml" \
    -p qsoe-tm-script \
    --features host-tests

echo "check-tm-script-model.sh: ok"
