#!/usr/bin/env bash
#
# Run the host-side Rust tests for the retired portable tm_procfs model.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST="$ROOT/rust/Cargo.toml"

cargo test --manifest-path "$MANIFEST" -p qsoe-tm-procfs --features host-tests

echo "check-tm-procfs-model.sh: ok"
