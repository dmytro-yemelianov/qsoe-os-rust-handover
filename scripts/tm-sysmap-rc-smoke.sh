#!/usr/bin/env bash
#
# Validate the retired tm_sysmap Rust selector.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-sysmap-rc-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds LQ taskman with the retired Rust tm_sysmap provider, verifies that
C sys/sysmap.o is absent from the link plan, then reuses the live tm_sysmap
runtime smoke.

Environment:
  TM_SYSMAP_RC_ROLLBACK  unsupported after C tm_sysmap retirement
  QSOE_RUST_TM_SYSMAP    must remain 1 after C tm_sysmap retirement
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

case "${QSOE_RUST_TM_SYSMAP:-1}" in
    1|true|TRUE|yes|YES)
        selected=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-sysmap-rc-smoke.sh: C tm_sysmap is retired; QSOE_RUST_TM_SYSMAP must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-sysmap-rc-smoke.sh: QSOE_RUST_TM_SYSMAP must be 1 after C retirement" >&2
        exit 2
        ;;
esac

case "$rollback" in
    0|false|FALSE|no|NO)
        mode=rust-retired
        ;;
    1|true|TRUE|yes|YES)
        echo "tm-sysmap-rc-smoke.sh: C tm_sysmap rollback is retired" >&2
        exit 2
        ;;
    *)
        echo "tm-sysmap-rc-smoke.sh: TM_SYSMAP_RC_ROLLBACK must be 0 after C retirement" >&2
        exit 2
        ;;
esac

echo "tm-sysmap-rc-smoke.sh: mode=$mode rollback=$rollback"

echo "tm-sysmap-rc-smoke.sh: verifying LQ taskman selector"
capture_lq_taskman_plan "lq-$mode" "$selected"
require_plan_omits "lq-$mode" '/sys/sysmap.o'
require_plan_contains "lq-$mode" 'libqsoe_tm_providers.a'

"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_SYSMAP=1 \
    QSOE_RUST_TM_PROCFS=1 \
    taskman

runtime_args=("$@")
if [ "$has_log" -eq 0 ]; then
    runtime_args=(-o "$workdir/boot-smoke-lq-tm-sysmap-rc-$mode.log" "${runtime_args[@]}")
fi

export QSOE_RUST_TM_SYSMAP="$selected"
export QSOE_RUST_TM_PROCFS=1
export TM_SYSMAP_RUNTIME_SMOKE_WORKDIR="$workdir"

exec "$ROOT/scripts/tm-sysmap-runtime-smoke.sh" "${runtime_args[@]}"
