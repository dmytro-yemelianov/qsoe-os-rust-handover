#!/usr/bin/env bash
#
# Validate the retired-C Rust-only mkfs-qrv writer path.

set -eu

usage() {
    cat <<'EOF_USAGE'
usage: scripts/mkfs-qrv-rc-live-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds the normal QSOE/L virtio qrvfs image with Rust mkfs-qrv-rs, then
reuses the virtio file-read smoke to prove the guest can mount /usr and read
/usr/conf/passwd from that image.

Environment:
  MKFS_QRV_RC_ROLLBACK       must remain unset/0 after C retirement
  QSOE_RUST_MKFS_QRV         must remain 1 after C retirement
  QSOE_RUST_VIRTIO           must remain 1 after C devb-virtio retirement
  MKFS_QRV_RC_WORKDIR        output directory, default build/mkfs-qrv-rc
EOF_USAGE
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)

has_log=0
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            usage
            exit 0
            ;;
        -o|--log)
            has_log=1
            ;;
        --)
            break
            ;;
    esac
done

workdir=${MKFS_QRV_RC_WORKDIR:-"$ROOT/build/mkfs-qrv-rc"}
rollback=${MKFS_QRV_RC_ROLLBACK:-0}

case "$rollback" in
    0)
        ;;
    1)
        echo "mkfs-qrv-rc-live-smoke.sh: C mkfs-qrv rollback is retired" >&2
        exit 2
        ;;
    *)
        echo "mkfs-qrv-rc-live-smoke.sh: MKFS_QRV_RC_ROLLBACK must be 0 after C retirement" >&2
        exit 2
        ;;
esac

QSOE_RUST_MKFS_QRV=${QSOE_RUST_MKFS_QRV:-1}
case "$QSOE_RUST_MKFS_QRV" in
    1|true|TRUE|yes|YES)
        mode=rust-only
        ;;
    0|false|FALSE|no|NO)
        echo "mkfs-qrv-rc-live-smoke.sh: C mkfs-qrv is retired; use Rust mkfs-qrv-rs" >&2
        exit 2
        ;;
    *)
        echo "mkfs-qrv-rc-live-smoke.sh: QSOE_RUST_MKFS_QRV must be 1 after C retirement" >&2
        exit 2
        ;;
esac

export QSOE_RUST_MKFS_QRV
export QSOE_RUST_VIRTIO=${QSOE_RUST_VIRTIO:-1}
export RUST_VIRTIO_FILE_WORKDIR=${RUST_VIRTIO_FILE_WORKDIR:-"$workdir"}
export RUST_VIRTIO_WORKDIR=${RUST_VIRTIO_WORKDIR:-"$workdir"}

mkdir -p "$workdir"

echo "mkfs-qrv-rc-live-smoke.sh: mode=$mode"
if [ "$has_log" -eq 1 ]; then
    exec "$ROOT/scripts/rust-virtio-file-smoke.sh" "$@"
fi

exec "$ROOT/scripts/rust-virtio-file-smoke.sh" \
    -o "$workdir/boot-smoke-lq-$mode-mkfs-qrv-rust-virtio-file.log" \
    "$@"
