#!/usr/bin/env bash
#
# Boot QSOE/L with Rust tm_cred selected and exercise live credential state.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-cred-runtime-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Injects a temporary sysinit fragment that runs /usr/bin/cred_probe, rebuilds the
virtio qrvfs image with that helper staged, and boots QSOE/L with
QSOE_RUST_TM_CRED=1.

The helper exercises taskman-backed POSIX credential wrappers, cwd and umask
state, non-root permission rejection, and spawn inheritance.

Environment:
  TM_CRED_RUNTIME_SMOKE_WORKDIR  output directory, default build/tm-cred-runtime-smoke
  QSOE_RUST_TM_CRED              set to 1; this smoke validates the Rust selection
  QSOE_RUST_TM_PROCFS            must remain 1 after C tm_procfs retirement
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
            [ "$#" -ge 2 ] || { echo "tm-cred-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "tm-cred-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "tm-cred-runtime-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "tm-cred-runtime-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "tm-cred-runtime-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

case "${QSOE_RUST_TM_CRED:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_CRED=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-cred-runtime-smoke.sh: this smoke validates QSOE_RUST_TM_CRED=1" >&2
        exit 2
        ;;
    *)
        echo "tm-cred-runtime-smoke.sh: QSOE_RUST_TM_CRED must be 1" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_PROCFS:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_PROCFS=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-cred-runtime-smoke.sh: C tm_procfs is retired; QSOE_RUST_TM_PROCFS must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-cred-runtime-smoke.sh: QSOE_RUST_TM_PROCFS must be 1 after C retirement" >&2
        exit 2
        ;;
esac

workdir=${TM_CRED_RUNTIME_SMOKE_WORKDIR:-"$ROOT/build/tm-cred-runtime-smoke"}
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
lq_libc="$ROOT/lq/build/libc/libc.so"
members_log="$workdir/lq-rust-selected-libtaskman-members.txt"
cred_probe_staged="$ROOT/build/fsqrv-root/bin/cred_probe"
selected_msgpass="$ROOT/build/rust/selected/usr/bin/test_msgpass.elf"

boot_syscfg_marker="syscfg built from FDT"
boot_sysmap_marker="sysmap page built"
initial_marker="tm-cred-runtime-smoke: initial root ids ok"
umask_marker="tm-cred-runtime-smoke: umask exchange ok"
cwd_marker="tm-cred-runtime-smoke: cwd roundtrip ok"
mutation_marker="tm-cred-runtime-smoke: credential mutation ok"
gate_marker="tm-cred-runtime-smoke: permission gate ok"
child_marker="tm-cred-runtime-smoke: child inherited state ok"
spawn_marker="tm-cred-runtime-smoke: spawn inheritance ok"
probe_marker="tm-cred-runtime-smoke: credential probe ok"

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-tm-cred-runtime.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "tm-cred-runtime-smoke.sh: missing quser/conf; run make prepare first" >&2
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
    echo "tm-cred-runtime-smoke.sh: no ar tool found" >&2
    exit 127
}
NM=$(find_tool riscv64-linux-gnu-nm nm llvm-nm) || {
    echo "tm-cred-runtime-smoke.sh: no nm tool found" >&2
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
fragment=$(mktemp "$source_sysinit/10-tm-cred-runtime-smoke.XXXXXX.sh")
cat > "$fragment" <<EOF
if /usr/bin/cred_probe; then
    :
else
    rc=\$?
    echo "tm-cred-runtime-smoke: cred_probe failed \$rc"
fi
EOF
chmod 0644 "$fragment"

echo "tm-cred-runtime-smoke.sh: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory

echo "tm-cred-runtime-smoke.sh: rebuilding quser with LQ libc"
"$MAKE" -C "$ROOT/quser" LIBC_SO="$lq_libc" --no-print-directory

fsqrv_bins="$ROOT/quser/build/test/suite/suite.elf:suite"
fsqrv_bins="$fsqrv_bins $selected_msgpass:test_msgpass"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/test/cred_probe/cred_probe.elf:cred_probe"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/test/syncspace/test_syncspace.elf:test_syncspace"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/utils/time.elf:time"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/utils/sysinfo.elf:sysinfo"

echo "tm-cred-runtime-smoke.sh: rebuilding virtio qrvfs image"
rm -f "$ROOT/build/fsqrv.img" "$ROOT/build/virtio.img"
"$MAKE" -C "$ROOT" virtio FSQRV_BINS="$fsqrv_bins" --no-print-directory

if [ ! -x "$cred_probe_staged" ]; then
    echo "tm-cred-runtime-smoke.sh: staged cred_probe is missing or not executable" >&2
    exit 1
fi

echo "tm-cred-runtime-smoke.sh: rebuilding QSOE/L image with Rust tm_cred"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_CRED=1 \
    QSOE_RUST_TM_PROCFS=1

"$AR" t "$ROOT/lq/build/libtaskman/libtaskman.a" > "$members_log"
if grep -Fxq cred.o "$members_log"; then
    echo "tm-cred-runtime-smoke.sh: Rust-selected libtaskman still contains cred.o" >&2
    exit 1
fi

for symbol in \
    tm_cred_init \
    tm_cred_chdir \
    tm_cred_getcwd \
    tm_cred_umask \
    tm_cred_set \
    tm_cred_change_permitted \
    tm_cred_self_info
do
    if ! "$NM" -g --defined-only "$ROOT/build/rust/tm-providers/libqsoe_tm_providers.a" |
        grep -Eq "[[:space:]]$symbol$"; then
        echo "tm-cred-runtime-smoke.sh: Rust provider archive is missing $symbol" >&2
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
    "$initial_marker"
    "$umask_marker"
    "$cwd_marker"
    "$mutation_marker"
    "$gate_marker"
    "$child_marker"
    "$spawn_marker"
    "$probe_marker"
)
boot_extra_patterns=$(printf '%s\n' "${expected_markers[@]}")

echo "tm-cred-runtime-smoke.sh: booting Rust tm_cred runtime smoke"
FSQRV_BINS="$fsqrv_bins" \
    QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    QSOE_BOOT_EXTRA_PATTERNS="$boot_extra_patterns" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

for expected in "${expected_markers[@]}"; do
    if ! log_has_marker "$expected"; then
        echo "tm-cred-runtime-smoke.sh: missing marker in $log: $expected" >&2
        exit 1
    fi
done

echo "tm-cred-runtime-smoke.sh: runtime smoke passed"
