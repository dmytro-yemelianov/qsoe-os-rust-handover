#!/usr/bin/env bash
#
# Boot QSOE/L with an opt-in Rust /sbin/pipe and verify registration.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/rust-pipe-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds a temporary Rust-pipe LQ modpkg.cpio under build/rust-pipe/,
rebuilds the LQ QEMU image with MODPKG_CPIO pointing at it, injects a sysinit
fragment that starts /sbin/pipe, and verifies the Rust pipe registration marker.

Environment:
  RUST_PIPE_MODPKG_CPIO   output archive, default build/rust-pipe/modpkg-lq-rust-pipe.cpio
  RUST_PIPE_BASE_CPIO     intermediate C archive, default build/rust-pipe/modpkg-lq-c.cpio
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
            [ "$#" -ge 2 ] || { echo "rust-pipe-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "rust-pipe-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "rust-pipe-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "rust-pipe-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "rust-pipe-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

workdir=${RUST_PIPE_WORKDIR:-"$ROOT/build/rust-pipe"}
base_cpio=${RUST_PIPE_BASE_CPIO:-"$workdir/modpkg-lq-c.cpio"}
rust_cpio=${RUST_PIPE_MODPKG_CPIO:-"$workdir/modpkg-lq-rust-pipe.cpio"}
selected_pipe="$ROOT/build/rust/selected/sbin/pipe.elf"
lq_libc="$ROOT/lq/build/libc/libc.so"
lq_rtld="$ROOT/lq/build/rtld/ld-qsoe.so.1"
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
marker="rust-pipe-smoke: started /sbin/pipe"
registration="[pipe-rs] /dev/pipe registered"

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-rust-pipe.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "rust-pipe-smoke.sh: missing quser/conf; run make prepare first" >&2
    exit 1
fi

cleanup() {
    if [ -n "$fragment" ]; then
        rm -f "$fragment"
    fi
    rmdir "$source_sysinit" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$source_sysinit"
fragment=$(mktemp "$source_sysinit/10-rust-pipe-smoke.XXXXXX.sh")
cat > "$fragment" <<'EOF'
if /sbin/pipe; then
    echo "rust-pipe-smoke: started /sbin/pipe"
else
    echo "rust-pipe-smoke: failed to start /sbin/pipe"
fi
EOF
chmod 0644 "$fragment"

echo "rust-pipe-smoke.sh: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory

echo "rust-pipe-smoke.sh: selecting Rust pipe artifact"
QSOE_RUST_PIPE=1 \
    LIBC_SO="$lq_libc" \
    "$MAKE" -C "$ROOT" pipe-artifact --no-print-directory

echo "rust-pipe-smoke.sh: building base LQ modpkg.cpio"
"$MAKE" -C "$ROOT/quser" cpio --no-print-directory \
    MODPKG_CPIO="$base_cpio" \
    LIBC_SO="$lq_libc" \
    RTLD_SO="$lq_rtld" \
    DYNLIBC_SO="$lq_libc"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/qsoe-rust-pipe-cpio.XXXXXX")
cleanup_tmp() {
    rm -rf "$tmp"
}
trap 'cleanup_tmp; cleanup' EXIT

list="$tmp/filelist"
rootdir="$tmp/root"
mkdir -p "$rootdir"

cpio --quiet -it < "$base_cpio" > "$list"
if ! grep -Fxq "sbin/pipe" "$list"; then
    echo "rust-pipe-smoke.sh: base cpio has no sbin/pipe entry" >&2
    exit 1
fi

(
    cd "$rootdir"
    cpio --quiet -id --no-absolute-filenames < "$base_cpio"
)

install -m 0755 "$selected_pipe" "$rootdir/sbin/pipe"

(
    cd "$rootdir"
    cpio --quiet --create -H newc \
        --owner=+0:+0 --reproducible \
        --file="$rust_cpio" < "$list"
)
touch "$rust_cpio"
echo "rust-pipe-smoke.sh: wrote $rust_cpio"

echo "rust-pipe-smoke.sh: rebuilding LQ QEMU image with Rust pipe cpio"
"$MAKE" -C "$ROOT/lq" MODPKG_CPIO="$rust_cpio" --no-print-directory

boot_args=(-k lq -t "$timeout_s" -o "$log")
if [ "$keep_running" -eq 1 ]; then
    boot_args+=(--keep-running)
fi
if [ "${#emu_args[@]}" -gt 0 ]; then
    boot_args+=(-- "${emu_args[@]}")
fi

echo "rust-pipe-smoke.sh: booting Rust pipe smoke"
QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

for expected in "$marker" "$registration"; do
    if ! grep -Fq "$expected" "$log"; then
        echo "rust-pipe-smoke.sh: missing marker in $log: $expected" >&2
        exit 1
    fi
done

echo "rust-pipe-smoke.sh: Rust pipe registration smoke passed"
