#!/usr/bin/env bash
#
# Build a QSOE/L image whose boot CPIO carries slogger-rs at /sbin/slogger,
# then boot it under QEMU and wait for login.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/rust-slogger-boot-smoke.sh [-t seconds] [-o log] [--prepare-only] [--keep-running] [-- <emu args>]

Builds a temporary Rust-slogger LQ modpkg.cpio under build/rust-slogger/,
rebuilds the LQ QEMU image with MODPKG_CPIO pointing at it, and delegates to
scripts/boot-smoke.sh while matching "[slogger-rs] alive".

With --prepare-only, the script builds the Rust-slogger LQ image and exits
before starting QEMU. This is intended for narrower smokes that need to
interact with the guest directly.

Environment:
  QSOE_RUST_SLOGGER          must be 1 if set; C slogger is retired
  RUST_SLOGGER_WORKDIR        output directory, default build/rust-slogger
  RUST_SLOGGER_MODPKG_CPIO   output archive, default build/rust-slogger/modpkg-lq-rust-slogger.cpio
  RUST_SLOGGER_BASE_CPIO     intermediate archive, default build/rust-slogger/modpkg-lq-base.cpio
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAKE=${MAKE:-make}
timeout_s=180
log=
prepare_only=0
keep_running=0
emu_args=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        -t|--timeout)
            [ "$#" -ge 2 ] || { echo "rust-slogger-boot-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "rust-slogger-boot-smoke.sh: $1 needs a value" >&2; exit 2; }
            log=$2
            shift 2
            ;;
        --keep-running)
            keep_running=1
            shift
            ;;
        --prepare-only)
            prepare_only=1
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
            echo "rust-slogger-boot-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "rust-slogger-boot-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "rust-slogger-boot-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

case "${QSOE_RUST_SLOGGER:-1}" in
    1|true|TRUE|yes|YES)
        slogger_mode=rust-retired
        slogger_pattern="[slogger-rs] alive"
        ;;
    0|false|FALSE|no|NO)
        echo "rust-slogger-boot-smoke.sh: C slogger is retired" >&2
        exit 2
        ;;
    *)
        echo "rust-slogger-boot-smoke.sh: QSOE_RUST_SLOGGER must be 1 after C retirement" >&2
        exit 2
        ;;
esac

workdir=${RUST_SLOGGER_WORKDIR:-"$ROOT/build/rust-slogger"}
base_cpio=${RUST_SLOGGER_BASE_CPIO:-"$workdir/modpkg-lq-base.cpio"}
if [ -n "${RUST_SLOGGER_MODPKG_CPIO:-}" ]; then
    rust_cpio=$RUST_SLOGGER_MODPKG_CPIO
else
    rust_cpio="$workdir/modpkg-lq-rust-slogger.cpio"
fi
selected_slogger="$ROOT/build/rust/selected/sbin/slogger.elf"
lq_libc="$ROOT/lq/build/libc/libc.so"
lq_rtld="$ROOT/lq/build/rtld/ld-qsoe.so.1"

mkdir -p "$workdir"

echo "rust-slogger-boot-smoke.sh: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory

echo "rust-slogger-boot-smoke.sh: selecting $slogger_mode slogger artifact"
QSOE_RUST_SLOGGER=1 \
    LIBC_SO="$lq_libc" \
    "$MAKE" -C "$ROOT" slogger-artifact --no-print-directory

if [ ! -f "$selected_slogger" ]; then
    echo "rust-slogger-boot-smoke.sh: missing selected slogger at $selected_slogger" >&2
    exit 1
fi

echo "rust-slogger-boot-smoke.sh: building base LQ modpkg.cpio"
"$MAKE" -C "$ROOT/quser" cpio --no-print-directory \
    MODPKG_CPIO="$base_cpio" \
    SBIN_SLOG_ELF="$selected_slogger" \
    LIBC_SO="$lq_libc" \
    RTLD_SO="$lq_rtld" \
    DYNLIBC_SO="$lq_libc"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/qsoe-rust-slogger-cpio.XXXXXX")
cleanup() {
    rm -rf "$tmp"
}
trap cleanup EXIT

list="$tmp/filelist"
rootdir="$tmp/root"
mkdir -p "$rootdir"

cpio --quiet -it < "$base_cpio" > "$list"
if ! grep -Fxq "sbin/slogger" "$list"; then
    echo "rust-slogger-boot-smoke.sh: base cpio has no sbin/slogger entry" >&2
    exit 1
fi

(
    cd "$rootdir"
    cpio --quiet -id --no-absolute-filenames < "$base_cpio"
)

install -m 0755 "$selected_slogger" "$rootdir/sbin/slogger"

(
    cd "$rootdir"
    cpio --quiet --create -H newc \
        --owner=+0:+0 --reproducible \
        --file="$rust_cpio" < "$list"
)
touch "$rust_cpio"
echo "rust-slogger-boot-smoke.sh: wrote $rust_cpio"

echo "rust-slogger-boot-smoke.sh: rebuilding LQ QEMU image with $slogger_mode slogger cpio"
"$MAKE" -C "$ROOT/lq" MODPKG_CPIO="$rust_cpio" --no-print-directory

if [ "$prepare_only" -eq 1 ]; then
    echo "rust-slogger-boot-smoke.sh: prepared $slogger_mode slogger LQ image"
    exit 0
fi

boot_args=(-k lq -t "$timeout_s")
if [ -n "$log" ]; then
    boot_args+=(-o "$log")
fi
if [ "$keep_running" -eq 1 ]; then
    boot_args+=(--keep-running)
fi
if [ "${#emu_args[@]}" -gt 0 ]; then
    boot_args+=(-- "${emu_args[@]}")
fi

QSOE_BOOT_SLOGGER_PATTERN="$slogger_pattern" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"
