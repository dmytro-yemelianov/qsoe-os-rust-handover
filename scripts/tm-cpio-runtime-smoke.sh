#!/usr/bin/env bash
#
# Boot QSOE/L with Rust tm_cpio selected and exercise CPIO-backed runtime
# paths from sysinit.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-cpio-runtime-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Adds a temporary quser/conf/sysinit fragment before rebuilding and booting a
normal QSOE/L image with Rust tm_cpio selected. The fragment runs after /usr is
mounted and verifies CPIO-root symlink readlink output, /etc -> /usr/conf file
access, a direct boot-cpio file read, and /bin/sh symlink spawn.

Environment:
  TM_CPIO_RUNTIME_SMOKE_WORKDIR  output directory, default build/tm-cpio-runtime-smoke
  QSOE_RUST_TM_CPIO              defaults to 1; set 0 only with rollback escape hatch
  QSOE_RUST_TM_PROCFS            must remain 1 after C tm_procfs retirement
  TM_CPIO_RUNTIME_ALLOW_C        internal RC rollback escape hatch
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
            [ "$#" -ge 2 ] || { echo "tm-cpio-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "tm-cpio-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "tm-cpio-runtime-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "tm-cpio-runtime-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "tm-cpio-runtime-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

tm_cpio_mode=
case "${QSOE_RUST_TM_CPIO:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_CPIO=1
        tm_cpio_mode=rust-selected
        ;;
    0|false|FALSE|no|NO)
        case "${TM_CPIO_RUNTIME_ALLOW_C:-0}" in
            1|true|TRUE|yes|YES)
                export QSOE_RUST_TM_CPIO=0
                tm_cpio_mode=c-rollback
                ;;
            *)
                echo "tm-cpio-runtime-smoke.sh: this smoke validates QSOE_RUST_TM_CPIO=1" >&2
                exit 2
                ;;
        esac
        ;;
    *)
        echo "tm-cpio-runtime-smoke.sh: QSOE_RUST_TM_CPIO must be 1" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_PROCFS:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_PROCFS=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-cpio-runtime-smoke.sh: C tm_procfs is retired; QSOE_RUST_TM_PROCFS must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-cpio-runtime-smoke.sh: QSOE_RUST_TM_PROCFS must be 1 after C retirement" >&2
        exit 2
        ;;
esac

workdir=${TM_CPIO_RUNTIME_SMOKE_WORKDIR:-"$ROOT/build/tm-cpio-runtime-smoke"}
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=

root_marker="tm-cpio-runtime-smoke: root symlink listing ok"
etc_marker="tm-cpio-runtime-smoke: /etc/passwd via cpio symlink ok"
boot_cpio_marker="tm-cpio-runtime-smoke: boot cpio file read ok"
spawn_marker="tm-cpio-runtime-smoke: /bin/sh symlink spawn ok"

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-tm-cpio-runtime.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "tm-cpio-runtime-smoke.sh: missing quser/conf; run make prepare first" >&2
    exit 1
fi

log_has_marker() {
    local marker=$1

    grep -Fq "$marker" "$log" ||
        tr -d '\r\n' < "$log" | grep -Fq "$marker"
}

"$ROOT/scripts/apply-component-overrides.sh"

cleanup() {
    if [ -n "$fragment" ]; then
        rm -f "$fragment"
    fi
    rmdir "$source_sysinit" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$source_sysinit"
fragment=$(mktemp "$source_sysinit/10-tm-cpio-runtime-smoke.XXXXXX.sh")
cat > "$fragment" <<EOF
if /bin/ls -la /; then
    echo "$root_marker"
else
    echo "tm-cpio-runtime-smoke: root symlink listing failed"
fi

if /bin/cat /etc/passwd >/dev/null 2>&1; then
    echo "$etc_marker"
else
    echo "tm-cpio-runtime-smoke: /etc/passwd via cpio symlink failed"
fi

if /bin/cat /sbin/init >/dev/null 2>&1; then
    echo "$boot_cpio_marker"
else
    echo "tm-cpio-runtime-smoke: boot cpio file read failed"
fi

if /bin/sh -c 'echo "$spawn_marker"'; then
    :
else
    echo "tm-cpio-runtime-smoke: /bin/sh symlink spawn failed"
fi
EOF
chmod 0644 "$fragment"

echo "tm-cpio-runtime-smoke.sh: rebuilding QSOE/L image with $tm_cpio_mode tm_cpio"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_CPIO="$QSOE_RUST_TM_CPIO" \
    QSOE_RUST_TM_PROCFS=1

boot_args=(-k lq -t "$timeout_s" -o "$log")
if [ "$keep_running" -eq 1 ]; then
    boot_args+=(--keep-running)
fi
if [ "${#emu_args[@]}" -gt 0 ]; then
    boot_args+=(-- "${emu_args[@]}")
fi

echo "tm-cpio-runtime-smoke.sh: booting $tm_cpio_mode tm_cpio runtime smoke"
boot_extra_patterns=$(printf '%s\n' \
    "etc -> /usr/conf" \
    "home -> /usr/home" \
    "$root_marker" \
    "$etc_marker" \
    "$boot_cpio_marker" \
    "$spawn_marker")
QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    QSOE_BOOT_EXTRA_PATTERNS="$boot_extra_patterns" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

for expected in \
    "etc -> /usr/conf" \
    "home -> /usr/home" \
    "$root_marker" \
    "$etc_marker" \
    "$boot_cpio_marker" \
    "$spawn_marker"
do
    if ! log_has_marker "$expected"; then
        echo "tm-cpio-runtime-smoke.sh: missing marker in $log: $expected" >&2
        exit 1
    fi
done

echo "tm-cpio-runtime-smoke.sh: runtime smoke passed"
