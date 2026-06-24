#!/usr/bin/env bash
#
# Boot QSOE/L with a temporary sysinit fragment that exercises the current
# taskman /proc path before any Rust taskman pilot is wired in.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/procfs-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Adds a temporary quser/conf/sysinit fragment before rebuilding and booting the
normal QSOE/L image. The fragment runs after /usr is mounted and verifies that
taskman's /proc model can list /proc and read /proc/1/info.

Environment:
  PROCFS_SMOKE_WORKDIR   output directory, default build/procfs-smoke
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
timeout_s=180
log=
keep_running=0
emu_args=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        -t|--timeout)
            [ "$#" -ge 2 ] || { echo "procfs-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "procfs-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "procfs-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "procfs-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "procfs-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

workdir=${PROCFS_SMOKE_WORKDIR:-"$ROOT/build/procfs-smoke"}
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
ls_marker="procfs-smoke: listed /proc ok"
info_marker="procfs-smoke: read /proc/1/info ok"

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-procfs.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "procfs-smoke.sh: missing quser/conf; run make prepare first" >&2
    exit 1
fi

cleanup() {
    if [ -n "$fragment" ]; then
        rm -f "$fragment"
    fi
    rmdir "$source_sysinit" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$source_sysinit"
fragment=$(mktemp "$source_sysinit/10-procfs-smoke.XXXXXX.sh")
cat > "$fragment" <<'EOF'
if /bin/ls /proc >/dev/null 2>&1; then
    echo "procfs-smoke: listed /proc ok"
else
    echo "procfs-smoke: listed /proc failed"
fi

if /bin/cat /proc/1/info; then
    echo "procfs-smoke: read /proc/1/info ok"
else
    echo "procfs-smoke: read /proc/1/info failed"
fi
EOF
chmod 0644 "$fragment"

echo "procfs-smoke.sh: rebuilding QSOE/L image with temporary procfs sysinit fragment"
"$MAKE" -C "$ROOT/lq" --no-print-directory

boot_args=(-k lq -t "$timeout_s" -o "$log")
if [ "$keep_running" -eq 1 ]; then
    boot_args+=(--keep-running)
fi
if [ "${#emu_args[@]}" -gt 0 ]; then
    boot_args+=(-- "${emu_args[@]}")
fi

echo "procfs-smoke.sh: booting C procfs smoke"
QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

for expected in \
    "$ls_marker" \
    "$info_marker" \
    "pid: 1" \
    "ppid: 1" \
    "state: alive" \
    "name: taskman"
do
    if ! grep -Fq "$expected" "$log"; then
        echo "procfs-smoke.sh: missing marker in $log: $expected" >&2
        exit 1
    fi
done

echo "procfs-smoke.sh: /proc smoke passed"
