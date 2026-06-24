#!/usr/bin/env bash
#
# Run a bounded cargo-fuzz smoke over parser fuzz targets.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FUZZ_RUNS=${QSOE_RUST_FUZZ_RUNS:-256}
FUZZ_SECONDS=${QSOE_RUST_FUZZ_SECONDS:-10}
FUZZ_MAX_LEN=${QSOE_RUST_FUZZ_MAX_LEN:-4096}
targets=("$@")

usage() {
    cat <<'EOF'
usage: scripts/rust-fuzz-smoke.sh [target...]

Runs cargo-fuzz for a bounded number of iterations on parser fuzz targets.
If no targets are supplied, all checked-in parser targets are run.

Environment:
  QSOE_RUST_FUZZ_RUNS       libFuzzer -runs value, default 256
  QSOE_RUST_FUZZ_SECONDS    libFuzzer -max_total_time value, default 10
  QSOE_RUST_FUZZ_MAX_LEN    libFuzzer -max_len value, default 4096
  QSOE_RUST_FUZZ_REQUIRE=1  fail when nightly cargo-fuzz is not available
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

if [ "${#targets[@]}" -eq 0 ]; then
    targets=(qrvfs cpio elf syscfg sysmap)
fi

if ! command -v cargo >/dev/null 2>&1; then
    echo "rust-fuzz-smoke.sh: cargo not found" >&2
    exit 127
fi

fuzz_cargo=(cargo +nightly)

if ! "${fuzz_cargo[@]}" fuzz --version >/dev/null 2>&1; then
    if [ "${QSOE_RUST_FUZZ_REQUIRE:-0}" = "1" ]; then
        echo "rust-fuzz-smoke.sh: nightly cargo-fuzz is not available" >&2
        echo "Install with: rustup toolchain install nightly && cargo install cargo-fuzz" >&2
        exit 127
    fi
    echo "rust-fuzz-smoke.sh: skipping; nightly cargo-fuzz is not available"
    exit 0
fi

cd "$ROOT/rust"

for target in "${targets[@]}"; do
    echo "rust-fuzz-smoke.sh: fuzz smoke $target"
    "${fuzz_cargo[@]}" fuzz run "$target" -- \
        -runs="$FUZZ_RUNS" \
        -max_total_time="$FUZZ_SECONDS" \
        -max_len="$FUZZ_MAX_LEN"
done
