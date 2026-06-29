#!/usr/bin/env bash
#
# Validate the tm_cpio Rust-default RC selector and the C rollback path.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-cpio-rc-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds NQ and LQ taskman in the selected tm_cpio RC mode, verifies the expected
cpio.o archive membership, then reuses the live tm_cpio runtime smoke.

Environment:
  TM_CPIO_RC_ROLLBACK  set 1 to select C tm_cpio rollback
  QSOE_RUST_TM_CPIO    defaults to the Rust RC path; may be 0 or 1
  TM_CPIO_RC_WORKDIR   output directory, default build/tm-cpio-rc
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
workdir=${TM_CPIO_RC_WORKDIR:-"$ROOT/build/tm-cpio-rc"}
rollback=${TM_CPIO_RC_ROLLBACK:-0}
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
    echo "tm-cpio-rc-smoke.sh: no ar tool found" >&2
    exit 127
}

fail() {
    echo "tm-cpio-rc-smoke.sh: $*" >&2
    exit 1
}

object_count() {
    local archive=$1
    local object=$2

    "$AR" t "$archive" |
        awk -v object="$object" '$0 == object { n++ } END { print n + 0 }'
}

require_cpio_count() {
    local label=$1
    local archive=$2
    local expected=$3
    local count

    [ -f "$archive" ] || fail "missing archive for $label: $archive"
    count=$(object_count "$archive" cpio.o)
    printf '%s cpio.o count: %s\n' "$label" "$count" |
        tee "$workdir/$label-cpio-membership.txt"
    [ "$count" -eq "$expected" ] ||
        fail "$label expected $expected cpio.o members, got $count"
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
            fail "QSOE_RUST_TM_CPIO must be 0 or 1"
            ;;
    esac
}

mkdir -p "$workdir"
"$ROOT/scripts/apply-component-overrides.sh"

case "$rollback" in
    0|false|FALSE|no|NO)
        if [ "${QSOE_RUST_TM_CPIO+x}" ]; then
            selected=$(normalize_selector "$QSOE_RUST_TM_CPIO")
            if [ "$selected" -eq 1 ]; then
                mode=rust-selected
                expected_cpio_count=0
            else
                mode=c-selected
                expected_cpio_count=1
            fi
        else
            selected=1
            mode=rust-default
            expected_cpio_count=0
        fi
        ;;
    1|true|TRUE|yes|YES)
        selected=0
        mode=c-rollback
        expected_cpio_count=1
        ;;
    *)
        fail "TM_CPIO_RC_ROLLBACK must be 0 or 1"
        ;;
esac

echo "tm-cpio-rc-smoke.sh: mode=$mode rollback=$rollback"

echo "tm-cpio-rc-smoke.sh: verifying NQ taskman selector"
if [ "$mode" = rust-default ]; then
    env -u QSOE_RUST_TM_CPIO "$MAKE" -C "$ROOT/nq/taskman" --no-print-directory \
        QSOE_RUST_TM_PROCFS=1
else
    "$MAKE" -C "$ROOT/nq/taskman" --no-print-directory \
        QSOE_RUST_TM_CPIO="$selected" \
        QSOE_RUST_TM_PROCFS=1
fi
require_cpio_count "nq-$mode" "$ROOT/nq/build/libtaskman/libtaskman.a" "$expected_cpio_count"

echo "tm-cpio-rc-smoke.sh: verifying LQ taskman selector"
if [ "$mode" = rust-default ]; then
    env -u QSOE_RUST_TM_CPIO "$MAKE" -C "$ROOT/lq" --no-print-directory \
        QSOE_RUST_TM_PROCFS=1 \
        taskman
else
    "$MAKE" -C "$ROOT/lq" --no-print-directory \
        QSOE_RUST_TM_CPIO="$selected" \
        QSOE_RUST_TM_PROCFS=1 \
        taskman
fi
require_cpio_count "lq-$mode" "$ROOT/lq/build/libtaskman/libtaskman.a" "$expected_cpio_count"

runtime_args=("$@")
if [ "$has_log" -eq 0 ]; then
    runtime_args=(-o "$workdir/boot-smoke-lq-tm-cpio-rc-$mode.log" "${runtime_args[@]}")
fi

export QSOE_RUST_TM_CPIO="$selected"
export QSOE_RUST_TM_PROCFS=1
export TM_CPIO_RUNTIME_SMOKE_WORKDIR="$workdir"
if [ "$selected" -eq 0 ]; then
    export TM_CPIO_RUNTIME_ALLOW_C=1
fi

exec "$ROOT/scripts/tm-cpio-runtime-smoke.sh" "${runtime_args[@]}"
