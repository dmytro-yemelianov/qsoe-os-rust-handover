#!/usr/bin/env bash
#
# Boot QSOE/L with Rust tm_script selected and exercise direct script spawn.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/tm-script-runtime-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Adds a temporary /usr/bin/tm_script_probe shell script to the virtio qrvfs
image, injects a sysinit fragment that runs it directly, and boots QSOE/L with
Rust tm_script selected. Running the probe by path forces taskman spawn to
parse the script shebang before loading /bin/sh.

Environment:
  TM_SCRIPT_RUNTIME_SMOKE_WORKDIR  output directory, default build/tm-script-runtime-smoke
  QSOE_RUST_TM_SCRIPT              must remain 1 after C tm_script retirement
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
            [ "$#" -ge 2 ] || { echo "tm-script-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "tm-script-runtime-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "tm-script-runtime-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "tm-script-runtime-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "tm-script-runtime-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

tm_script_mode=
case "${QSOE_RUST_TM_SCRIPT:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_SCRIPT=1
        tm_script_mode=rust-retired
        ;;
    0|false|FALSE|no|NO)
        echo "tm-script-runtime-smoke.sh: C tm_script is retired; QSOE_RUST_TM_SCRIPT must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-script-runtime-smoke.sh: QSOE_RUST_TM_SCRIPT must be 1 after C retirement" >&2
        exit 2
        ;;
esac

case "${QSOE_RUST_TM_PROCFS:-1}" in
    1|true|TRUE|yes|YES)
        export QSOE_RUST_TM_PROCFS=1
        ;;
    0|false|FALSE|no|NO)
        echo "tm-script-runtime-smoke.sh: C tm_procfs is retired; QSOE_RUST_TM_PROCFS must be 1" >&2
        exit 2
        ;;
    *)
        echo "tm-script-runtime-smoke.sh: QSOE_RUST_TM_PROCFS must be 1 after C retirement" >&2
        exit 2
        ;;
esac

workdir=${TM_SCRIPT_RUNTIME_SMOKE_WORKDIR:-"$ROOT/build/tm-script-runtime-smoke"}
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
probe="$workdir/tm_script_probe"
lq_libc="$ROOT/lq/build/libc/libc.so"
selected_msgpass="$ROOT/build/rust/selected/usr/bin/test_msgpass.elf"

script_marker="tm-script-runtime-smoke: direct shebang spawn ok"
exit_marker="tm-script-runtime-smoke: probe exited 0"

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-tm-script-runtime.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "tm-script-runtime-smoke.sh: missing quser/conf; run make prepare first" >&2
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

cat > "$probe" <<EOF
#!/bin/sh
echo "$script_marker"
EOF
chmod 0755 "$probe"

mkdir -p "$source_sysinit"
fragment=$(mktemp "$source_sysinit/10-tm-script-runtime-smoke.XXXXXX.sh")
cat > "$fragment" <<EOF
if /usr/bin/tm_script_probe; then
    echo "$exit_marker"
else
    rc=\$?
    echo "tm-script-runtime-smoke: probe failed \$rc"
fi
EOF
chmod 0644 "$fragment"

echo "tm-script-runtime-smoke.sh: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory

echo "tm-script-runtime-smoke.sh: rebuilding quser with LQ libc"
"$MAKE" -C "$ROOT/quser" LIBC_SO="$lq_libc" --no-print-directory

fsqrv_bins="$ROOT/quser/build/test/suite/suite.elf:suite"
fsqrv_bins="$fsqrv_bins $selected_msgpass:test_msgpass"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/test/syncspace/test_syncspace.elf:test_syncspace"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/utils/time.elf:time"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/utils/sysinfo.elf:sysinfo"
fsqrv_bins="$fsqrv_bins $probe:tm_script_probe"

echo "tm-script-runtime-smoke.sh: rebuilding virtio qrvfs image with script probe"
"$MAKE" -C "$ROOT" virtio FSQRV_BINS="$fsqrv_bins" --no-print-directory

if ! grep -Fq "$script_marker" "$ROOT/build/fsqrv-root/bin/tm_script_probe"; then
    echo "tm-script-runtime-smoke.sh: staged script probe is unexpected" >&2
    exit 1
fi
if [ ! -x "$ROOT/build/fsqrv-root/bin/tm_script_probe" ]; then
    echo "tm-script-runtime-smoke.sh: staged script probe is not executable" >&2
    exit 1
fi

echo "tm-script-runtime-smoke.sh: rebuilding QSOE/L image with $tm_script_mode tm_script"
"$MAKE" -C "$ROOT/lq" --no-print-directory \
    QSOE_RUST_TM_PROCFS=1 \
    QSOE_RUST_TM_SCRIPT="$QSOE_RUST_TM_SCRIPT"

boot_args=(-k lq -t "$timeout_s" -o "$log")
if [ "$keep_running" -eq 1 ]; then
    boot_args+=(--keep-running)
fi
if [ "${#emu_args[@]}" -gt 0 ]; then
    boot_args+=(-- "${emu_args[@]}")
fi

expected_markers=(
    "$script_marker" \
    "$exit_marker"
)
boot_extra_patterns=$(printf '%s\n' "${expected_markers[@]}")

echo "tm-script-runtime-smoke.sh: booting $tm_script_mode tm_script runtime smoke"
FSQRV_BINS="$fsqrv_bins" \
    QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    QSOE_BOOT_EXTRA_PATTERNS="$boot_extra_patterns" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

for expected in "${expected_markers[@]}"; do
    if ! log_has_marker "$expected"; then
        echo "tm-script-runtime-smoke.sh: missing marker in $log: $expected" >&2
        exit 1
    fi
done

echo "tm-script-runtime-smoke.sh: runtime smoke passed"
