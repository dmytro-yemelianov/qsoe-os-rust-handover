#!/usr/bin/env bash
#
# Boot QSOE/L with the selected tm_sysfs provider and exercise /sys consumers.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-sysfs-runtime-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Injects a temporary sysinit fragment that enumerates /sys and reads all five
portable /sys files, rebuilds the virtio qrvfs image, and boots QSOE/L with
Rust tm_sysfs selected.

By default this validates the Rust-selected libtaskman tm_sysfs model through
LQ taskman's existing path dispatch. Syscfg/FDT discovery, process creation,
IPC, and seL4 object manipulation remain C.

Environment:
  TM_SYSFS_RUNTIME_SMOKE_WORKDIR  output directory, default build/tm-sysfs-runtime-smoke
  QSOE_RUST_TM_SYSFS              defaults to 1; set 0 only with rollback escape hatch
  QSOE_RUST_TM_PROCFS             must remain 1 after C tm_procfs retirement
  TM_SYSFS_RUNTIME_ALLOW_C        internal RC rollback escape hatch
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
            [ "$#" -ge 2 ] || { echo "tm-sysfs-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "tm-sysfs-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "tm-sysfs-runtime-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "tm-sysfs-runtime-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "tm-sysfs-runtime-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

tm_sysfs_mode=
case "${QSOE_RUST_TM_SYSFS:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_SYSFS=1
        tm_sysfs_mode=rust-selected
        ;;
    0|false|FALSE|no|NO)
        case "${TM_SYSFS_RUNTIME_ALLOW_C:-0}" in
            1|true|TRUE|yes|YES)
                export QSOE_RUST_TM_SYSFS=0
                tm_sysfs_mode=c-rollback
                ;;
            *)
                echo "tm-sysfs-runtime-smoke.sh: this smoke validates QSOE_RUST_TM_SYSFS=1" >&2
                exit 2
                ;;
        esac
        ;;
    *)
        echo "tm-sysfs-runtime-smoke.sh: QSOE_RUST_TM_SYSFS must be 1" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_PROCFS:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_PROCFS=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-sysfs-runtime-smoke.sh: C tm_procfs is retired; QSOE_RUST_TM_PROCFS must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-sysfs-runtime-smoke.sh: QSOE_RUST_TM_PROCFS must be 1 after C retirement" >&2
        exit 2
        ;;
esac

workdir=${TM_SYSFS_RUNTIME_SMOKE_WORKDIR:-"$ROOT/build/tm-sysfs-runtime-smoke"}
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
lq_libc="$ROOT/lq/build/libc/libc.so"
members_log="$workdir/lq-$tm_sysfs_mode-libtaskman-members.txt"

boot_syscfg_marker="syscfg built from FDT"
boot_sysmap_marker="sysmap page built"
dir_marker="tm-sysfs-runtime-smoke: /sys readdir ok"
board_marker="tm-sysfs-runtime-smoke: /sys/board ok"
builddate_marker="tm-sysfs-runtime-smoke: /sys/builddate ok"
cmdline_marker="tm-sysfs-runtime-smoke: /sys/cmdline ok"
osname_marker="tm-sysfs-runtime-smoke: /sys/osname ok"
version_marker="tm-sysfs-runtime-smoke: /sys/version ok"

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-tm-sysfs-runtime.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "tm-sysfs-runtime-smoke.sh: missing quser/conf; run make prepare first" >&2
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

AR=$(find_tool riscv64-linux-gnu-ar ar llvm-ar) || {
    echo "tm-sysfs-runtime-smoke.sh: no ar tool found" >&2
    exit 127
}
NM=$(find_tool riscv64-linux-gnu-nm nm llvm-nm) || {
    echo "tm-sysfs-runtime-smoke.sh: no nm tool found" >&2
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
fragment=$(mktemp "$source_sysinit/10-tm-sysfs-runtime-smoke.XXXXXX.sh")
cat > "$fragment" <<EOF
if /bin/ls /sys; then
    echo "$dir_marker"
else
    echo "tm-sysfs-runtime-smoke: /sys readdir failed"
fi

if read -r BOARD < /sys/board && [ -n "\$BOARD" ] && [ "\$BOARD" != "unknown" ]; then
    echo "$board_marker"
else
    echo "tm-sysfs-runtime-smoke: /sys/board failed"
fi

if read -r BUILDDATE < /sys/builddate && [ -n "\$BUILDDATE" ]; then
    echo "$builddate_marker"
else
    echo "tm-sysfs-runtime-smoke: /sys/builddate failed"
fi

if read -r CMDLINE < /sys/cmdline; then
    case "\$CMDLINE" in
        *mainfs=/dev/vblk0*) echo "$cmdline_marker" ;;
        *) echo "tm-sysfs-runtime-smoke: /sys/cmdline missing mainfs" ;;
    esac
else
    echo "tm-sysfs-runtime-smoke: /sys/cmdline failed"
fi

if read -r OSNAME < /sys/osname && [ "\$OSNAME" = "QSOE/L" ]; then
    echo "$osname_marker"
else
    echo "tm-sysfs-runtime-smoke: /sys/osname failed"
fi

if read -r VERSION < /sys/version && [ -n "\$VERSION" ]; then
    echo "$version_marker"
else
    echo "tm-sysfs-runtime-smoke: /sys/version failed"
fi
EOF
chmod 0644 "$fragment"

echo "tm-sysfs-runtime-smoke.sh: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory

echo "tm-sysfs-runtime-smoke.sh: rebuilding quser with LQ libc"
"$MAKE" -C "$ROOT/quser" LIBC_SO="$lq_libc" --no-print-directory

echo "tm-sysfs-runtime-smoke.sh: rebuilding virtio qrvfs image"
"$MAKE" -C "$ROOT" virtio --no-print-directory

echo "tm-sysfs-runtime-smoke.sh: rebuilding QSOE/L image with $tm_sysfs_mode tm_sysfs"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_SYSFS="$QSOE_RUST_TM_SYSFS"

"$AR" t "$ROOT/lq/build/libtaskman/libtaskman.a" > "$members_log"
case "$QSOE_RUST_TM_SYSFS" in
    1)
        if grep -Fxq tm_sysfs.o "$members_log"; then
            echo "tm-sysfs-runtime-smoke.sh: Rust-selected libtaskman still contains tm_sysfs.o" >&2
            exit 1
        fi

        for symbol in \
            tm_sysfs_init \
            tm_sysfs_resolve \
            tm_sysfs_path_exists \
            tm_sysfs_content \
            tm_sysfs_nentries \
            tm_sysfs_entry_name
        do
            if ! "$NM" -g --defined-only "$ROOT/build/rust/tm-providers/libqsoe_tm_providers.a" |
                grep -Eq "[[:space:]]$symbol$"; then
                echo "tm-sysfs-runtime-smoke.sh: Rust provider archive is missing $symbol" >&2
                exit 1
            fi
        done
        ;;
    0)
        if ! grep -Fxq tm_sysfs.o "$members_log"; then
            echo "tm-sysfs-runtime-smoke.sh: C rollback libtaskman is missing tm_sysfs.o" >&2
            exit 1
        fi
        ;;
esac

boot_args=(-k lq -t "$timeout_s" -o "$log")
if [ "$keep_running" -eq 1 ]; then
    boot_args+=(--keep-running)
fi
if [ "${#emu_args[@]}" -gt 0 ]; then
    boot_args+=(-- "${emu_args[@]}")
fi

expected_markers=(
    "$boot_syscfg_marker"
    "$boot_sysmap_marker"
    "$dir_marker"
    "$board_marker"
    "$builddate_marker"
    "$cmdline_marker"
    "$osname_marker"
    "$version_marker"
)
boot_extra_patterns=$(printf '%s\n' "${expected_markers[@]}")

echo "tm-sysfs-runtime-smoke.sh: booting $tm_sysfs_mode tm_sysfs runtime smoke"
QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    QSOE_BOOT_EXTRA_PATTERNS="$boot_extra_patterns" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

for expected in "${expected_markers[@]}"; do
    if ! log_has_marker "$expected"; then
        echo "tm-sysfs-runtime-smoke.sh: missing marker in $log: $expected" >&2
        exit 1
    fi
done

echo "tm-sysfs-runtime-smoke.sh: runtime smoke passed"
