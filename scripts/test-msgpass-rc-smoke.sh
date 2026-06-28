#!/usr/bin/env bash
#
# Boot the test_msgpass Rust-default release-candidate image, or its C
# rollback, and verify the existing suite [msgpass] path.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/test-msgpass-rc-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds and boots the test_msgpass release-candidate image. The RC default
selects test_msgpass-rs at /usr/bin/test_msgpass in the temporary qrvfs test
image. Set QSOE_TEST_MSGPASS_RC_ROLLBACK=1 to prove the C rollback image
through the same suite [msgpass] smoke.

Environment:
  QSOE_TEST_MSGPASS_RC_ROLLBACK  set 1 to select the C rollback artifact
  RUST_TEST_MSGPASS_WORKDIR      output directory, default build/test-msgpass-rc
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
rollback=${QSOE_TEST_MSGPASS_RC_ROLLBACK:-0}

case "$rollback" in
    0|false|FALSE|no|NO)
        export QSOE_RUST_TEST_MSGPASS=1
        mode=rust-default
        ;;
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TEST_MSGPASS=0
        mode=c-rollback
        ;;
    *)
        echo "test-msgpass-rc-smoke.sh: QSOE_TEST_MSGPASS_RC_ROLLBACK must be 0 or 1" >&2
        exit 2
        ;;
esac

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

export RUST_TEST_MSGPASS_WORKDIR=${RUST_TEST_MSGPASS_WORKDIR:-"$ROOT/build/test-msgpass-rc"}

echo "test-msgpass-rc-smoke.sh: mode=$mode rollback=$rollback"
exec "$ROOT/scripts/rust-test-msgpass-smoke.sh" "$@"
