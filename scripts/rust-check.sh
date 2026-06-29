#!/usr/bin/env bash
#
# Rust workspace checks for the QSOE migration spike.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST="$ROOT/rust/Cargo.toml"
RUST_TARGET=${RUST_TARGET:-riscv64gc-unknown-none-elf}

. "$ROOT/scripts/rust-env.sh"
qsoe_cargo_set_target_dir "$ROOT" host

if ! command -v cargo >/dev/null 2>&1; then
    echo "rust-check.sh: cargo not found" >&2
    exit 127
fi

cargo fmt --manifest-path "$MANIFEST" --all --check
cargo check --manifest-path "$MANIFEST" --workspace
cargo clippy --manifest-path "$MANIFEST" --workspace -- -D warnings
cargo test --manifest-path "$MANIFEST" \
    -p qsoe-abi \
    -p qsoe-cpio \
    -p qsoe-elf \
    -p qsoe-ressrv \
    -p qsoe-qrvfs \
    -p qsoe-slogger \
    -p qsoe-sysview

cargo test --manifest-path "$MANIFEST" -p qsoe-minimal-rs --features host-tests
cargo test --manifest-path "$MANIFEST" -p qsoe-tm-cred --features host-tests
cargo test --manifest-path "$MANIFEST" -p qsoe-tm-procfs --features host-tests
cargo test --manifest-path "$MANIFEST" -p qsoe-virtio
cargo test --manifest-path "$MANIFEST" -p qsoe-service-example-rs --features host-tests

if [ "${QSOE_RUST_COMPILE:-0}" = "1" ]; then
    if ! rustup target list --installed 2>/dev/null | grep -Fxq "$RUST_TARGET"; then
        echo "rust-check.sh: Rust target not installed: $RUST_TARGET" >&2
        echo "Install it with: rustup target add $RUST_TARGET" >&2
        exit 1
    fi

    cargo build \
        --manifest-path "$MANIFEST" \
        -p qsoe-minimal-rs \
        --target "$RUST_TARGET" \
        --release
else
    echo "rust-check.sh: RISC-V compile skipped; set QSOE_RUST_COMPILE=1 to enable"
fi
