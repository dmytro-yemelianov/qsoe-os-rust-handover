#!/usr/bin/env bash
#
# Boot QSOE/L with the selected tm_rsrcdb provider and exercise live rsrcdbmgr calls.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-rsrcdb-runtime-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Injects a temporary sysinit fragment that runs /usr/bin/rsrcdb_probe, rebuilds
the virtio qrvfs image with that helper staged, and boots QSOE/L with the
selected tm_rsrcdb provider. The default is the Rust provider.

The helper exercises public rsrcdbmgr_* create, attach, query, detach, and
destroy calls against the selected taskman resource DB provider.

Environment:
  TM_RSRCDB_RUNTIME_SMOKE_WORKDIR  output directory, default build/tm-rsrcdb-runtime-smoke
  QSOE_RUST_TM_RSRCDB              1 for Rust default, 0 only with TM_RSRCDB_RUNTIME_ALLOW_C=1
  TM_RSRCDB_RUNTIME_ALLOW_C        permit C rollback validation when QSOE_RUST_TM_RSRCDB=0
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
            [ "$#" -ge 2 ] || { echo "tm-rsrcdb-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "tm-rsrcdb-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "tm-rsrcdb-runtime-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "tm-rsrcdb-runtime-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "tm-rsrcdb-runtime-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

case "${QSOE_RUST_TM_RSRCDB:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_RSRCDB=1
        selected=1
        mode=rust-default
        expected_rsrcdb_count=0
        ;;
    0|false|FALSE|no|NO)
        case "${TM_RSRCDB_RUNTIME_ALLOW_C:-0}" in
            1|true|TRUE|yes|YES)
                export QSOE_RUST_TM_RSRCDB=0
                selected=0
                mode=c-rollback
                expected_rsrcdb_count=2
                ;;
            *)
                echo "tm-rsrcdb-runtime-smoke.sh: QSOE_RUST_TM_RSRCDB=0 is only allowed with TM_RSRCDB_RUNTIME_ALLOW_C=1" >&2
                exit 2
                ;;
        esac
        ;;
    *)
        echo "tm-rsrcdb-runtime-smoke.sh: QSOE_RUST_TM_RSRCDB must be 0 or 1" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_PROCFS:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_PROCFS=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-rsrcdb-runtime-smoke.sh: C tm_procfs is retired; QSOE_RUST_TM_PROCFS must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-rsrcdb-runtime-smoke.sh: QSOE_RUST_TM_PROCFS must be 1 after C retirement" >&2
        exit 2
        ;;
esac

workdir=${TM_RSRCDB_RUNTIME_SMOKE_WORKDIR:-"$ROOT/build/tm-rsrcdb-runtime-smoke"}
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
lq_libc="$ROOT/lq/build/libc/libc.so"
plan_log="$workdir/lq-$mode-taskman-dry-run.txt"
rsrcdb_probe_staged="$ROOT/build/fsqrv-root/bin/rsrcdb_probe"
selected_msgpass="$ROOT/build/rust/selected/usr/bin/test_msgpass.elf"

boot_syscfg_marker="syscfg built from FDT"
boot_sysmap_marker="sysmap page built"
create_marker="tm-rsrcdb-runtime-smoke: create ok"
query_create_marker="tm-rsrcdb-runtime-smoke: query create ok"
attach_marker="tm-rsrcdb-runtime-smoke: attach ok"
query_attach_marker="tm-rsrcdb-runtime-smoke: query attach ok"
detach_marker="tm-rsrcdb-runtime-smoke: detach merge ok"
destroy_marker="tm-rsrcdb-runtime-smoke: destroy ok"
probe_marker="tm-rsrcdb-runtime-smoke: rsrcdb probe ok"

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-tm-rsrcdb-runtime.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "tm-rsrcdb-runtime-smoke.sh: missing quser/conf; run make prepare first" >&2
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
    echo "tm-rsrcdb-runtime-smoke.sh: no nm tool found" >&2
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
fragment=$(mktemp "$source_sysinit/10-tm-rsrcdb-runtime-smoke.XXXXXX.sh")
cat > "$fragment" <<EOF
if /usr/bin/rsrcdb_probe; then
    :
else
    rc=\$?
    echo "tm-rsrcdb-runtime-smoke: rsrcdb_probe failed \$rc"
fi
EOF
chmod 0644 "$fragment"

echo "tm-rsrcdb-runtime-smoke.sh: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory \
    QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_RSRCDB="$selected"

echo "tm-rsrcdb-runtime-smoke.sh: rebuilding quser with LQ libc"
"$MAKE" -C "$ROOT/quser" LIBC_SO="$lq_libc" --no-print-directory

fsqrv_bins="$ROOT/quser/build/test/suite/suite.elf:suite"
fsqrv_bins="$fsqrv_bins $selected_msgpass:test_msgpass"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/test/rsrcdb_probe/rsrcdb_probe.elf:rsrcdb_probe"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/test/syncspace/test_syncspace.elf:test_syncspace"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/utils/time.elf:time"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/utils/sysinfo.elf:sysinfo"

echo "tm-rsrcdb-runtime-smoke.sh: rebuilding virtio qrvfs image"
rm -f "$ROOT/build/fsqrv.img" "$ROOT/build/virtio.img"
"$MAKE" -C "$ROOT" virtio FSQRV_BINS="$fsqrv_bins" --no-print-directory

if [ ! -x "$rsrcdb_probe_staged" ]; then
    echo "tm-rsrcdb-runtime-smoke.sh: staged rsrcdb_probe is missing or not executable" >&2
    exit 1
fi

echo "tm-rsrcdb-runtime-smoke.sh: capturing $mode tm_rsrcdb LQ taskman link plan"
"$MAKE" -C "$ROOT/lq/taskman" --no-print-directory -B -n all \
    LIBTASKMAN_A="$ROOT/lq/build/libtaskman/libtaskman.a" \
    LIBTASKMAN_INC="$ROOT/libtaskman/include" \
    QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_RSRCDB="$selected" \
    > "$plan_log"

rsrcdb_count=$(grep -Fo '/sys/rsrcdb.o' "$plan_log" | wc -l | tr -d ' ')
if [ "$rsrcdb_count" -ne "$expected_rsrcdb_count" ]; then
    echo "tm-rsrcdb-runtime-smoke.sh: $mode expected $expected_rsrcdb_count sys/rsrcdb.o dry-run entries, got $rsrcdb_count" >&2
    exit 1
fi
if [ "$selected" -eq 1 ] && ! grep -Fq 'libqsoe_tm_providers.a' "$plan_log"; then
    echo "tm-rsrcdb-runtime-smoke.sh: Rust-default taskman link plan omits libqsoe_tm_providers.a" >&2
    exit 1
fi

echo "tm-rsrcdb-runtime-smoke.sh: rebuilding QSOE/L image with $mode tm_rsrcdb"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_RSRCDB="$selected"

if [ "$selected" -eq 1 ]; then
    for symbol in \
        tm_rsrc_init \
        tm_rsrc_create \
        tm_rsrc_destroy \
        tm_rsrc_attach \
        tm_rsrc_detach \
        tm_rsrc_query \
        tm_rsrc_release_pid \
        tm_rsrc_seed_from_syscfg
    do
        if ! "$NM" -g --defined-only "$ROOT/build/rust/tm-providers/libqsoe_tm_providers.a" |
            grep -Eq "[[:space:]]$symbol$"; then
            echo "tm-rsrcdb-runtime-smoke.sh: Rust provider archive is missing $symbol" >&2
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
    "$create_marker"
    "$query_create_marker"
    "$attach_marker"
    "$query_attach_marker"
    "$detach_marker"
    "$destroy_marker"
    "$probe_marker"
)
boot_extra_patterns=$(printf '%s\n' "${expected_markers[@]}")

echo "tm-rsrcdb-runtime-smoke.sh: booting $mode tm_rsrcdb runtime smoke"
FSQRV_BINS="$fsqrv_bins" \
    QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    QSOE_BOOT_EXTRA_PATTERNS="$boot_extra_patterns" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

for expected in "${expected_markers[@]}"; do
    if ! log_has_marker "$expected"; then
        echo "tm-rsrcdb-runtime-smoke.sh: missing marker in $log: $expected" >&2
        exit 1
    fi
done

echo "tm-rsrcdb-runtime-smoke.sh: runtime smoke passed"
