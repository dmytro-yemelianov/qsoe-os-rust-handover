#!/usr/bin/env bash
#
# Generate host-side Rust coverage reports for parser and ABI crates.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST="$ROOT/rust/Cargo.toml"
OUTDIR=${QSOE_RUST_COVERAGE_DIR:-"$ROOT/build/rust-coverage"}

. "$ROOT/scripts/rust-env.sh"

packages=(
    -p qsoe-abi
    -p qsoe-cpio
    -p qsoe-elf
    -p qsoe-qrvfs
    -p qsoe-ressrv
    -p qsoe-sysview
)

usage() {
    cat <<'EOF'
usage: scripts/rust-coverage.sh

Generates host-side coverage reports for parser and ABI crates.

Outputs:
  build/rust-coverage/summary.txt
  build/rust-coverage/lcov.info
  build/rust-coverage/html/       when QSOE_RUST_COVERAGE_HTML=1

Environment:
  QSOE_RUST_COVERAGE_DIR          output directory, default build/rust-coverage
  QSOE_RUST_COVERAGE_HTML=1       also generate an HTML report
  QSOE_RUST_COVERAGE_REQUIRE=1    fail when cargo-llvm-cov is missing
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    '')
        ;;
    *)
        echo "rust-coverage.sh: unknown argument: $1" >&2
        usage >&2
        exit 2
        ;;
esac

if ! command -v cargo >/dev/null 2>&1; then
    echo "rust-coverage.sh: cargo not found" >&2
    exit 127
fi

if ! cargo llvm-cov --version >/dev/null 2>&1; then
    if [ "${QSOE_RUST_COVERAGE_REQUIRE:-0}" = "1" ]; then
        echo "rust-coverage.sh: cargo-llvm-cov is not installed" >&2
        echo "Install it with: cargo install cargo-llvm-cov" >&2
        exit 127
    fi
    echo "rust-coverage.sh: skipping; cargo-llvm-cov is not installed"
    exit 0
fi

qsoe_cargo_set_target_dir "$ROOT" coverage
mkdir -p "$OUTDIR"

cargo llvm-cov \
    --manifest-path "$MANIFEST" \
    "${packages[@]}" \
    --lib \
    > "$OUTDIR/summary.txt"

cargo llvm-cov \
    --manifest-path "$MANIFEST" \
    "${packages[@]}" \
    --lib \
    --lcov \
    --output-path "$OUTDIR/lcov.info"

if [ "${QSOE_RUST_COVERAGE_HTML:-0}" = "1" ]; then
    cargo llvm-cov \
        --manifest-path "$MANIFEST" \
        "${packages[@]}" \
        --lib \
        --html \
        --output-dir "$OUTDIR/html"
fi

echo "rust-coverage.sh: wrote $OUTDIR/summary.txt"
echo "rust-coverage.sh: wrote $OUTDIR/lcov.info"
if [ "${QSOE_RUST_COVERAGE_HTML:-0}" = "1" ]; then
    echo "rust-coverage.sh: wrote $OUTDIR/html/index.html"
fi
