#!/usr/bin/env bash
#
# Boot the tm_procfs Rust-default release-candidate image, or its C rollback,
# and verify taskman's /proc model through the selected provider.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-procfs-rc-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds and boots the tm_procfs release-candidate image. The RC default selects
the Rust qsoe-tm-procfs provider inside taskman. Set TM_PROCFS_RC_ROLLBACK=1
to prove the C rollback image through the same /proc smoke.

Environment:
  TM_PROCFS_RC_ROLLBACK  set 1 to select the C rollback provider
  PROCFS_SMOKE_WORKDIR   output directory, default build/tm-procfs-rc/<mode>
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
rollback=${TM_PROCFS_RC_ROLLBACK:-0}

case "$rollback" in
    0|false|FALSE|no|NO)
        export QSOE_RUST_TM_PROCFS=1
        mode=rust-default
        ;;
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_PROCFS=0
        mode=c-rollback
        ;;
    *)
        echo "tm-procfs-rc-smoke.sh: TM_PROCFS_RC_ROLLBACK must be 0 or 1" >&2
        exit 2
        ;;
esac

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

export PROCFS_SMOKE_WORKDIR=${PROCFS_SMOKE_WORKDIR:-"$ROOT/build/tm-procfs-rc/$mode"}

echo "tm-procfs-rc-smoke.sh: mode=$mode rollback=$rollback"
exec "$ROOT/scripts/procfs-smoke.sh" "$@"
