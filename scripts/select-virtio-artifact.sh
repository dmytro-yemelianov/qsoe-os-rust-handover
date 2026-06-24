#!/usr/bin/env bash
#
# Stage the selected virtio block driver at a stable path for later image
# packaging. The default is the existing C driver; Rust is selected explicitly
# with QSOE_RUST_VIRTIO=1.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
QSOE_RUST_VIRTIO=${QSOE_RUST_VIRTIO:-0}
SELECTED_VIRTIO_ELF=${SELECTED_VIRTIO_ELF:-"$ROOT/build/rust/selected/sbin/devb-virtio.elf"}
C_VIRTIO_ELF=${C_VIRTIO_ELF:-"$ROOT/quser/build/dev/virtio/devb-virtio.elf"}
RUST_VIRTIO_ELF=${RUST_VIRTIO_ELF:-"$ROOT/build/rust/qsoe-devb-virtio-rs.elf"}
RESSRV_DIR=${RESSRV_DIR:-"$ROOT/quser/build/ressrv"}

case "$QSOE_RUST_VIRTIO" in
    0|false|FALSE|no|NO)
        mode=c
        ;;
    1|true|TRUE|yes|YES)
        mode=rust
        ;;
    *)
        echo "select-virtio-artifact.sh: QSOE_RUST_VIRTIO must be 0 or 1" >&2
        exit 2
        ;;
esac

if [ "$mode" = rust ]; then
    "$MAKE" -C "$ROOT/quser/ressrv" --no-print-directory
    RUST_PACKAGE=qsoe-devb-virtio-rs \
        RUST_OUT="$RUST_VIRTIO_ELF" \
        RUST_EXTRA_LDFLAGS="-L$RESSRV_DIR" \
        RUST_EXTRA_LDLIBS="-lressrv" \
        "$ROOT/scripts/rust-qsoe-link-smoke.sh"
    src=$RUST_VIRTIO_ELF
else
    src=$C_VIRTIO_ELF
    if [ ! -f "$src" ]; then
        if [ -d "$ROOT/quser/dev/virtio" ]; then
            "$MAKE" -C "$ROOT/quser/dev/virtio" --no-print-directory
        fi
    fi
fi

if [ ! -f "$src" ]; then
    echo "select-virtio-artifact.sh: missing selected virtio ELF: $src" >&2
    if [ "$mode" = c ]; then
        echo "select-virtio-artifact.sh: build quser first or set C_VIRTIO_ELF=/path/devb-virtio.elf" >&2
    fi
    exit 1
fi

mkdir -p "$(dirname "$SELECTED_VIRTIO_ELF")"
cp "$src" "$SELECTED_VIRTIO_ELF"
chmod 0755 "$SELECTED_VIRTIO_ELF"

echo "select-virtio-artifact.sh: selected $mode virtio -> $SELECTED_VIRTIO_ELF"
