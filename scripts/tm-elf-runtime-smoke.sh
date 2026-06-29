#!/usr/bin/env bash
#
# Boot QSOE/L with Rust tm_elf selected and exercise dynamic ELF spawn.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-elf-runtime-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Injects a temporary sysinit fragment that runs /usr/bin/sysinfo, rebuilds the
virtio qrvfs image, and boots QSOE/L with QSOE_RUST_TM_ELF=1. sysinfo is a
dynamic ELF, so a clean run exercises taskman's ELF parser for the main image,
rtld, and libc before process start.

Environment:
  TM_ELF_RUNTIME_SMOKE_WORKDIR  output directory, default build/tm-elf-runtime-smoke
  QSOE_RUST_TM_ELF              set to 1; this smoke validates the Rust provider
  QSOE_RUST_TM_PROCFS           must remain 1 after C tm_procfs retirement
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
            [ "$#" -ge 2 ] || { echo "tm-elf-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "tm-elf-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "tm-elf-runtime-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "tm-elf-runtime-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "tm-elf-runtime-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

case "${QSOE_RUST_TM_ELF:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_ELF=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-elf-runtime-smoke.sh: this smoke validates QSOE_RUST_TM_ELF=1" >&2
        exit 2
        ;;
    *)
        echo "tm-elf-runtime-smoke.sh: QSOE_RUST_TM_ELF must be 1" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_PROCFS:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_PROCFS=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-elf-runtime-smoke.sh: C tm_procfs is retired; QSOE_RUST_TM_PROCFS must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-elf-runtime-smoke.sh: QSOE_RUST_TM_PROCFS must be 1 after C retirement" >&2
        exit 2
        ;;
esac

workdir=${TM_ELF_RUNTIME_SMOKE_WORKDIR:-"$ROOT/build/tm-elf-runtime-smoke"}
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
lq_libc="$ROOT/lq/build/libc/libc.so"
sysinfo_staged="$ROOT/build/fsqrv-root/bin/sysinfo"
spawn_marker="tm-elf-runtime-smoke: /usr/bin/sysinfo dynamic ELF spawn ok"

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-tm-elf-runtime.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "tm-elf-runtime-smoke.sh: missing quser/conf; run make prepare first" >&2
    exit 1
fi

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

READELF=$(find_tool riscv64-linux-gnu-readelf readelf llvm-readelf) || {
    echo "tm-elf-runtime-smoke.sh: no readelf tool found" >&2
    exit 127
}

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
fragment=$(mktemp "$source_sysinit/10-tm-elf-runtime-smoke.XXXXXX.sh")
cat > "$fragment" <<EOF
if /usr/bin/sysinfo >/dev/null 2>&1; then
    echo "$spawn_marker"
else
    rc=\$?
    echo "tm-elf-runtime-smoke: /usr/bin/sysinfo failed \$rc"
fi
EOF
chmod 0644 "$fragment"

echo "tm-elf-runtime-smoke.sh: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory

echo "tm-elf-runtime-smoke.sh: rebuilding quser with LQ libc"
"$MAKE" -C "$ROOT/quser" LIBC_SO="$lq_libc" --no-print-directory

echo "tm-elf-runtime-smoke.sh: rebuilding virtio qrvfs image"
"$MAKE" -C "$ROOT" virtio --no-print-directory

if [ ! -x "$sysinfo_staged" ]; then
    echo "tm-elf-runtime-smoke.sh: staged sysinfo is missing or not executable" >&2
    exit 1
fi
if ! "$READELF" -l "$sysinfo_staged" | grep -Fq "Requesting program interpreter"; then
    echo "tm-elf-runtime-smoke.sh: staged sysinfo is not a dynamic ELF" >&2
    exit 1
fi

echo "tm-elf-runtime-smoke.sh: rebuilding QSOE/L image with Rust tm_elf"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_ELF=1 \
    QSOE_RUST_TM_PROCFS=1

boot_args=(-k lq -t "$timeout_s" -o "$log")
if [ "$keep_running" -eq 1 ]; then
    boot_args+=(--keep-running)
fi
if [ "${#emu_args[@]}" -gt 0 ]; then
    boot_args+=(-- "${emu_args[@]}")
fi

echo "tm-elf-runtime-smoke.sh: booting Rust tm_elf runtime smoke"
QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    QSOE_BOOT_EXTRA_PATTERNS="$spawn_marker" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

if ! log_has_marker "$spawn_marker"; then
    echo "tm-elf-runtime-smoke.sh: missing marker in $log: $spawn_marker" >&2
    exit 1
fi

echo "tm-elf-runtime-smoke.sh: runtime smoke passed"
