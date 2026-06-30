#!/usr/bin/env bash
#
# Validate the retired tm_rsrcdb Rust selector.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-rsrcdb-rc-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds LQ taskman with the retired Rust tm_rsrcdb provider, verifies that C
sys/rsrcdb.o is absent from the link plan, then reuses the live tm_rsrcdb
runtime smoke.

Environment:
  TM_RSRCDB_RC_ROLLBACK  unsupported after C tm_rsrcdb retirement
  QSOE_RUST_TM_RSRCDB    must remain 1 after C tm_rsrcdb retirement
  TM_RSRCDB_RC_WORKDIR   output directory, default build/tm-rsrcdb-rc
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
workdir=${TM_RSRCDB_RC_WORKDIR:-"$ROOT/build/tm-rsrcdb-rc"}
rollback=${TM_RSRCDB_RC_ROLLBACK:-0}
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
    echo "tm-rsrcdb-rc-smoke.sh: $*" >&2
    exit 1
}

capture_lq_plan() {
    local selected=$1
    local log=$2

    "$MAKE" -C "$ROOT/lq/taskman" --no-print-directory -B -n all \
        LIBTASKMAN_A="$ROOT/lq/build/libtaskman/libtaskman.a" \
        LIBTASKMAN_INC="$ROOT/libtaskman/include" \
        QSOE_RUST_TM_PATHMGR=1 \
        QSOE_RUST_TM_PROCFS=1 \
        QSOE_RUST_TM_PSEUDODEV=1 \
        QSOE_RUST_TM_RSRCDB="$selected" \
        > "$log"
}

require_rsrcdb_plan() {
    local label=$1
    local log=$2
    local expected=$3
    local count

    count=$(grep -Fo '/sys/rsrcdb.o' "$log" | wc -l | tr -d ' ')
    printf '%s sys/rsrcdb.o plan count: %s\n' "$label" "$count" |
        tee "$workdir/$label-rsrcdb-plan-membership.txt"
    [ "$count" -eq "$expected" ] ||
        fail "$label expected $expected sys/rsrcdb.o dry-run entries, got $count"
}

mkdir -p "$workdir"
"$ROOT/scripts/apply-component-overrides.sh"

if [ -e "$ROOT/lq/taskman/sys/rsrcdb.c" ]; then
    fail "lq/taskman/sys/rsrcdb.c should be retired"
fi

case "$rollback" in
    0|false|FALSE|no|NO)
        mode=rust-retired
        expected_rsrcdb_count=0
        ;;
    1|true|TRUE|yes|YES)
        echo "tm-rsrcdb-rc-smoke.sh: C tm_rsrcdb rollback is retired" >&2
        exit 2
        ;;
    *)
        echo "tm-rsrcdb-rc-smoke.sh: TM_RSRCDB_RC_ROLLBACK must be 0 after C retirement" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_RSRCDB:-1}" in
    1|true|TRUE|yes|YES)
        selected=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-rsrcdb-rc-smoke.sh: C tm_rsrcdb is retired; QSOE_RUST_TM_RSRCDB must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-rsrcdb-rc-smoke.sh: QSOE_RUST_TM_RSRCDB must be 1 after C retirement" >&2
        exit 2
        ;;
esac

echo "tm-rsrcdb-rc-smoke.sh: mode=$mode rollback=$rollback"

plan_log="$workdir/lq-$mode-taskman-dry-run.txt"
echo "tm-rsrcdb-rc-smoke.sh: verifying LQ taskman selector"
capture_lq_plan "$selected" "$plan_log"
require_rsrcdb_plan "lq-$mode" "$plan_log" "$expected_rsrcdb_count"

echo "tm-rsrcdb-rc-smoke.sh: building LQ taskman selector"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_PATHMGR=1 \
    QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_PSEUDODEV=1 \
    QSOE_RUST_TM_RSRCDB="$selected" \
    taskman

runtime_args=("$@")
if [ "$has_log" -eq 0 ]; then
    runtime_args=(-o "$workdir/boot-smoke-lq-tm-rsrcdb-rc-$mode.log" "${runtime_args[@]}")
fi

export QSOE_RUST_TM_PATHMGR=1
export QSOE_RUST_TM_PROCFS=1
export QSOE_RUST_TM_PSEUDODEV=1
export QSOE_RUST_TM_RSRCDB="$selected"
export TM_RSRCDB_RUNTIME_SMOKE_WORKDIR="$workdir"

exec "$ROOT/scripts/tm-rsrcdb-runtime-smoke.sh" "${runtime_args[@]}"
