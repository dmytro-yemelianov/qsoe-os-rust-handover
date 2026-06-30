#!/usr/bin/env bash
#
# Run the Rust host-side model for LQ taskman's sysmap ABI.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

cargo test --manifest-path "$ROOT/rust/Cargo.toml" -p qsoe-tm-sysmap --features host-tests --lib

echo "check-tm-sysmap-model.sh: ok"
