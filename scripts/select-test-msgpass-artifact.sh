#!/usr/bin/env bash
#
# Stage the selected test_msgpass helper at a stable path for test-image
# packaging. The default is the existing C helper; Rust is selected explicitly
# with QSOE_RUST_TEST_MSGPASS=1.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
QSOE_RUST_TEST_MSGPASS=${QSOE_RUST_TEST_MSGPASS:-0}
SELECTED_TEST_MSGPASS_ELF=${SELECTED_TEST_MSGPASS_ELF:-"$ROOT/build/rust/selected/usr/bin/test_msgpass.elf"}
C_TEST_MSGPASS_ELF=${C_TEST_MSGPASS_ELF:-"$ROOT/quser/build/test/msgpass/test_msgpass.elf"}
RUST_TEST_MSGPASS_ELF=${RUST_TEST_MSGPASS_ELF:-"$ROOT/build/rust/qsoe-test-msgpass-rs.elf"}

case "$QSOE_RUST_TEST_MSGPASS" in
    0|false|FALSE|no|NO)
        mode=c
        ;;
    1|true|TRUE|yes|YES)
        mode=rust
        ;;
    *)
        echo "select-test-msgpass-artifact.sh: QSOE_RUST_TEST_MSGPASS must be 0 or 1" >&2
        exit 2
        ;;
esac

if [ "$mode" = rust ]; then
    RUST_PACKAGE=qsoe-test-msgpass-rs \
        RUST_OUT="$RUST_TEST_MSGPASS_ELF" \
        "$ROOT/scripts/rust-qsoe-link-smoke.sh"
    src=$RUST_TEST_MSGPASS_ELF
else
    src=$C_TEST_MSGPASS_ELF
    if [ ! -f "$src" ]; then
        if [ -d "$ROOT/quser/test/msgpass" ]; then
            "$MAKE" -C "$ROOT/quser/test/msgpass" --no-print-directory
        fi
    fi
fi

if [ ! -f "$src" ]; then
    echo "select-test-msgpass-artifact.sh: missing selected test_msgpass ELF: $src" >&2
    if [ "$mode" = c ]; then
        echo "select-test-msgpass-artifact.sh: build quser first or set C_TEST_MSGPASS_ELF=/path/test_msgpass.elf" >&2
    fi
    exit 1
fi

mkdir -p "$(dirname "$SELECTED_TEST_MSGPASS_ELF")"
cp "$src" "$SELECTED_TEST_MSGPASS_ELF"
chmod 0755 "$SELECTED_TEST_MSGPASS_ELF"

echo "select-test-msgpass-artifact.sh: selected $mode test_msgpass -> $SELECTED_TEST_MSGPASS_ELF"
