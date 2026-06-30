#!/usr/bin/env bash
#
# Validate the retired tm_pathmgr Rust selector.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-pathmgr-rc-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds NQ and LQ taskman with the retired Rust tm_pathmgr provider, verifies
that C pathmgr.o is absent, then reuses the live LQ tm_pathmgr runtime smoke.

Environment:
  TM_PATHMGR_RC_ROLLBACK  unsupported after C tm_pathmgr retirement
  QSOE_RUST_TM_PATHMGR    must remain 1 after C tm_pathmgr retirement
  TM_PATHMGR_RC_WORKDIR   output directory, default build/tm-pathmgr-rc
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
workdir=${TM_PATHMGR_RC_WORKDIR:-"$ROOT/build/tm-pathmgr-rc"}
rollback=${TM_PATHMGR_RC_ROLLBACK:-0}
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

fail() {
    echo "tm-pathmgr-rc-smoke.sh: $*" >&2
    exit 1
}

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
    echo "tm-pathmgr-rc-smoke.sh: no ar tool found" >&2
    exit 127
}

object_count() {
    local archive=$1
    local object=$2

    "$AR" t "$archive" |
        awk -v object="$object" '$0 == object { n++ } END { print n + 0 }'
}

require_pathmgr_count() {
    local label=$1
    local archive=$2
    local expected=$3
    local count

    [ -f "$archive" ] || fail "missing archive for $label: $archive"
    count=$(object_count "$archive" pathmgr.o)
    printf '%s pathmgr.o count: %s\n' "$label" "$count" |
        tee "$workdir/$label-pathmgr-membership.txt"
    [ "$count" -eq "$expected" ] ||
        fail "$label expected $expected pathmgr.o members, got $count"
}

mkdir -p "$workdir"
"$ROOT/scripts/apply-component-overrides.sh"

case "$rollback" in
    0|false|FALSE|no|NO)
        mode=rust-retired
        expected_pathmgr_count=0
        ;;
    1|true|TRUE|yes|YES)
        echo "tm-pathmgr-rc-smoke.sh: C tm_pathmgr rollback is retired" >&2
        exit 2
        ;;
    *)
        echo "tm-pathmgr-rc-smoke.sh: TM_PATHMGR_RC_ROLLBACK must be 0 after C retirement" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_PATHMGR:-1}" in
    1|true|TRUE|yes|YES)
        selected=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-pathmgr-rc-smoke.sh: C tm_pathmgr is retired; QSOE_RUST_TM_PATHMGR must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-pathmgr-rc-smoke.sh: QSOE_RUST_TM_PATHMGR must be 1 after C retirement" >&2
        exit 2
        ;;
esac

echo "tm-pathmgr-rc-smoke.sh: mode=$mode rollback=$rollback"

echo "tm-pathmgr-rc-smoke.sh: verifying NQ taskman selector"
"$MAKE" -C "$ROOT/nq/taskman" --no-print-directory \
    QSOE_RUST_TM_PATHMGR="$selected" \
    QSOE_RUST_TM_PROCFS=1
require_pathmgr_count "nq-$mode" "$ROOT/nq/build/libtaskman/libtaskman.a" "$expected_pathmgr_count"

echo "tm-pathmgr-rc-smoke.sh: verifying LQ taskman selector"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_PATHMGR="$selected" \
    QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_PSEUDODEV=1 \
    QSOE_RUST_TM_RSRCDB=1 \
    taskman
require_pathmgr_count "lq-$mode" "$ROOT/lq/build/libtaskman/libtaskman.a" "$expected_pathmgr_count"

runtime_args=("$@")
if [ "$has_log" -eq 0 ]; then
    runtime_args=(-o "$workdir/boot-smoke-lq-tm-pathmgr-rc-$mode.log" "${runtime_args[@]}")
fi

export QSOE_RUST_TM_PATHMGR="$selected"
export QSOE_RUST_TM_PROCFS=1
export QSOE_RUST_TM_PSEUDODEV=1
export QSOE_RUST_TM_RSRCDB=1
export TM_PATHMGR_RUNTIME_SMOKE_WORKDIR="$workdir"

exec "$ROOT/scripts/tm-pathmgr-runtime-smoke.sh" "${runtime_args[@]}"
