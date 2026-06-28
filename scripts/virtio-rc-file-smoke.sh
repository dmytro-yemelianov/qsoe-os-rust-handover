#!/usr/bin/env bash
#
# Boot the devb-virtio Rust-default release-candidate image, or its C
# rollback, and verify /usr file reads through the selected /sbin/devb-virtio.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/virtio-rc-file-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds and boots the devb-virtio release-candidate image. The RC default
selects devb-virtio-rs at /sbin/devb-virtio in the temporary boot CPIO. Set
QSOE_VIRTIO_RC_ROLLBACK=1 to prove the C rollback image through the same /usr
file-read smoke.

Environment:
  QSOE_VIRTIO_RC_ROLLBACK  set 1 to select the C rollback artifact
  RUST_VIRTIO_FILE_WORKDIR output directory, default build/virtio-rc
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
rollback=${QSOE_VIRTIO_RC_ROLLBACK:-0}

case "$rollback" in
    0|false|FALSE|no|NO)
        export QSOE_RUST_VIRTIO=1
        mode=rust-default
        ;;
    1|true|TRUE|yes|YES)
        export QSOE_RUST_VIRTIO=0
        mode=c-rollback
        ;;
    *)
        echo "virtio-rc-file-smoke.sh: QSOE_VIRTIO_RC_ROLLBACK must be 0 or 1" >&2
        exit 2
        ;;
esac

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

export RUST_VIRTIO_FILE_WORKDIR=${RUST_VIRTIO_FILE_WORKDIR:-"$ROOT/build/virtio-rc"}
export RUST_VIRTIO_WORKDIR=${RUST_VIRTIO_WORKDIR:-"$ROOT/build/virtio-rc"}

echo "virtio-rc-file-smoke.sh: mode=$mode rollback=$rollback"
exec "$ROOT/scripts/rust-virtio-file-smoke.sh" "$@"
