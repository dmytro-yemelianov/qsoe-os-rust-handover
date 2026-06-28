#!/usr/bin/env bash
#
# Boot QSOE/L with the selected virtio block driver and a temporary on-disk
# sysinit fragment that reads a file from /usr. Rust is selected by default;
# set QSOE_RUST_VIRTIO=0 for the C rollback path.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/rust-virtio-file-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Adds a temporary quser/conf/sysinit fragment before delegating to
scripts/rust-virtio-boot-smoke.sh. The normal virtio image build stages that
fragment into /usr/conf/sysinit, where it runs in the guest after /usr is
mounted and verifies that /bin/cat can read /usr/conf/passwd.

Environment:
  QSOE_RUST_VIRTIO          set 0 to prepare the C rollback image
  RUST_VIRTIO_FILE_WORKDIR   output directory, default build/rust-virtio-file
EOF
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
timeout_s=180
log=
keep_running=0
emu_args=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        -t|--timeout)
            [ "$#" -ge 2 ] || { echo "rust-virtio-file-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "rust-virtio-file-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "rust-virtio-file-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "rust-virtio-file-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "rust-virtio-file-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

QSOE_RUST_VIRTIO=${QSOE_RUST_VIRTIO:-1}
case "$QSOE_RUST_VIRTIO" in
    0|false|FALSE|no|NO)
        virtio_mode=c
        ;;
    1|true|TRUE|yes|YES)
        virtio_mode=rust
        ;;
    *)
        echo "rust-virtio-file-smoke.sh: QSOE_RUST_VIRTIO must be 0 or 1" >&2
        exit 2
        ;;
esac
export QSOE_RUST_VIRTIO

workdir=${RUST_VIRTIO_FILE_WORKDIR:-"$ROOT/build/rust-virtio-file"}
marker="rust-virtio-file-smoke: read /usr/conf/passwd ok"
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=

if [ -z "$log" ]; then
    log="$workdir/boot-smoke-lq-$virtio_mode-virtio-file.log"
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "rust-virtio-file-smoke.sh: missing quser/conf; run make prepare first" >&2
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
fragment=$(mktemp "$source_sysinit/10-rust-virtio-file-smoke.XXXXXX.sh")
cat > "$fragment" <<'EOF'
if /bin/cat /usr/conf/passwd >/dev/null 2>&1; then
    echo "rust-virtio-file-smoke: read /usr/conf/passwd ok"
else
    echo "rust-virtio-file-smoke: read /usr/conf/passwd failed"
fi
EOF
chmod 0644 "$fragment"

boot_args=(-t "$timeout_s" -o "$log")
if [ "$keep_running" -eq 1 ]; then
    boot_args+=(--keep-running)
fi
if [ "${#emu_args[@]}" -gt 0 ]; then
    boot_args+=(-- "${emu_args[@]}")
fi

echo "rust-virtio-file-smoke.sh: booting $virtio_mode virtio with temporary /usr file-read fragment"
"$ROOT/scripts/rust-virtio-boot-smoke.sh" "${boot_args[@]}"

if ! grep -Fq "$marker" "$log"; then
    echo "rust-virtio-file-smoke.sh: missing marker in $log: $marker" >&2
    exit 1
fi

echo "rust-virtio-file-smoke.sh: /usr file read smoke passed"
