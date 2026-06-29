#!/usr/bin/env bash
#
# Validate the Rust-default mkfs-qrv writer RC and the C rollback selector.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/mkfs-qrv-rc-live-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds the normal QSOE/L virtio qrvfs image with the selected mkfs-qrv writer,
then reuses the virtio file-read smoke to prove the guest can mount /usr and
read /usr/conf/passwd from that image.

Environment:
  MKFS_QRV_RC_ROLLBACK       set 1 to select C mkfs-qrv rollback
  QSOE_RUST_MKFS_QRV         defaults to 1 for the RC path
  QSOE_RUST_VIRTIO           defaults to 0 to isolate writer evidence
  MKFS_QRV_RC_WORKDIR        output directory, default build/mkfs-qrv-rc
EOF
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
        QSOE_RUST_MKFS_QRV=${QSOE_RUST_MKFS_QRV:-1}
        case "$QSOE_RUST_MKFS_QRV" in
            1)
                mode=rust-default
                ;;
            0)
                mode=c-selected
                ;;
            *)
                echo "mkfs-qrv-rc-live-smoke.sh: QSOE_RUST_MKFS_QRV must be 0 or 1" >&2
                exit 2
                ;;
        esac
        ;;
    1)
        QSOE_RUST_MKFS_QRV=0
        mode=c-rollback
        ;;
    *)
        echo "mkfs-qrv-rc-live-smoke.sh: MKFS_QRV_RC_ROLLBACK must be 0 or 1" >&2
        exit 2
        ;;
esac

export QSOE_RUST_MKFS_QRV
export QSOE_RUST_VIRTIO=${QSOE_RUST_VIRTIO:-0}
export RUST_VIRTIO_FILE_WORKDIR=${RUST_VIRTIO_FILE_WORKDIR:-"$workdir"}
export RUST_VIRTIO_WORKDIR=${RUST_VIRTIO_WORKDIR:-"$workdir"}

mkdir -p "$workdir"

echo "mkfs-qrv-rc-live-smoke.sh: mode=$mode rollback=$rollback"
if [ "$has_log" -eq 1 ]; then
    exec "$ROOT/scripts/rust-virtio-file-smoke.sh" "$@"
fi

exec "$ROOT/scripts/rust-virtio-file-smoke.sh" \
    -o "$workdir/boot-smoke-lq-$mode-mkfs-qrv-c-virtio-file.log" \
    "$@"
