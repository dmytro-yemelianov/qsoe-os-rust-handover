#!/usr/bin/env bash
#
# Boot QSOE/L with the selected tm_fdt provider and exercise booted FDT consumers.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-fdt-runtime-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Injects a temporary sysinit fragment that reads /sys/board and /sys/cmdline,
runs /usr/bin/sysinfo, rebuilds the virtio qrvfs image, and boots QSOE/L with
the selected tm_fdt provider.

This validates the selected LQ FDT parser through /chosen bootargs, syscfg/sysmap
construction, syscfg-backed /sys consumers, and sysinfo. It is a QEMU/LQ runtime
smoke, not complete hardware PCI or memory-topology coverage.

Environment:
  TM_FDT_RUNTIME_SMOKE_WORKDIR  output directory, default build/tm-fdt-runtime-smoke
  TM_FDT_RUNTIME_ALLOW_C        set to 1 only for the C rollback smoke
  QSOE_RUST_TM_FDT              default 1; set 0 only with TM_FDT_RUNTIME_ALLOW_C=1
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
            [ "$#" -ge 2 ] || { echo "tm-fdt-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "tm-fdt-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "tm-fdt-runtime-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "tm-fdt-runtime-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "tm-fdt-runtime-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

case "${QSOE_RUST_TM_FDT:-1}" in
    1|true|TRUE|yes|YES)
        selected=1
        mode=rust-default
        ;;
    0|false|FALSE|no|NO)
        if [ "${TM_FDT_RUNTIME_ALLOW_C:-0}" = 1 ]; then
            selected=0
            mode=c-rollback
        else
            echo "tm-fdt-runtime-smoke.sh: QSOE_RUST_TM_FDT=0 is only allowed with TM_FDT_RUNTIME_ALLOW_C=1" >&2
            exit 2
        fi
        ;;
    *)
        echo "tm-fdt-runtime-smoke.sh: QSOE_RUST_TM_FDT must be 0 or 1" >&2
        exit 2
        ;;
esac
export QSOE_RUST_TM_FDT="$selected"

case "${QSOE_RUST_TM_PROCFS:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_PROCFS=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-fdt-runtime-smoke.sh: C tm_procfs is retired; QSOE_RUST_TM_PROCFS must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-fdt-runtime-smoke.sh: QSOE_RUST_TM_PROCFS must be 1 after C retirement" >&2
        exit 2
        ;;
esac

workdir=${TM_FDT_RUNTIME_SMOKE_WORKDIR:-"$ROOT/build/tm-fdt-runtime-smoke"}
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
lq_libc="$ROOT/lq/build/libc/libc.so"
sysinfo_staged="$ROOT/build/fsqrv-root/bin/sysinfo"
plan_log="$workdir/lq-$mode-taskman-dry-run.txt"

boot_cmdline_marker="Boot command line: mainfs=/dev/vblk0"
boot_syscfg_marker="syscfg built from FDT"
boot_sysmap_marker="sysmap page built"
board_marker="tm-fdt-runtime-smoke: /sys/board FDT compatible ok"
cmdline_marker="tm-fdt-runtime-smoke: /chosen bootargs ok"
sysinfo_marker="tm-fdt-runtime-smoke: /usr/bin/sysinfo FDT sysinfo ok"

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-tm-fdt-runtime.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "tm-fdt-runtime-smoke.sh: missing quser/conf; run make prepare first" >&2
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

NM=$(find_tool riscv64-linux-gnu-nm nm llvm-nm) || {
    echo "tm-fdt-runtime-smoke.sh: no nm tool found" >&2
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
fragment=$(mktemp "$source_sysinit/10-tm-fdt-runtime-smoke.XXXXXX.sh")
cat > "$fragment" <<EOF
if read -r BOARD < /sys/board && [ -n "\$BOARD" ] && [ "\$BOARD" != "unknown" ]; then
    echo "$board_marker"
else
    echo "tm-fdt-runtime-smoke: /sys/board failed"
fi

if read -r CMDLINE < /sys/cmdline; then
    case "\$CMDLINE" in
        *mainfs=/dev/vblk0*) echo "$cmdline_marker" ;;
        *) echo "tm-fdt-runtime-smoke: /sys/cmdline missing mainfs" ;;
    esac
else
    echo "tm-fdt-runtime-smoke: /sys/cmdline failed"
fi

if /usr/bin/sysinfo >/dev/null 2>&1; then
    echo "$sysinfo_marker"
else
    rc=\$?
    echo "tm-fdt-runtime-smoke: /usr/bin/sysinfo failed \$rc"
fi
EOF
chmod 0644 "$fragment"

echo "tm-fdt-runtime-smoke.sh: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory

echo "tm-fdt-runtime-smoke.sh: rebuilding quser with LQ libc"
"$MAKE" -C "$ROOT/quser" LIBC_SO="$lq_libc" --no-print-directory

echo "tm-fdt-runtime-smoke.sh: rebuilding virtio qrvfs image"
"$MAKE" -C "$ROOT" virtio --no-print-directory

if [ ! -x "$sysinfo_staged" ]; then
    echo "tm-fdt-runtime-smoke.sh: staged sysinfo is missing or not executable" >&2
    exit 1
fi

echo "tm-fdt-runtime-smoke.sh: capturing $mode tm_fdt LQ taskman link plan"
"$MAKE" -C "$ROOT/lq/taskman" --no-print-directory -B -n all \
    LIBTASKMAN_A="$ROOT/lq/build/libtaskman/libtaskman.a" \
    LIBTASKMAN_INC="$ROOT/libtaskman/include" \
    QSOE_RUST_TM_FDT="$selected" \
    QSOE_RUST_TM_PROCFS=1 \
    > "$plan_log"

if [ "$selected" -eq 1 ]; then
    if grep -Fq '/sys/fdt.o' "$plan_log"; then
        echo "tm-fdt-runtime-smoke.sh: Rust-default taskman link plan still contains sys/fdt.o" >&2
        exit 1
    fi
    if ! grep -Fq 'libqsoe_tm_providers.a' "$plan_log"; then
        echo "tm-fdt-runtime-smoke.sh: Rust-default taskman link plan omits libqsoe_tm_providers.a" >&2
        exit 1
    fi
else
    if ! grep -Fq '/sys/fdt.o' "$plan_log"; then
        echo "tm-fdt-runtime-smoke.sh: C rollback taskman link plan omits sys/fdt.o" >&2
        exit 1
    fi
fi

echo "tm-fdt-runtime-smoke.sh: rebuilding QSOE/L image with $mode tm_fdt"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_FDT="$selected" \
    QSOE_RUST_TM_PROCFS=1

if [ "$selected" -eq 1 ]; then
    for symbol in \
        tm_fdt_check \
        tm_fdt_size \
        tm_fdt_path \
        tm_fdt_compatible \
        tm_fdt_prop \
        tm_fdt_prop_u32 \
        tm_fdt_prop_u64 \
        tm_fdt_prop_str \
        tm_fdt_reg
    do
        if ! "$NM" -g --defined-only "$ROOT/build/rust/tm-providers/libqsoe_tm_providers.a" |
            grep -Eq "[[:space:]]$symbol$"; then
            echo "tm-fdt-runtime-smoke.sh: Rust provider archive is missing $symbol" >&2
            exit 1
        fi
    done
fi

boot_args=(-k lq -t "$timeout_s" -o "$log")
if [ "$keep_running" -eq 1 ]; then
    boot_args+=(--keep-running)
fi
if [ "${#emu_args[@]}" -gt 0 ]; then
    boot_args+=(-- "${emu_args[@]}")
fi

expected_markers=(
    "$boot_cmdline_marker"
    "$boot_syscfg_marker"
    "$boot_sysmap_marker"
    "$board_marker"
    "$cmdline_marker"
    "$sysinfo_marker"
)
boot_extra_patterns=$(printf '%s\n' "${expected_markers[@]}")

echo "tm-fdt-runtime-smoke.sh: booting $mode tm_fdt runtime smoke"
QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    QSOE_BOOT_EXTRA_PATTERNS="$boot_extra_patterns" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

for expected in "${expected_markers[@]}"; do
    if ! log_has_marker "$expected"; then
        echo "tm-fdt-runtime-smoke.sh: missing marker in $log: $expected" >&2
        exit 1
    fi
done

echo "tm-fdt-runtime-smoke.sh: runtime smoke passed"
