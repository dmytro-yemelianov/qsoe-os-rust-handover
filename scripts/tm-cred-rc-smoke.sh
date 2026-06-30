#!/usr/bin/env bash
#
# Validate the retired tm_cred Rust selector.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-cred-rc-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds NQ and LQ taskman with the retired Rust tm_cred provider, verifies that
C cred.o is absent, then reuses the live tm_cred runtime smoke.

Environment:
  TM_CRED_RC_ROLLBACK  unsupported after C tm_cred retirement
  QSOE_RUST_TM_CRED    must remain 1 after C tm_cred retirement
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
        mode=rust-retired
        expected_cred_count=0
        ;;
    1|true|TRUE|yes|YES)
        echo "tm-cred-rc-smoke.sh: C tm_cred rollback is retired" >&2
        exit 2
        ;;
    *)
        echo "tm-cred-rc-smoke.sh: TM_CRED_RC_ROLLBACK must be 0 after C retirement" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_CRED:-1}" in
    1|true|TRUE|yes|YES)
        selected=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-cred-rc-smoke.sh: C tm_cred is retired; QSOE_RUST_TM_CRED must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-cred-rc-smoke.sh: QSOE_RUST_TM_CRED must be 1 after C retirement" >&2
        exit 2
        ;;
esac

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

exec "$ROOT/scripts/tm-cred-runtime-smoke.sh" "${runtime_args[@]}"
