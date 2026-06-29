#!/usr/bin/env bash
#
# Tiered Rust workflow entry point for QSOE migration work.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST="$ROOT/rust/Cargo.toml"
MODE=${1:-}

. "$ROOT/scripts/rust-env.sh"

usage() {
    cat <<EOF
usage: scripts/rust-workflow.sh <mode>

modes:
  fast      cargo check plus focused host tests
  quality   formatting, clippy, and host tests
  abi       QSOE userland link smoke and strict ELF audit
  deep      optional deeper checks when local tools are installed

environment:
  CARGO_TARGET_DIR          override generated artifact directory
  QSOE_RUST_DEEP_REQUIRE=1  fail deep mode if optional tools are missing
  QSOE_RUST_FUZZ_REQUIRE=1  fail fuzz smoke if nightly cargo-fuzz is missing
  QSOE_RUST_COVERAGE_REQUIRE=1 fail coverage if cargo-llvm-cov is missing
EOF
}

need_cargo() {
    if ! command -v cargo >/dev/null 2>&1; then
        echo "rust-workflow.sh: cargo not found" >&2
        exit 127
    fi
}

run_optional() {
    name=$1
    shift

    if "$@" --version >/dev/null 2>&1; then
        echo "rust-workflow.sh: running $name"
        return 0
    fi

    echo "rust-workflow.sh: skipping $name; tool not installed"
    return 1
}

run_fast() {
    need_cargo
    qsoe_cargo_set_target_dir "$ROOT" host

    cargo check --manifest-path "$MANIFEST" --workspace
    cargo test --manifest-path "$MANIFEST" \
        -p qsoe-abi \
        -p qsoe-cpio \
        -p qsoe-elf \
        -p qsoe-ressrv \
        -p qsoe-slogger \
        -p qsoe-sysview \
        -p qsoe-qrvfs \
        --lib
    cargo test --manifest-path "$MANIFEST" -p qsoe-minimal-rs --features host-tests --lib
    cargo test --manifest-path "$MANIFEST" -p qsoe-tm-cpio --features host-tests --lib
    cargo test --manifest-path "$MANIFEST" -p qsoe-tm-cred --features host-tests --lib
    cargo test --manifest-path "$MANIFEST" -p qsoe-tm-pseudodev --features host-tests --lib
    cargo test --manifest-path "$MANIFEST" -p qsoe-tm-procfs --features host-tests --lib
    cargo test --manifest-path "$MANIFEST" -p qsoe-tm-script --features host-tests --lib
    cargo test --manifest-path "$MANIFEST" -p qsoe-tm-sysfs --features host-tests --lib
}

run_deep() {
    need_cargo
    qsoe_cargo_set_target_dir "$ROOT" host

    cargo doc --manifest-path "$MANIFEST" --workspace --no-deps

    ran_optional=0

    if run_optional "cargo-nextest" cargo nextest; then
        cargo nextest run --manifest-path "$MANIFEST" --workspace
        ran_optional=1
    else
        cargo test --manifest-path "$MANIFEST" \
            -p qsoe-abi \
            -p qsoe-cpio \
            -p qsoe-elf \
            -p qsoe-ressrv \
            -p qsoe-slogger \
            -p qsoe-sysview \
            -p qsoe-qrvfs
        cargo test --manifest-path "$MANIFEST" -p qsoe-minimal-rs --features host-tests
        cargo test --manifest-path "$MANIFEST" -p qsoe-tm-cpio --features host-tests
        cargo test --manifest-path "$MANIFEST" -p qsoe-tm-cred --features host-tests
        cargo test --manifest-path "$MANIFEST" -p qsoe-tm-pseudodev --features host-tests
        cargo test --manifest-path "$MANIFEST" -p qsoe-tm-procfs --features host-tests
        cargo test --manifest-path "$MANIFEST" -p qsoe-tm-script --features host-tests
        cargo test --manifest-path "$MANIFEST" -p qsoe-tm-sysfs --features host-tests
    fi

    if run_optional "cargo-miri" cargo miri; then
        cargo miri test --manifest-path "$MANIFEST" \
            -p qsoe-abi \
            -p qsoe-cpio \
            -p qsoe-elf \
            -p qsoe-qrvfs \
            -p qsoe-sysview
        ran_optional=1
    fi

    if run_optional "cargo-deny" cargo deny; then
        cargo deny --manifest-path "$MANIFEST" check -c "$ROOT/rust/deny.toml"
        ran_optional=1
    fi

    if run_optional "cargo-fuzz" cargo +nightly fuzz; then
        "$ROOT/scripts/rust-fuzz-smoke.sh"
        ran_optional=1
    fi

    if run_optional "cargo-llvm-cov" cargo llvm-cov; then
        "$ROOT/scripts/rust-coverage.sh"
        ran_optional=1
    fi

    if [ "$ran_optional" -eq 0 ] && [ "${QSOE_RUST_DEEP_REQUIRE:-0}" = "1" ]; then
        echo "rust-workflow.sh: no optional deep tools were available" >&2
        exit 1
    fi
}

case "$MODE" in
    fast)
        run_fast
        ;;
    quality)
        exec "$ROOT/scripts/rust-check.sh"
        ;;
    abi)
        exec "$ROOT/scripts/rust-qsoe-link-smoke.sh"
        ;;
    deep)
        run_deep
        ;;
    -h|--help|help|'')
        usage
        ;;
    *)
        echo "rust-workflow.sh: unknown mode: $MODE" >&2
        usage >&2
        exit 2
        ;;
esac
