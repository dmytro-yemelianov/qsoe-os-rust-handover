#!/usr/bin/env bash
#
# Build an opt-in QSOE/L image whose boot CPIO carries the selected
# /sbin/devb-virtio artifact, then boot it under QEMU and wait for login. Rust
# is selected by default; set QSOE_RUST_VIRTIO=0 for the C rollback path.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/rust-virtio-boot-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds a temporary selected-virtio LQ modpkg.cpio under build/rust-virtio/,
rebuilds the LQ QEMU image with MODPKG_CPIO pointing at it, and delegates to
scripts/boot-smoke.sh while matching the selected devb-virtio readiness marker.

Environment:
  QSOE_RUST_VIRTIO          set 0 to prepare the C rollback image
  RUST_VIRTIO_WORKDIR       output directory, default build/rust-virtio
  RUST_VIRTIO_MODPKG_CPIO   output archive, default under RUST_VIRTIO_WORKDIR
  RUST_VIRTIO_BASE_CPIO     intermediate C archive, default under RUST_VIRTIO_WORKDIR
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
            [ "$#" -ge 2 ] || { echo "rust-virtio-boot-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "rust-virtio-boot-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "rust-virtio-boot-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "rust-virtio-boot-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "rust-virtio-boot-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

QSOE_RUST_VIRTIO=${QSOE_RUST_VIRTIO:-1}
case "$QSOE_RUST_VIRTIO" in
    0|false|FALSE|no|NO)
        virtio_mode=c
        virtio_pattern="devb-virtio: /dev/vblk0 ready"
        ;;
    1|true|TRUE|yes|YES)
        virtio_mode=rust
        virtio_pattern="[devb-virtio-rs] /dev/vblk0 ready"
        ;;
    *)
        echo "rust-virtio-boot-smoke.sh: QSOE_RUST_VIRTIO must be 0 or 1" >&2
        exit 2
        ;;
esac
export QSOE_RUST_VIRTIO

workdir=${RUST_VIRTIO_WORKDIR:-"$ROOT/build/rust-virtio"}
base_cpio=${RUST_VIRTIO_BASE_CPIO:-"$workdir/modpkg-lq-c.cpio"}
selected_cpio=${RUST_VIRTIO_MODPKG_CPIO:-"$workdir/modpkg-lq-$virtio_mode-virtio.cpio"}
selected_virtio="$ROOT/build/rust/selected/sbin/devb-virtio.elf"
lq_libc="$ROOT/lq/build/libc/libc.so"
lq_rtld="$ROOT/lq/build/rtld/ld-qsoe.so.1"

mkdir -p "$workdir"

echo "rust-virtio-boot-smoke.sh: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory

echo "rust-virtio-boot-smoke.sh: selecting $virtio_mode virtio artifact"
QSOE_RUST_VIRTIO="$QSOE_RUST_VIRTIO" \
    LIBC_SO="$lq_libc" \
    "$MAKE" -C "$ROOT" virtio-artifact --no-print-directory

echo "rust-virtio-boot-smoke.sh: building base LQ modpkg.cpio"
"$MAKE" -C "$ROOT/quser" cpio --no-print-directory \
    MODPKG_CPIO="$base_cpio" \
    LIBC_SO="$lq_libc" \
    RTLD_SO="$lq_rtld" \
    DYNLIBC_SO="$lq_libc"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/qsoe-rust-virtio-cpio.XXXXXX")
cleanup() {
    rm -rf "$tmp"
}
trap cleanup EXIT

list="$tmp/filelist"
rootdir="$tmp/root"
mkdir -p "$rootdir"

cpio --quiet -it < "$base_cpio" > "$list"
if ! grep -Fxq "sbin/devb-virtio" "$list"; then
    echo "rust-virtio-boot-smoke.sh: base cpio has no sbin/devb-virtio entry" >&2
    exit 1
fi

(
    cd "$rootdir"
    cpio --quiet -id --no-absolute-filenames < "$base_cpio"
)

install -m 0755 "$selected_virtio" "$rootdir/sbin/devb-virtio"

(
    cd "$rootdir"
    cpio --quiet --create -H newc \
        --owner=+0:+0 --reproducible \
        --file="$selected_cpio" < "$list"
)
touch "$selected_cpio"
echo "rust-virtio-boot-smoke.sh: wrote $selected_cpio"

echo "rust-virtio-boot-smoke.sh: rebuilding LQ QEMU image with $virtio_mode virtio cpio"
"$MAKE" -C "$ROOT/lq" MODPKG_CPIO="$selected_cpio" --no-print-directory

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

QSOE_BOOT_VIRTIO_PATTERN="$virtio_pattern" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"
