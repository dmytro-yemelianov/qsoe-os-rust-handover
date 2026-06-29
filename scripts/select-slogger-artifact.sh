#!/usr/bin/env bash
#
# Stage the selected slogger implementation at a stable path for later image
# packaging. The C daemon is retired; this always stages slogger-rs.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SELECTED_SLOGGER_ELF=${SELECTED_SLOGGER_ELF:-"$ROOT/build/rust/selected/sbin/slogger.elf"}
RUST_SLOGGER_ELF=${RUST_SLOGGER_ELF:-"$ROOT/build/rust/qsoe-slogger-rs.elf"}

case "${QSOE_RUST_SLOGGER:-1}" in
    1|true|TRUE|yes|YES)
        ;;
    0|false|FALSE|no|NO)
        echo "select-slogger-artifact.sh: C slogger is retired; use Rust slogger-rs" >&2
        exit 2
        ;;
    *)
        echo "select-slogger-artifact.sh: QSOE_RUST_SLOGGER must be 1 after C retirement" >&2
        exit 2
        ;;
esac

RUST_PACKAGE=qsoe-slogger-rs \
    RUST_OUT="$RUST_SLOGGER_ELF" \
    "$ROOT/scripts/rust-qsoe-link-smoke.sh"

if [ ! -f "$RUST_SLOGGER_ELF" ]; then
    echo "select-slogger-artifact.sh: missing Rust slogger ELF: $RUST_SLOGGER_ELF" >&2
    exit 1
fi

mkdir -p "$(dirname "$SELECTED_SLOGGER_ELF")"
cp "$RUST_SLOGGER_ELF" "$SELECTED_SLOGGER_ELF"
chmod 0755 "$SELECTED_SLOGGER_ELF"

echo "select-slogger-artifact.sh: selected rust slogger -> $SELECTED_SLOGGER_ELF"
