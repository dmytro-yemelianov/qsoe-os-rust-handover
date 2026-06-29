#!/usr/bin/env bash
#
# Boot the retired slogger Rust image.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/slogger-rc-boot-smoke.sh [-t seconds] [-o log] [--prepare-only] [--keep-running] [-- <emu args>]

Builds and boots the retired slogger image. The image selects slogger-rs at
/sbin/slogger. C slogger rollback is retired and no longer selectable.

Environment:
  QSOE_SLOGGER_RC_ROLLBACK  unsupported after C retirement
  RUST_SLOGGER_WORKDIR      output directory, default build/slogger-rc
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
rollback=${QSOE_SLOGGER_RC_ROLLBACK:-0}

case "$rollback" in
    0|false|FALSE|no|NO)
        export QSOE_RUST_SLOGGER=1
        mode=rust-retired
        ;;
    1|true|TRUE|yes|YES)
        echo "slogger-rc-boot-smoke.sh: C slogger rollback is retired" >&2
        exit 2
        ;;
    *)
        echo "slogger-rc-boot-smoke.sh: QSOE_SLOGGER_RC_ROLLBACK must be 0 after C retirement" >&2
        exit 2
        ;;
esac

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

export RUST_SLOGGER_WORKDIR=${RUST_SLOGGER_WORKDIR:-"$ROOT/build/slogger-rc"}

echo "slogger-rc-boot-smoke.sh: mode=$mode rollback=$rollback"
exec "$ROOT/scripts/rust-slogger-boot-smoke.sh" "$@"
