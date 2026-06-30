#!/usr/bin/env bash
#
# Boot QSOE/L with the selected tm_syscfg provider and exercise syscfg-backed
# runtime consumers that remain owned by LQ taskman.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-syscfg-runtime-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Injects a temporary sysinit fragment that reads /sys/board and /sys/cmdline,
runs /usr/bin/sysinfo, rebuilds the virtio qrvfs image, and boots QSOE/L with
Rust tm_syscfg selected.

By default this validates the Rust-selected libtaskman tm_syscfg model plus
booted syscfg-backed consumers. LQ's private FDT-backed runtime syscfg builder
remains C and is intentionally not replaced by this provider.

Environment:
  TM_SYSCFG_RUNTIME_SMOKE_WORKDIR  output directory, default build/tm-syscfg-runtime-smoke
  QSOE_RUST_TM_SYSCFG              defaults to 1; set 0 only with rollback escape hatch
  QSOE_RUST_TM_PROCFS              must remain 1 after C tm_procfs retirement
  TM_SYSCFG_RUNTIME_ALLOW_C        internal RC rollback escape hatch
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
            [ "$#" -ge 2 ] || { echo "tm-syscfg-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "tm-syscfg-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "tm-syscfg-runtime-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "tm-syscfg-runtime-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "tm-syscfg-runtime-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

tm_syscfg_mode=
case "${QSOE_RUST_TM_SYSCFG:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_SYSCFG=1
        tm_syscfg_mode=rust-selected
        ;;
    0|false|FALSE|no|NO)
        case "${TM_SYSCFG_RUNTIME_ALLOW_C:-0}" in
            1|true|TRUE|yes|YES)
                export QSOE_RUST_TM_SYSCFG=0
                tm_syscfg_mode=c-rollback
                ;;
            *)
                echo "tm-syscfg-runtime-smoke.sh: this smoke validates QSOE_RUST_TM_SYSCFG=1" >&2
                exit 2
                ;;
        esac
        ;;
    *)
        echo "tm-syscfg-runtime-smoke.sh: QSOE_RUST_TM_SYSCFG must be 0 or 1" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_PROCFS:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_PROCFS=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-syscfg-runtime-smoke.sh: C tm_procfs is retired; QSOE_RUST_TM_PROCFS must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-syscfg-runtime-smoke.sh: QSOE_RUST_TM_PROCFS must be 1 after C retirement" >&2
        exit 2
        ;;
esac

workdir=${TM_SYSCFG_RUNTIME_SMOKE_WORKDIR:-"$ROOT/build/tm-syscfg-runtime-smoke"}
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
lq_libc="$ROOT/lq/build/libc/libc.so"
sysinfo_staged="$ROOT/build/fsqrv-root/bin/sysinfo"
members_log="$workdir/lq-$tm_syscfg_mode-libtaskman-members.txt"

boot_syscfg_marker="syscfg built from FDT"
boot_sysmap_marker="sysmap page built"
board_marker="tm-syscfg-runtime-smoke: /sys/board ok"
cmdline_marker="tm-syscfg-runtime-smoke: /sys/cmdline ok"
sysinfo_marker="tm-syscfg-runtime-smoke: /usr/bin/sysinfo syscfg consumers ok"

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-tm-syscfg-runtime.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "tm-syscfg-runtime-smoke.sh: missing quser/conf; run make prepare first" >&2
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
    echo "tm-syscfg-runtime-smoke.sh: no ar tool found" >&2
    exit 127
}
NM=$(find_tool riscv64-linux-gnu-nm nm llvm-nm) || {
    echo "tm-syscfg-runtime-smoke.sh: no nm tool found" >&2
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
fragment=$(mktemp "$source_sysinit/10-tm-syscfg-runtime-smoke.XXXXXX.sh")
cat > "$fragment" <<EOF
if read -r BOARD < /sys/board && [ -n "\$BOARD" ] && [ "\$BOARD" != "unknown" ]; then
    echo "$board_marker"
else
    echo "tm-syscfg-runtime-smoke: /sys/board failed"
fi

if read -r CMDLINE < /sys/cmdline; then
    case "\$CMDLINE" in
        *mainfs=/dev/vblk0*) echo "$cmdline_marker" ;;
        *) echo "tm-syscfg-runtime-smoke: /sys/cmdline missing mainfs" ;;
    esac
else
    echo "tm-syscfg-runtime-smoke: /sys/cmdline failed"
fi

if /usr/bin/sysinfo >/dev/null 2>&1; then
    echo "$sysinfo_marker"
else
    rc=\$?
    echo "tm-syscfg-runtime-smoke: /usr/bin/sysinfo failed \$rc"
fi
EOF
chmod 0644 "$fragment"

echo "tm-syscfg-runtime-smoke.sh: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory

echo "tm-syscfg-runtime-smoke.sh: rebuilding quser with LQ libc"
"$MAKE" -C "$ROOT/quser" LIBC_SO="$lq_libc" --no-print-directory

echo "tm-syscfg-runtime-smoke.sh: rebuilding virtio qrvfs image"
"$MAKE" -C "$ROOT" virtio --no-print-directory

if [ ! -x "$sysinfo_staged" ]; then
    echo "tm-syscfg-runtime-smoke.sh: staged sysinfo is missing or not executable" >&2
    exit 1
fi

echo "tm-syscfg-runtime-smoke.sh: rebuilding QSOE/L image with $tm_syscfg_mode tm_syscfg"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_SYSCFG="$QSOE_RUST_TM_SYSCFG"

"$AR" t "$ROOT/lq/build/libtaskman/libtaskman.a" > "$members_log"
case "$QSOE_RUST_TM_SYSCFG" in
    1)
        if grep -Fxq syscfg.o "$members_log"; then
            echo "tm-syscfg-runtime-smoke.sh: Rust-selected libtaskman still contains syscfg.o" >&2
            exit 1
        fi
        if ! "$NM" -g --defined-only "$ROOT/build/rust/tm-providers/libqsoe_tm_providers.a" |
            grep -Eq '[[:space:]]tm_syscfg_init$'; then
            echo "tm-syscfg-runtime-smoke.sh: Rust provider archive is missing tm_syscfg_init" >&2
            exit 1
        fi
        ;;
    0)
        if ! grep -Fxq syscfg.o "$members_log"; then
            echo "tm-syscfg-runtime-smoke.sh: C rollback libtaskman is missing syscfg.o" >&2
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
    "$board_marker"
    "$cmdline_marker"
    "$sysinfo_marker"
)
boot_extra_patterns=$(printf '%s\n' "${expected_markers[@]}")

echo "tm-syscfg-runtime-smoke.sh: booting $tm_syscfg_mode tm_syscfg runtime smoke"
QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    QSOE_BOOT_EXTRA_PATTERNS="$boot_extra_patterns" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

for expected in "${expected_markers[@]}"; do
    if ! log_has_marker "$expected"; then
        echo "tm-syscfg-runtime-smoke.sh: missing marker in $log: $expected" >&2
        exit 1
    fi
done

echo "tm-syscfg-runtime-smoke.sh: runtime smoke passed"
