#!/usr/bin/env bash
#
# Stage the selected pipe manager at a stable path for later image packaging.
# The C daemon is retired; this always stages pipe-rs.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SELECTED_PIPE_ELF=${SELECTED_PIPE_ELF:-"$ROOT/build/rust/selected/sbin/pipe.elf"}
RUST_PIPE_ELF=${RUST_PIPE_ELF:-"$ROOT/build/rust/qsoe-pipe-rs.elf"}

case "${QSOE_RUST_PIPE:-1}" in
    1|true|TRUE|yes|YES)
        ;;
    0|false|FALSE|no|NO)
        echo "select-pipe-artifact.sh: C pipe is retired; use Rust pipe-rs" >&2
        exit 2
        ;;
    *)
        echo "select-pipe-artifact.sh: QSOE_RUST_PIPE must be 1 after C retirement" >&2
        exit 2
        ;;
esac

RUST_PACKAGE=qsoe-pipe-rs \
    RUST_OUT="$RUST_PIPE_ELF" \
    "$ROOT/scripts/rust-qsoe-link-smoke.sh"

if [ ! -f "$RUST_PIPE_ELF" ]; then
    echo "select-pipe-artifact.sh: missing Rust pipe ELF: $RUST_PIPE_ELF" >&2
    exit 1
fi

mkdir -p "$(dirname "$SELECTED_PIPE_ELF")"
cp "$RUST_PIPE_ELF" "$SELECTED_PIPE_ELF"
chmod 0755 "$SELECTED_PIPE_ELF"

echo "select-pipe-artifact.sh: selected rust pipe -> $SELECTED_PIPE_ELF"
