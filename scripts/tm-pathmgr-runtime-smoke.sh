#!/usr/bin/env bash
#
# Boot QSOE/L with the retired Rust tm_pathmgr provider and exercise runtime namespace use.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-pathmgr-runtime-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Injects a temporary sysinit fragment that enumerates /dev, follows the cpio
/etc symlink, repaths /dev/console, and runs /usr/bin/pathmgr_probe.  It then
rebuilds the virtio qrvfs image and boots QSOE/L with the retired Rust
tm_pathmgr provider.

This validates the Rust taskman path manager through real boot-time
device registrations, PMDIR readdir, cpio-root symlink expansion, explicit
resolve/repath, duplicate registration rejection, MsgSend through a resolved
external binding, and process-exit unregister cleanup.

Environment:
  TM_PATHMGR_RUNTIME_SMOKE_WORKDIR  output directory, default build/tm-pathmgr-runtime-smoke
  QSOE_RUST_TM_PATHMGR              must remain 1 after C tm_pathmgr retirement
  QSOE_RUST_TM_PROCFS               must remain 1 after C tm_procfs retirement
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
            [ "$#" -ge 2 ] || { echo "tm-pathmgr-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "tm-pathmgr-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "tm-pathmgr-runtime-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "tm-pathmgr-runtime-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "tm-pathmgr-runtime-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

case "${QSOE_RUST_TM_PATHMGR:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_PATHMGR=1
        selected=1
        mode=rust-retired
        expected_pathmgr_count=0
        ;;
    0|false|FALSE|no|NO)
        echo "tm-pathmgr-runtime-smoke.sh: C tm_pathmgr is retired; QSOE_RUST_TM_PATHMGR must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-pathmgr-runtime-smoke.sh: QSOE_RUST_TM_PATHMGR must be 1 after C retirement" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_PROCFS:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_PROCFS=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-pathmgr-runtime-smoke.sh: C tm_procfs is retired; QSOE_RUST_TM_PROCFS must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-pathmgr-runtime-smoke.sh: QSOE_RUST_TM_PROCFS must be 1 after C retirement" >&2
        exit 2
        ;;
esac

workdir=${TM_PATHMGR_RUNTIME_SMOKE_WORKDIR:-"$ROOT/build/tm-pathmgr-runtime-smoke"}
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
lq_libc="$ROOT/lq/build/libc/libc.so"
members_log="$workdir/lq-$mode-libtaskman-members.txt"
probe_staged="$ROOT/build/fsqrv-root/bin/pathmgr_probe"
selected_msgpass="$ROOT/build/rust/selected/usr/bin/test_msgpass.elf"

boot_syscfg_marker="syscfg built from FDT"
boot_sysmap_marker="sysmap page built"
pci_server_marker="[pci-server] scan complete"
dev_marker="tm-pathmgr-runtime-smoke: /dev readdir ok"
etc_marker="tm-pathmgr-runtime-smoke: /etc/passwd symlink ok"
repath_marker="tm-pathmgr-runtime-smoke: /dev/console repath ok"
registered_marker="tm-pathmgr-runtime-smoke: helper registered"
resolved_marker="tm-pathmgr-runtime-smoke: helper resolved"
duplicate_marker="tm-pathmgr-runtime-smoke: duplicate register rejected"
unregistered_marker="tm-pathmgr-runtime-smoke: helper unregistered"
probe_marker="tm-pathmgr-runtime-smoke: pathmgr probe ok"

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-tm-pathmgr-runtime.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "tm-pathmgr-runtime-smoke.sh: missing quser/conf; run make prepare first" >&2
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
    echo "tm-pathmgr-runtime-smoke.sh: no ar tool found" >&2
    exit 127
}
NM=$(find_tool riscv64-linux-gnu-nm nm llvm-nm) || {
    echo "tm-pathmgr-runtime-smoke.sh: no nm tool found" >&2
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
fragment=$(mktemp "$source_sysinit/10-tm-pathmgr-runtime-smoke.XXXXXX.sh")
cat > "$fragment" <<EOF
if /bin/ls /dev >/dev/null 2>&1; then
    echo "$dev_marker"
else
    echo "tm-pathmgr-runtime-smoke: /dev readdir failed"
fi

if /bin/cat /etc/passwd >/dev/null 2>&1; then
    echo "$etc_marker"
else
    echo "tm-pathmgr-runtime-smoke: /etc/passwd symlink failed"
fi

if /bin/syscmd reopen /dev/ser1; then
    echo "$repath_marker"
else
    echo "tm-pathmgr-runtime-smoke: /dev/console repath failed"
fi

if /usr/bin/pathmgr_probe; then
    :
else
    rc=\$?
    echo "tm-pathmgr-runtime-smoke: pathmgr_probe failed \$rc"
fi
EOF
chmod 0644 "$fragment"

echo "tm-pathmgr-runtime-smoke.sh: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory \
    QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_PATHMGR="$selected" \
    QSOE_RUST_TM_PSEUDODEV=1 \
    QSOE_RUST_TM_RSRCDB=1

echo "tm-pathmgr-runtime-smoke.sh: rebuilding quser with LQ libc"
"$MAKE" -C "$ROOT/quser" LIBC_SO="$lq_libc" --no-print-directory

fsqrv_bins="$ROOT/quser/build/test/suite/suite.elf:suite"
fsqrv_bins="$fsqrv_bins $selected_msgpass:test_msgpass"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/test/pathmgr_probe/pathmgr_probe.elf:pathmgr_probe"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/test/syncspace/test_syncspace.elf:test_syncspace"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/utils/time.elf:time"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/utils/sysinfo.elf:sysinfo"

echo "tm-pathmgr-runtime-smoke.sh: rebuilding virtio qrvfs image"
rm -f "$ROOT/build/fsqrv.img" "$ROOT/build/virtio.img"
"$MAKE" -C "$ROOT" virtio FSQRV_BINS="$fsqrv_bins" --no-print-directory

if [ ! -x "$probe_staged" ]; then
    echo "tm-pathmgr-runtime-smoke.sh: staged pathmgr_probe is missing or not executable" >&2
    exit 1
fi

echo "tm-pathmgr-runtime-smoke.sh: rebuilding QSOE/L image with mode=$mode"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_PATHMGR="$selected" \
    QSOE_RUST_TM_PSEUDODEV=1 \
    QSOE_RUST_TM_RSRCDB=1

"$AR" t "$ROOT/lq/build/libtaskman/libtaskman.a" > "$members_log"
pathmgr_count=$(awk '$0 == "pathmgr.o" { n++ } END { print n + 0 }' "$members_log")
printf 'tm-pathmgr-runtime-smoke.sh: %s pathmgr.o count: %s\n' "$mode" "$pathmgr_count" |
    tee "$workdir/lq-$mode-libtaskman-membership.txt"
if [ "$pathmgr_count" -ne "$expected_pathmgr_count" ]; then
    echo "tm-pathmgr-runtime-smoke.sh: $mode expected $expected_pathmgr_count pathmgr.o members, got $pathmgr_count" >&2
    exit 1
fi

if [ "$selected" -eq 1 ]; then
    for symbol in \
        tm_pathmgr_init \
        tm_pathmgr_register \
        tm_pathmgr_unregister_pid \
        tm_pathmgr_resolve \
        tm_pathmgr_repath \
        tm_pathmgr_symlink \
        tm_pathmgr_expand_symlink_cpio \
        tm_pathmgr_expand_symlink \
        tm_pathmgr_child_at
    do
        if ! "$NM" -g --defined-only "$ROOT/build/rust/tm-providers/libqsoe_tm_providers.a" |
            grep -Eq "[[:space:]]$symbol$"; then
            echo "tm-pathmgr-runtime-smoke.sh: Rust provider archive is missing $symbol" >&2
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
    "$boot_syscfg_marker"
    "$boot_sysmap_marker"
    "$pci_server_marker"
    "$dev_marker"
    "$etc_marker"
    "$repath_marker"
    "$registered_marker"
    "$resolved_marker"
    "$duplicate_marker"
    "$unregistered_marker"
    "$probe_marker"
)
boot_extra_patterns=$(printf '%s\n' "${expected_markers[@]}")

echo "tm-pathmgr-runtime-smoke.sh: booting tm_pathmgr runtime smoke mode=$mode"
FSQRV_BINS="$fsqrv_bins" \
    QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    QSOE_BOOT_EXTRA_PATTERNS="$boot_extra_patterns" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

for expected in "${expected_markers[@]}"; do
    if ! log_has_marker "$expected"; then
        echo "tm-pathmgr-runtime-smoke.sh: missing marker in $log: $expected" >&2
        exit 1
    fi
done

echo "tm-pathmgr-runtime-smoke.sh: runtime smoke passed"
