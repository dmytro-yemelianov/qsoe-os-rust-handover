#!/usr/bin/env bash
#
# Boot QSOE/L with an opt-in Rust /usr/bin/test_msgpass helper and run the
# existing suite [msgpass] path from a temporary sysinit fragment.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/rust-test-msgpass-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds qsoe-test-msgpass-rs, stages it at /usr/bin/test_msgpass in a
temporary virtio qrvfs image, injects a sysinit fragment that runs
/usr/bin/suite, and verifies the existing [msgpass] suite markers.

Environment:
  RUST_TEST_MSGPASS_WORKDIR   output directory, default build/rust-test-msgpass
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
timeout_s=240
log=
keep_running=0
emu_args=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        -t|--timeout)
            [ "$#" -ge 2 ] || { echo "rust-test-msgpass-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "rust-test-msgpass-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "rust-test-msgpass-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "rust-test-msgpass-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "rust-test-msgpass-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

workdir=${RUST_TEST_MSGPASS_WORKDIR:-"$ROOT/build/rust-test-msgpass"}
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
lq_libc="$ROOT/lq/build/libc/libc.so"
selected_helper="$ROOT/build/rust/selected/usr/bin/test_msgpass.elf"

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-rust-test-msgpass.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "rust-test-msgpass-smoke.sh: missing quser/conf; run make prepare first" >&2
    exit 1
fi

log_has_marker() {
    local marker=$1

    grep -Fq "$marker" "$log" ||
        tr -d '\r\n' < "$log" | grep -Fq "$marker"
}

cleanup() {
    if [ -n "$fragment" ]; then
        rm -f "$fragment"
    fi
    rmdir "$source_sysinit" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$source_sysinit"
fragment=$(mktemp "$source_sysinit/10-rust-test-msgpass.XXXXXX.sh")
cat > "$fragment" <<'EOF'
echo "rust-test-msgpass-smoke: starting /usr/bin/suite"
/usr/bin/suite
echo "rust-test-msgpass-smoke: suite exited $?"
EOF
chmod 0644 "$fragment"

echo "rust-test-msgpass-smoke.sh: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory

echo "rust-test-msgpass-smoke.sh: building Rust test_msgpass helper"
QSOE_RUST_TEST_MSGPASS=1 \
    LIBC_SO="$lq_libc" \
    SELECTED_TEST_MSGPASS_ELF="$selected_helper" \
    "$MAKE" -C "$ROOT" test-msgpass-artifact --no-print-directory

echo "rust-test-msgpass-smoke.sh: rebuilding quser with LQ libc"
"$MAKE" -C "$ROOT/quser" LIBC_SO="$lq_libc" --no-print-directory

fsqrv_bins="$ROOT/quser/build/test/suite/suite.elf:suite"
fsqrv_bins="$fsqrv_bins $selected_helper:test_msgpass"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/test/syncspace/test_syncspace.elf:test_syncspace"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/utils/time.elf:time"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/utils/sysinfo.elf:sysinfo"

echo "rust-test-msgpass-smoke.sh: rebuilding virtio qrvfs image with Rust helper"
"$MAKE" -C "$ROOT" virtio FSQRV_BINS="$fsqrv_bins" --no-print-directory

if ! strings -a "$ROOT/build/fsqrv-root/bin/test_msgpass" | \
        grep -Fq "[test_msgpass-rs] /dev/msgpass registered"; then
    echo "rust-test-msgpass-smoke.sh: staged test_msgpass is not the Rust helper" >&2
    exit 1
fi

echo "rust-test-msgpass-smoke.sh: rebuilding LQ image"
"$MAKE" -C "$ROOT/lq" --no-print-directory

boot_args=(-k lq -t "$timeout_s" -o "$log")
if [ "$keep_running" -eq 1 ]; then
    boot_args+=(--keep-running)
fi
if [ "${#emu_args[@]}" -gt 0 ]; then
    boot_args+=(-- "${emu_args[@]}")
fi

echo "rust-test-msgpass-smoke.sh: booting Rust test_msgpass suite smoke"
FSQRV_BINS="$fsqrv_bins" \
    QSOE_BOOT_SLOGGER_PATTERN="fs-qrv: mounted qrvfs at /usr" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

for expected in \
    "[test_msgpass-rs] alive" \
    "PASS  msgpass: resolve /dev/msgpass" \
    "PASS  msgpass: 4MB-2 round-trip" \
    "PASS  msgpass: payload halfword-swapped" \
    "PASS  msgpass: server exited clean" \
    "SKIP  msgpass: no-reply exit -> ESRVRFAULT" \
    "rust-test-msgpass-smoke: suite exited"; do
    if ! log_has_marker "$expected"; then
        echo "rust-test-msgpass-smoke.sh: missing marker in $log: $expected" >&2
        exit 1
    fi
done

echo "rust-test-msgpass-smoke.sh: Rust test_msgpass suite smoke passed"
