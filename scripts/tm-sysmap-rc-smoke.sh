#!/usr/bin/env bash
#
# Validate the tm_sysmap Rust-default RC selector and the C rollback path.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-sysmap-rc-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds LQ taskman in the selected tm_sysmap RC mode, verifies the expected
sys/sysmap.o link-plan membership, then reuses the live tm_sysmap runtime
smoke.

Environment:
  TM_SYSMAP_RC_ROLLBACK  set 1 to select C tm_sysmap rollback
  QSOE_RUST_TM_SYSMAP    defaults to the Rust RC path; may be 0 or 1
  TM_SYSMAP_RC_WORKDIR   output directory, default build/tm-sysmap-rc
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
workdir=${TM_SYSMAP_RC_WORKDIR:-"$ROOT/build/tm-sysmap-rc"}
rollback=${TM_SYSMAP_RC_ROLLBACK:-0}
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
    echo "tm-sysmap-rc-smoke.sh: $*" >&2
    exit 1
}

normalize_selector() {
    case "$1" in
        1|true|TRUE|yes|YES)
            printf '1'
            ;;
        0|false|FALSE|no|NO)
            printf '0'
            ;;
        *)
            fail "QSOE_RUST_TM_SYSMAP must be 0 or 1"
            ;;
    esac
}

capture_lq_taskman_plan() {
    local label=$1
    local selected=$2
    local log="$workdir/$label-taskman-dry-run.txt"

    "$MAKE" -C "$ROOT/lq/taskman" --no-print-directory -B -n all \
        LIBTASKMAN_A="$ROOT/lq/build/libtaskman/libtaskman.a" \
        LIBTASKMAN_INC="$ROOT/libtaskman/include" \
        QSOE_RUST_TM_PROCFS=1 \
        QSOE_RUST_TM_SYSMAP="$selected" \
        > "$log"
}

require_plan_contains() {
    local label=$1
    local needle=$2
    local log="$workdir/$label-taskman-dry-run.txt"

    grep -Fq "$needle" "$log" ||
        fail "$label dry-run link plan is missing $needle"
}

require_plan_omits() {
    local label=$1
    local needle=$2
    local log="$workdir/$label-taskman-dry-run.txt"

    if grep -Fq "$needle" "$log"; then
        fail "$label dry-run link plan unexpectedly contains $needle"
    fi
}

mkdir -p "$workdir"
"$ROOT/scripts/apply-component-overrides.sh"

case "$rollback" in
    0|false|FALSE|no|NO)
        if [ "${QSOE_RUST_TM_SYSMAP+x}" ]; then
            selected=$(normalize_selector "$QSOE_RUST_TM_SYSMAP")
            if [ "$selected" -eq 1 ]; then
                mode=rust-selected
            else
                mode=c-selected
            fi
        else
            selected=1
            mode=rust-default
        fi
        ;;
    1|true|TRUE|yes|YES)
        selected=0
        mode=c-rollback
        ;;
    *)
        fail "TM_SYSMAP_RC_ROLLBACK must be 0 or 1"
        ;;
esac

echo "tm-sysmap-rc-smoke.sh: mode=$mode rollback=$rollback"

echo "tm-sysmap-rc-smoke.sh: verifying LQ taskman selector"
capture_lq_taskman_plan "lq-$mode" "$selected"
case "$selected" in
    1)
        require_plan_omits "lq-$mode" '/sys/sysmap.o'
        require_plan_contains "lq-$mode" 'libqsoe_tm_providers.a'
        ;;
    0)
        require_plan_contains "lq-$mode" '/sys/sysmap.o'
        ;;
esac

if [ "$mode" = rust-default ]; then
    env -u QSOE_RUST_TM_SYSMAP "$MAKE" -C "$ROOT/lq" --no-print-directory \
        QSOE_RUST_TM_PROCFS=1 \
        taskman
else
    "$MAKE" -C "$ROOT/lq" --no-print-directory \
        QSOE_RUST_TM_SYSMAP="$selected" \
        QSOE_RUST_TM_PROCFS=1 \
        taskman
fi

runtime_args=("$@")
if [ "$has_log" -eq 0 ]; then
    runtime_args=(-o "$workdir/boot-smoke-lq-tm-sysmap-rc-$mode.log" "${runtime_args[@]}")
fi

export QSOE_RUST_TM_SYSMAP="$selected"
export QSOE_RUST_TM_PROCFS=1
export TM_SYSMAP_RUNTIME_SMOKE_WORKDIR="$workdir"
if [ "$selected" -eq 0 ]; then
    export TM_SYSMAP_RUNTIME_ALLOW_C=1
fi

exec "$ROOT/scripts/tm-sysmap-runtime-smoke.sh" "${runtime_args[@]}"
