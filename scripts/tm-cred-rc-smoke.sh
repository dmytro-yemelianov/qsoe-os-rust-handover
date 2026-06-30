#!/usr/bin/env bash
#
# Validate the tm_cred Rust-default RC selector while keeping C rollback alive.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-cred-rc-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds NQ and LQ taskman with the tm_cred RC selection, verifies cred.o archive
membership, then reuses the live tm_cred runtime smoke.

Environment:
  TM_CRED_RC_ROLLBACK  set to 1 to validate the C rollback path
  QSOE_RUST_TM_CRED    default 1 for Rust RC; set 0 only for rollback validation
  TM_CRED_RC_WORKDIR   output directory, default build/tm-cred-rc
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
workdir=${TM_CRED_RC_WORKDIR:-"$ROOT/build/tm-cred-rc"}
rollback=${TM_CRED_RC_ROLLBACK:-0}
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

find_tool() {
    local tool
    for tool in "$@"; do
        if command -v "$tool" >/dev/null 2>&1; then
            command -v "$tool"
            return 0
        fi
    done
    return 1
}

AR=$(find_tool riscv64-linux-gnu-ar ar llvm-ar) || {
    echo "tm-cred-rc-smoke.sh: no ar tool found" >&2
    exit 127
}

fail() {
    echo "tm-cred-rc-smoke.sh: $*" >&2
    exit 1
}

object_count() {
    local archive=$1
    local object=$2

    "$AR" t "$archive" |
        awk -v object="$object" '$0 == object { n++ } END { print n + 0 }'
}

require_cred_count() {
    local label=$1
    local archive=$2
    local expected=$3
    local count

    [ -f "$archive" ] || fail "missing archive for $label: $archive"
    count=$(object_count "$archive" cred.o)
    printf '%s cred.o count: %s\n' "$label" "$count" |
        tee "$workdir/$label-cred-membership.txt"
    [ "$count" -eq "$expected" ] ||
        fail "$label expected $expected cred.o members, got $count"
}

mkdir -p "$workdir"
"$ROOT/scripts/apply-component-overrides.sh"

case "$rollback" in
    0|false|FALSE|no|NO)
        rollback=0
        default_selected=1
        ;;
    1|true|TRUE|yes|YES)
        rollback=1
        default_selected=0
        ;;
    *)
        echo "tm-cred-rc-smoke.sh: TM_CRED_RC_ROLLBACK must be 0 or 1" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_CRED:-$default_selected}" in
    1|true|TRUE|yes|YES)
        selected=1
        mode=rust-default
        expected_cred_count=0
        ;;
    0|false|FALSE|no|NO)
        selected=0
        mode=c-rollback
        expected_cred_count=1
        ;;
    *)
        echo "tm-cred-rc-smoke.sh: QSOE_RUST_TM_CRED must be 0 or 1" >&2
        exit 2
        ;;
esac

if [ "$rollback" -eq 1 ] && [ "$selected" -ne 0 ]; then
    echo "tm-cred-rc-smoke.sh: TM_CRED_RC_ROLLBACK=1 requires QSOE_RUST_TM_CRED=0" >&2
    exit 2
fi

echo "tm-cred-rc-smoke.sh: mode=$mode rollback=$rollback"

echo "tm-cred-rc-smoke.sh: verifying NQ taskman selector"
"$MAKE" -C "$ROOT/nq/taskman" --no-print-directory \
    QSOE_RUST_TM_CRED="$selected" \
    QSOE_RUST_TM_PROCFS=1
require_cred_count "nq-$mode" "$ROOT/nq/build/libtaskman/libtaskman.a" "$expected_cred_count"

echo "tm-cred-rc-smoke.sh: verifying LQ taskman selector"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_CRED="$selected" \
    QSOE_RUST_TM_PROCFS=1 \
    taskman
require_cred_count "lq-$mode" "$ROOT/lq/build/libtaskman/libtaskman.a" "$expected_cred_count"

runtime_args=("$@")
if [ "$has_log" -eq 0 ]; then
    runtime_args=(-o "$workdir/boot-smoke-lq-tm-cred-rc-$mode.log" "${runtime_args[@]}")
fi

export QSOE_RUST_TM_CRED="$selected"
export QSOE_RUST_TM_PROCFS=1
export TM_CRED_RUNTIME_SMOKE_WORKDIR="$workdir"
if [ "$selected" -eq 0 ]; then
    export TM_CRED_RUNTIME_ALLOW_C=1
fi

exec "$ROOT/scripts/tm-cred-runtime-smoke.sh" "${runtime_args[@]}"
