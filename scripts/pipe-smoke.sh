#!/usr/bin/env bash
#
# Boot QSOE/L with a temporary sysinit fragment that starts the retired Rust
# /sbin/pipe service, then verify that it registers /dev/pipe and reaches login.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/pipe-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Adds a temporary quser/conf/sysinit fragment before rebuilding and booting the
normal QSOE/L image. The fragment starts Rust /sbin/pipe after /usr is mounted.

Environment:
  PIPE_SMOKE_WORKDIR   output directory, default build/pipe-smoke
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
            [ "$#" -ge 2 ] || { echo "pipe-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "pipe-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "pipe-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "pipe-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "pipe-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

workdir=${PIPE_SMOKE_WORKDIR:-"$ROOT/build/pipe-smoke"}
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
marker="pipe-smoke: started /sbin/pipe"
registration="[pipe-rs] /dev/pipe registered"

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-pipe.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "pipe-smoke.sh: missing quser/conf; run make prepare first" >&2
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
fragment=$(mktemp "$source_sysinit/10-pipe-smoke.XXXXXX.sh")
cat > "$fragment" <<'EOF'
if /sbin/pipe; then
    echo "pipe-smoke: started /sbin/pipe"
else
    echo "pipe-smoke: failed to start /sbin/pipe"
fi
EOF
chmod 0644 "$fragment"

echo "pipe-smoke.sh: rebuilding QSOE/L image with temporary pipe sysinit fragment"
"$MAKE" -C "$ROOT/lq" --no-print-directory

boot_args=(-k lq -t "$timeout_s" -o "$log")
if [ "$keep_running" -eq 1 ]; then
    boot_args+=(--keep-running)
fi
if [ "${#emu_args[@]}" -gt 0 ]; then
    boot_args+=(-- "${emu_args[@]}")
fi

echo "pipe-smoke.sh: booting Rust pipe smoke"
boot_extra_patterns=$(printf '%s\n' "$marker" "$registration")
QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    QSOE_BOOT_EXTRA_PATTERNS="$boot_extra_patterns" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

for expected in "$marker" "$registration"; do
    if ! grep -Fq "$expected" "$log"; then
        echo "pipe-smoke.sh: missing marker in $log: $expected" >&2
        exit 1
    fi
done

echo "pipe-smoke.sh: Rust pipe registration smoke passed"
