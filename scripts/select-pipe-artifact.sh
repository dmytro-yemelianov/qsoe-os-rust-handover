#!/usr/bin/env bash
#
# Stage the selected pipe manager at a stable path for later image packaging.
# The default is the existing C daemon; Rust is selected explicitly with
# QSOE_RUST_PIPE=1.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
QSOE_RUST_PIPE=${QSOE_RUST_PIPE:-0}
SELECTED_PIPE_ELF=${SELECTED_PIPE_ELF:-"$ROOT/build/rust/selected/sbin/pipe.elf"}
C_PIPE_ELF=${C_PIPE_ELF:-"$ROOT/quser/build/sbin/pipe/pipe.elf"}
RUST_PIPE_ELF=${RUST_PIPE_ELF:-"$ROOT/build/rust/qsoe-pipe-rs.elf"}

case "$QSOE_RUST_PIPE" in
    0|false|FALSE|no|NO)
        mode=c
        ;;
    1|true|TRUE|yes|YES)
        mode=rust
        ;;
    *)
        echo "select-pipe-artifact.sh: QSOE_RUST_PIPE must be 0 or 1" >&2
        exit 2
        ;;
esac

if [ "$mode" = rust ]; then
    RUST_PACKAGE=qsoe-pipe-rs \
        RUST_OUT="$RUST_PIPE_ELF" \
        "$ROOT/scripts/rust-qsoe-link-smoke.sh"
    src=$RUST_PIPE_ELF
else
    src=$C_PIPE_ELF
    if [ ! -f "$src" ]; then
        if [ -d "$ROOT/quser/sbin/pipe" ]; then
            "$MAKE" -C "$ROOT/quser/sbin/pipe" --no-print-directory
        fi
    fi
fi

if [ ! -f "$src" ]; then
    echo "select-pipe-artifact.sh: missing selected pipe ELF: $src" >&2
    if [ "$mode" = c ]; then
        echo "select-pipe-artifact.sh: build quser first or set C_PIPE_ELF=/path/pipe.elf" >&2
    fi
    exit 1
fi

mkdir -p "$(dirname "$SELECTED_PIPE_ELF")"
cp "$src" "$SELECTED_PIPE_ELF"
chmod 0755 "$SELECTED_PIPE_ELF"

echo "select-pipe-artifact.sh: selected $mode pipe -> $SELECTED_PIPE_ELF"
