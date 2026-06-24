#!/usr/bin/env bash
#
# Boot QSOE under QEMU and wait for a login prompt.
#
# This wrapper delegates to the variant emu.sh scripts. It only adds log
# capture, milestone matching, timeout handling, and cleanup.

set -u

usage() {
    cat <<'EOF'
usage: scripts/boot-smoke.sh [-k lq|nq] [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Defaults:
  -k lq
  -t 120
  -o build/boot-smoke-<variant>-<timestamp>.log

Examples:
  scripts/boot-smoke.sh
  scripts/boot-smoke.sh -k lq -- --debug
  scripts/boot-smoke.sh -k nq -t 180

The selected variant must already be built. Missing build artifacts are
reported by lq/emu.sh or nq/emu.sh and captured in the log.

Environment:
  QSOE_BOOT_SLOGGER_PATTERN   slogger startup milestone; defaults to
                              "[slogger] alive"
  QSOE_BOOT_VIRTIO_PATTERN    LQ virtio block milestone; defaults to
                              "devb-virtio: /dev/vblk0 ready"
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
variant=lq
timeout_s=120
log=
keep_running=0
emu_args=()
slogger_pattern=${QSOE_BOOT_SLOGGER_PATTERN:-"[slogger] alive"}
virtio_pattern=${QSOE_BOOT_VIRTIO_PATTERN:-"devb-virtio: /dev/vblk0 ready"}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -k|--kernel|--variant)
            [ "$#" -ge 2 ] || { echo "boot-smoke.sh: $1 needs a value" >&2; exit 2; }
            variant=$2
            shift 2
            ;;
        -t|--timeout)
            [ "$#" -ge 2 ] || { echo "boot-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "boot-smoke.sh: $1 needs a value" >&2; exit 2; }
            log=$2
            shift 2
            ;;
        --keep-running)
            keep_running=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            while [ "$#" -gt 0 ]; do
                emu_args+=("$1")
                shift
            done
            ;;
        *)
            echo "boot-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$variant" in
    lq|nq) ;;
    *)
        echo "boot-smoke.sh: variant must be 'lq' or 'nq'" >&2
        exit 2
        ;;
esac

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "boot-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "boot-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

launcher="$ROOT/$variant/emu.sh"
if [ ! -x "$launcher" ]; then
    echo "boot-smoke.sh: launcher not executable: $launcher" >&2
    exit 1
fi

if [ -z "$log" ]; then
    stamp=$(date +%Y%m%d-%H%M%S)
    log="$ROOT/build/boot-smoke-$variant-$stamp.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$(dirname "$log")"
: > "$log"

patterns=(
    "QSOE/"
    "$slogger_pattern"
    "fs-qrv: mounted qrvfs at /usr"
    "login:"
)

if [ "$variant" = "lq" ]; then
    patterns+=(
        "spawning /sbin/init"
        "dispatcher ready"
        "$virtio_pattern"
    )
else
    patterns+=(
        "QSOE/N taskman starting"
        "taskman: cmdline:"
        "devb-nvme: ready"
    )
fi

all_patterns_seen() {
    local p
    for p in "${patterns[@]}"; do
        if ! grep -Fq "$p" "$log"; then
            return 1
        fi
    done
    return 0
}

print_missing_patterns() {
    local p
    for p in "${patterns[@]}"; do
        if grep -Fq "$p" "$log"; then
            printf '  ok      %s\n' "$p"
        else
            printf '  missing %s\n' "$p"
        fi
    done
}

pid=
cleanup() {
    if [ -n "${pid:-}" ] && kill -0 "$pid" >/dev/null 2>&1; then
        kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" >/dev/null 2>&1 || true
    fi
}

trap cleanup INT TERM EXIT

echo "boot-smoke.sh: variant=$variant timeout=${timeout_s}s log=$log"

(
    cd "$ROOT/$variant" || exit 1
    if [ "${#emu_args[@]}" -gt 0 ]; then
        exec ./emu.sh "${emu_args[@]}"
    else
        exec ./emu.sh
    fi
) >>"$log" 2>&1 &
pid=$!

start=$SECONDS
success=0

while kill -0 "$pid" >/dev/null 2>&1; do
    if all_patterns_seen; then
        success=1
        break
    fi

    elapsed=$((SECONDS - start))
    if [ "$elapsed" -ge "$timeout_s" ]; then
        break
    fi

    sleep 1
done

if [ "$success" -eq 1 ]; then
    echo "boot-smoke.sh: boot reached login prompt"
    print_missing_patterns
    if [ "$keep_running" -eq 0 ]; then
        cleanup
    else
        trap - INT TERM EXIT
        echo "boot-smoke.sh: QEMU left running as pid $pid"
    fi
    exit 0
fi

if kill -0 "$pid" >/dev/null 2>&1; then
    echo "boot-smoke.sh: timed out after ${timeout_s}s" >&2
else
    wait "$pid"
    rc=$?
    echo "boot-smoke.sh: launcher exited before login prompt, rc=$rc" >&2
fi

echo "boot-smoke.sh: milestone status:" >&2
print_missing_patterns >&2
echo "boot-smoke.sh: last 80 log lines:" >&2
tail -n 80 "$log" >&2
exit 1
