#!/usr/bin/env bash
#
# Boot the retired pipe Rust image and verify pipe(2) data flow through
# /sbin/pipe.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/pipe-rc-data-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds and boots the retired pipe image. The image selects pipe-rs at
/sbin/pipe. C pipe rollback is retired and no longer selectable.

Environment:
  QSOE_PIPE_RC_ROLLBACK   unsupported after C retirement
  RUST_PIPE_DATA_WORKDIR  output directory, default build/pipe-rc
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
rollback=${QSOE_PIPE_RC_ROLLBACK:-0}

case "$rollback" in
    0|false|FALSE|no|NO)
        export QSOE_RUST_PIPE=1
        mode=rust-retired
        ;;
    1|true|TRUE|yes|YES)
        echo "pipe-rc-data-smoke.sh: C pipe rollback is retired" >&2
        exit 2
        ;;
    *)
        echo "pipe-rc-data-smoke.sh: QSOE_PIPE_RC_ROLLBACK must be 0 after C retirement" >&2
        exit 2
        ;;
esac

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

export RUST_PIPE_DATA_WORKDIR=${RUST_PIPE_DATA_WORKDIR:-"$ROOT/build/pipe-rc"}

echo "pipe-rc-data-smoke.sh: mode=$mode rollback=$rollback"
exec "$ROOT/scripts/rust-pipe-data-smoke.sh" "$@"
