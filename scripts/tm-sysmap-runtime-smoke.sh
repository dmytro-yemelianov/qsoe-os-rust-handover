#!/usr/bin/env bash
#
# Boot QSOE/L with the selected tm_sysmap provider and exercise child sysmap consumers.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-sysmap-runtime-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Injects a temporary sysinit fragment that runs /usr/bin/sysinfo, rebuilds the
virtio qrvfs image, and boots QSOE/L with Rust tm_sysmap selected.

By default this validates the Rust-selected LQ sysmap page builder through a
spawned child process consuming the mapped PSYS page at QSOE_SYSMAP_VA. The
smoke expects sysinfo's QEMU timebase, PLIC, and PCI output, and therefore
also covers pci-server's hwi_init path derived from the same page.

Environment:
  TM_SYSMAP_RUNTIME_SMOKE_WORKDIR  output directory, default build/tm-sysmap-runtime-smoke
  QSOE_RUST_TM_SYSMAP              must remain 1 after C tm_sysmap retirement
  QSOE_RUST_TM_PROCFS              must remain 1 after C tm_procfs retirement
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
            [ "$#" -ge 2 ] || { echo "tm-sysmap-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "tm-sysmap-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "tm-sysmap-runtime-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "tm-sysmap-runtime-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "tm-sysmap-runtime-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

tm_sysmap_mode=
case "${QSOE_RUST_TM_SYSMAP:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_SYSMAP=1
        tm_sysmap_mode=rust-selected
        ;;
    0|false|FALSE|no|NO)
        echo "tm-sysmap-runtime-smoke.sh: C tm_sysmap is retired; QSOE_RUST_TM_SYSMAP must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-sysmap-runtime-smoke.sh: QSOE_RUST_TM_SYSMAP must be 1 after C retirement" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_PROCFS:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_PROCFS=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-sysmap-runtime-smoke.sh: C tm_procfs is retired; QSOE_RUST_TM_PROCFS must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-sysmap-runtime-smoke.sh: QSOE_RUST_TM_PROCFS must be 1 after C retirement" >&2
        exit 2
        ;;
esac

workdir=${TM_SYSMAP_RUNTIME_SMOKE_WORKDIR:-"$ROOT/build/tm-sysmap-runtime-smoke"}
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
lq_libc="$ROOT/lq/build/libc/libc.so"
sysinfo_staged="$ROOT/build/fsqrv-root/bin/sysinfo"
plan_log="$workdir/lq-$tm_sysmap_mode-taskman-dry-run.txt"

boot_syscfg_marker="syscfg built from FDT"
boot_sysmap_marker="sysmap page built"
pci_server_marker="[pci-server] scan complete"
sysinfo_ok_marker="tm-sysmap-runtime-smoke: /usr/bin/sysinfo completed"
timebase_marker="timebase 10000000 Hz"
plic_marker="interrupts: PLIC at"
pci_marker="PCI:       buses 0.."

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-tm-sysmap-runtime.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "tm-sysmap-runtime-smoke.sh: missing quser/conf; run make prepare first" >&2
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
    echo "tm-sysmap-runtime-smoke.sh: no nm tool found" >&2
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
fragment=$(mktemp "$source_sysinit/10-tm-sysmap-runtime-smoke.XXXXXX.sh")
cat > "$fragment" <<EOF
if /usr/bin/sysinfo; then
    echo "$sysinfo_ok_marker"
else
    rc=\$?
    echo "tm-sysmap-runtime-smoke: /usr/bin/sysinfo failed \$rc"
fi
EOF
chmod 0644 "$fragment"

echo "tm-sysmap-runtime-smoke.sh: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory

echo "tm-sysmap-runtime-smoke.sh: rebuilding quser with LQ libc"
"$MAKE" -C "$ROOT/quser" LIBC_SO="$lq_libc" --no-print-directory

echo "tm-sysmap-runtime-smoke.sh: rebuilding virtio qrvfs image"
"$MAKE" -C "$ROOT" virtio --no-print-directory

if [ ! -x "$sysinfo_staged" ]; then
    echo "tm-sysmap-runtime-smoke.sh: staged sysinfo is missing or not executable" >&2
    exit 1
fi

echo "tm-sysmap-runtime-smoke.sh: capturing $tm_sysmap_mode tm_sysmap LQ taskman link plan"
"$MAKE" -C "$ROOT/lq/taskman" --no-print-directory -B -n all \
    LIBTASKMAN_A="$ROOT/lq/build/libtaskman/libtaskman.a" \
    LIBTASKMAN_INC="$ROOT/libtaskman/include" \
    QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_SYSMAP="$QSOE_RUST_TM_SYSMAP" \
    > "$plan_log"

if grep -Fq '/sys/sysmap.o' "$plan_log"; then
    echo "tm-sysmap-runtime-smoke.sh: Rust-selected taskman link plan still contains sys/sysmap.o" >&2
    exit 1
fi
if ! grep -Fq 'libqsoe_tm_providers.a' "$plan_log"; then
    echo "tm-sysmap-runtime-smoke.sh: Rust-selected taskman link plan omits libqsoe_tm_providers.a" >&2
    exit 1
fi

echo "tm-sysmap-runtime-smoke.sh: rebuilding QSOE/L image with $tm_sysmap_mode tm_sysmap"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_SYSMAP="$QSOE_RUST_TM_SYSMAP"

for symbol in tm_sysmap_build tm_sysmap_get; do
    if ! "$NM" -g --defined-only "$ROOT/build/rust/tm-providers/libqsoe_tm_providers.a" |
        grep -Eq "[[:space:]]$symbol$"; then
        echo "tm-sysmap-runtime-smoke.sh: Rust provider archive is missing $symbol" >&2
        exit 1
    fi
done

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
    "$pci_server_marker"
    "$sysinfo_ok_marker"
    "$timebase_marker"
    "$plic_marker"
    "$pci_marker"
)
boot_extra_patterns=$(printf '%s\n' "${expected_markers[@]}")

echo "tm-sysmap-runtime-smoke.sh: booting $tm_sysmap_mode tm_sysmap runtime smoke"
QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    QSOE_BOOT_EXTRA_PATTERNS="$boot_extra_patterns" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

for expected in "${expected_markers[@]}"; do
    if ! log_has_marker "$expected"; then
        echo "tm-sysmap-runtime-smoke.sh: missing marker in $log: $expected" >&2
        exit 1
    fi
done

echo "tm-sysmap-runtime-smoke.sh: runtime smoke passed"
