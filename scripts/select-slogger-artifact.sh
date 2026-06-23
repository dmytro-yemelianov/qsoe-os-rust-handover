#!/usr/bin/env bash
#
# Stage the selected slogger implementation at a stable path for later image
# packaging. The default is the existing C daemon; Rust is selected explicitly
# with QSOE_RUST_SLOGGER=1.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
QSOE_RUST_SLOGGER=${QSOE_RUST_SLOGGER:-0}
SELECTED_SLOGGER_ELF=${SELECTED_SLOGGER_ELF:-"$ROOT/build/rust/selected/sbin/slogger.elf"}
C_SLOGGER_ELF=${C_SLOGGER_ELF:-"$ROOT/quser/build/sbin/slogger/slogger.elf"}
RUST_SLOGGER_ELF=${RUST_SLOGGER_ELF:-"$ROOT/build/rust/qsoe-slogger-rs.elf"}

case "$QSOE_RUST_SLOGGER" in
    0|false|FALSE|no|NO)
        mode=c
        ;;
    1|true|TRUE|yes|YES)
        mode=rust
        ;;
    *)
        echo "select-slogger-artifact.sh: QSOE_RUST_SLOGGER must be 0 or 1" >&2
        exit 2
        ;;
esac

if [ "$mode" = rust ]; then
    RUST_PACKAGE=qsoe-slogger-rs \
        RUST_OUT="$RUST_SLOGGER_ELF" \
        "$ROOT/scripts/rust-qsoe-link-smoke.sh"
    src=$RUST_SLOGGER_ELF
else
    src=$C_SLOGGER_ELF
    if [ ! -f "$src" ]; then
        if [ -d "$ROOT/quser/sbin/slogger" ]; then
            "$MAKE" -C "$ROOT/quser/sbin/slogger" --no-print-directory
        fi
    fi
fi

if [ ! -f "$src" ]; then
    echo "select-slogger-artifact.sh: missing selected slogger ELF: $src" >&2
    if [ "$mode" = c ]; then
        echo "select-slogger-artifact.sh: build quser first or set C_SLOGGER_ELF=/path/slogger.elf" >&2
    fi
    exit 1
fi

mkdir -p "$(dirname "$SELECTED_SLOGGER_ELF")"
cp "$src" "$SELECTED_SLOGGER_ELF"
chmod 0755 "$SELECTED_SLOGGER_ELF"

echo "select-slogger-artifact.sh: selected $mode slogger -> $SELECTED_SLOGGER_ELF"
