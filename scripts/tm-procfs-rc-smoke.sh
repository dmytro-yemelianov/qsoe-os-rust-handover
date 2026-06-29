#!/usr/bin/env bash
#
# Boot the retired tm_procfs Rust image and verify taskman's /proc model.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-procfs-rc-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds and boots the retired tm_procfs image. The image selects the Rust
qsoe-tm-procfs provider inside taskman. C tm_procfs rollback is retired and no
longer selectable.

Environment:
  TM_PROCFS_RC_ROLLBACK  unsupported after C retirement
  PROCFS_SMOKE_WORKDIR   output directory, default build/tm-procfs-rc
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
rollback=${TM_PROCFS_RC_ROLLBACK:-0}

case "$rollback" in
    0|false|FALSE|no|NO)
        export QSOE_RUST_TM_PROCFS=1
        mode=rust-retired
        ;;
    1|true|TRUE|yes|YES)
        echo "tm-procfs-rc-smoke.sh: C tm_procfs rollback is retired" >&2
        exit 2
        ;;
    *)
        echo "tm-procfs-rc-smoke.sh: TM_PROCFS_RC_ROLLBACK must be 0 after C retirement" >&2
        exit 2
        ;;
esac

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

export PROCFS_SMOKE_WORKDIR=${PROCFS_SMOKE_WORKDIR:-"$ROOT/build/tm-procfs-rc"}

echo "tm-procfs-rc-smoke.sh: mode=$mode rollback=$rollback"
exec "$ROOT/scripts/procfs-smoke.sh" "$@"
