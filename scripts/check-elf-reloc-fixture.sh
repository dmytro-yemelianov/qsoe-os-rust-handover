#!/usr/bin/env bash
#
# Verify that the Rust ELF inspector identifies relocation types in built QSOE
# userland artifacts.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST="$ROOT/rust/Cargo.toml"

. "$ROOT/scripts/rust-env.sh"
qsoe_cargo_set_target_dir "$ROOT" host

if ! command -v cargo >/dev/null 2>&1; then
    echo "check-elf-reloc-fixture.sh: cargo not found" >&2
    exit 127
fi

QSOE_ELF_FIXTURES_REQUIRED=1 \
    cargo test \
        --manifest-path "$MANIFEST" \
        -p qsoe-elf \
        tests::identifies_relocation_types_used_by_existing_qsoe_binaries \
        -- --exact

echo "check-elf-reloc-fixture.sh: ok"
