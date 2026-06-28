#!/usr/bin/env bash
#
# Boot QSOE/L with a /usr qrvfs image written by Rust mkfs-qrv-rs.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/rust-mkfs-qrv-live-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds the normal virtio qrvfs image with Rust mkfs-qrv-rs selected, then
reuses the virtio file-read smoke to prove the guest can mount /usr and read
/usr/conf/passwd from the Rust-written image.

Environment:
  QSOE_RUST_VIRTIO             set 1 to combine with the Rust virtio driver;
                               default is 0 to isolate qrvfs writer evidence
  RUST_MKFS_QRV_LIVE_WORKDIR   output directory, default build/rust-mkfs-qrv-live
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
workdir=${RUST_MKFS_QRV_LIVE_WORKDIR:-"$ROOT/build/rust-mkfs-qrv-live"}

args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done

mkdir -p "$workdir"

export QSOE_RUST_MKFS_QRV=1
export QSOE_RUST_VIRTIO=${QSOE_RUST_VIRTIO:-0}
export RUST_VIRTIO_FILE_WORKDIR=${RUST_VIRTIO_FILE_WORKDIR:-"$workdir"}
export RUST_VIRTIO_WORKDIR=${RUST_VIRTIO_WORKDIR:-"$workdir"}

echo "rust-mkfs-qrv-live-smoke.sh: booting with Rust mkfs-qrv-rs image writer"
exec "$ROOT/scripts/rust-virtio-file-smoke.sh" "${args[@]}"
