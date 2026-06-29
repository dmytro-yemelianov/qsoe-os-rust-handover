#!/usr/bin/env bash
#
# Boot QSOE/L with a selected /sbin/pipe and verify pipe(2) data flow.

set -eu

usage() {
    cat <<'EOF'
usage: scripts/rust-pipe-data-smoke.sh [-t seconds] [-o log] [--keep-running] [-- <emu args>]

Builds a temporary LQ modpkg.cpio under build/rust-pipe-data/, stages a focused
/usr/bin/test_pipe_data helper into a temporary qrvfs image, starts /sbin/pipe
from sysinit, and verifies a libc/taskman pipe(2) write/read round trip through
the selected pipe service. Rust is selected by default; set QSOE_RUST_PIPE=0
for the C rollback path.

Environment:
  QSOE_RUST_PIPE             selected artifact mode, default 1 (Rust)
                              set 0 to prepare the C rollback image
  RUST_PIPE_DATA_MODPKG_CPIO  output archive, default is mode-specific under build/rust-pipe-data/
  RUST_PIPE_DATA_BASE_CPIO    intermediate C archive, default build/rust-pipe-data/modpkg-lq-c.cpio
  RUST_PIPE_DATA_WORKDIR      output directory, default build/rust-pipe-data
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
            [ "$#" -ge 2 ] || { echo "rust-pipe-data-smoke.sh: $1 needs a value" >&2; exit 2; }
            timeout_s=$2
            shift 2
            ;;
        -o|--log)
            [ "$#" -ge 2 ] || { echo "rust-pipe-data-smoke.sh: $1 needs a value" >&2; exit 2; }
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
            echo "rust-pipe-data-smoke.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$timeout_s" in
    ''|*[!0-9]*)
        echo "rust-pipe-data-smoke.sh: timeout must be a positive integer" >&2
        exit 2
        ;;
esac

if [ "$timeout_s" -le 0 ]; then
    echo "rust-pipe-data-smoke.sh: timeout must be greater than zero" >&2
    exit 2
fi

QSOE_RUST_PIPE=${QSOE_RUST_PIPE:-1}
case "$QSOE_RUST_PIPE" in
    0|false|FALSE|no|NO)
        pipe_mode=c
        registration="[pipe] registered at /dev/pipe"
        ;;
    1|true|TRUE|yes|YES)
        pipe_mode=rust
        registration="[pipe-rs] /dev/pipe registered"
        ;;
    *)
        echo "rust-pipe-data-smoke.sh: QSOE_RUST_PIPE must be 0 or 1" >&2
        exit 2
        ;;
esac

workdir=${RUST_PIPE_DATA_WORKDIR:-"$ROOT/build/rust-pipe-data"}
base_cpio=${RUST_PIPE_DATA_BASE_CPIO:-"$workdir/modpkg-lq-c.cpio"}
if [ -n "${RUST_PIPE_DATA_MODPKG_CPIO:-}" ]; then
    selected_cpio=$RUST_PIPE_DATA_MODPKG_CPIO
elif [ "$pipe_mode" = rust ]; then
    selected_cpio="$workdir/modpkg-lq-rust-pipe.cpio"
else
    selected_cpio="$workdir/modpkg-lq-c-rollback-pipe.cpio"
fi
selected_pipe="$ROOT/build/rust/selected/sbin/pipe.elf"
lq_libc="$ROOT/lq/build/libc/libc.so"
lq_rtld="$ROOT/lq/build/rtld/ld-qsoe.so.1"
helper_src="$workdir/test_pipe_data.c"
helper_obj="$workdir/test_pipe_data.c.o"
helper="$workdir/test_pipe_data.elf"
source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
fragment_tmp=
exit_marker="rust-pipe-data-smoke: helper exited 0"
round_trip="[test_pipe_data] pipe round-trip ok"
eof_marker="[test_pipe_data] pipe eof ok"

if [ -z "$log" ]; then
    if [ "$pipe_mode" = rust ]; then
        log="$workdir/boot-smoke-lq-rust-pipe-data.log"
    else
        log="$workdir/boot-smoke-lq-c-pipe-data.log"
    fi
elif [ "${log#/}" = "$log" ]; then
    log="$ROOT/$log"
fi

mkdir -p "$workdir"

if [ ! -d "$source_conf" ]; then
    echo "rust-pipe-data-smoke.sh: missing quser/conf; run make prepare first" >&2
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
    if [ -n "$fragment_tmp" ]; then
        rm -f "$fragment_tmp"
    fi
    rmdir "$source_sysinit" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$source_sysinit"
fragment_tmp=$(mktemp "$source_sysinit/10-rust-pipe-data-smoke.XXXXXX")
fragment="$fragment_tmp.sh"
if [ -e "$fragment" ]; then
    echo "rust-pipe-data-smoke.sh: temporary fragment already exists: $fragment" >&2
    exit 1
fi
mv "$fragment_tmp" "$fragment"
fragment_tmp=
cat > "$fragment" <<'EOF'
if /sbin/pipe; then
    echo "rust-pipe-data-smoke: started /sbin/pipe"
else
    echo "rust-pipe-data-smoke: failed to start /sbin/pipe"
fi

if /usr/bin/test_pipe_data; then
    echo "rust-pipe-data-smoke: helper exited 0"
else
    rc=$?
    echo "rust-pipe-data-smoke: helper failed $rc"
fi
EOF
chmod 0644 "$fragment"

echo "rust-pipe-data-smoke.sh: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory

echo "rust-pipe-data-smoke.sh: selecting $pipe_mode pipe artifact"
QSOE_RUST_PIPE="$QSOE_RUST_PIPE" \
    LIBC_SO="$lq_libc" \
    "$MAKE" -C "$ROOT" pipe-artifact --no-print-directory

if [ ! -f "$selected_pipe" ]; then
    echo "rust-pipe-data-smoke.sh: missing selected pipe at $selected_pipe" >&2
    exit 1
fi

echo "rust-pipe-data-smoke.sh: building pipe data helper"
cat > "$helper_src" <<'EOF'
/*
 * test_pipe_data: focused pipe(2) data-path smoke helper.
 *
 * Generated into build/rust-pipe-data/ by rust-pipe-data-smoke.sh so the
 * handover repo does not need to commit source into nested component checkouts.
 */

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/qsoe.h>

static int fail(const char *what)
{
    printf("[test_pipe_data] %s failed errno=%d\n", what, qsoe_errno);
    return 1;
}

int main(int argc, char **argv, char **envp)
{
    (void)argc;
    (void)argv;
    (void)envp;

    static const char payload[] = "qsoe-rust-pipe-data-smoke";
    char buf[sizeof payload] = { 0 };
    int fd[2] = { -1, -1 };

    printf("[test_pipe_data] starting\n");

    if (pipe(fd) != 0)
        return fail("pipe");
    printf("[test_pipe_data] pipe fds read=%d write=%d\n", fd[0], fd[1]);

    ssize_t wrote = write(fd[1], payload, sizeof payload);
    if (wrote != (ssize_t)sizeof payload) {
        printf("[test_pipe_data] write got %ld expected %lu errno=%d\n",
               (long)wrote, (unsigned long)sizeof payload, qsoe_errno);
        return 1;
    }

    ssize_t got = read(fd[0], buf, sizeof buf);
    if (got != (ssize_t)sizeof payload) {
        printf("[test_pipe_data] read got %ld expected %lu errno=%d\n",
               (long)got, (unsigned long)sizeof payload, qsoe_errno);
        return 1;
    }
    if (memcmp(buf, payload, sizeof payload) != 0) {
        printf("[test_pipe_data] payload mismatch\n");
        return 1;
    }
    printf("[test_pipe_data] pipe round-trip ok\n");

    if (close(fd[1]) != 0)
        return fail("close write");

    got = read(fd[0], buf, sizeof buf);
    if (got != 0) {
        printf("[test_pipe_data] eof read got %ld expected 0 errno=%d\n",
               (long)got, qsoe_errno);
        return 1;
    }
    printf("[test_pipe_data] pipe eof ok\n");

    if (close(fd[0]) != 0)
        return fail("close read");

    printf("[test_pipe_data] done\n");
    return 0;
}
EOF

CROSS=${CROSS:-riscv64-linux-gnu-}
CC=${CC:-${CROSS}gcc}
archflags=(-march=rv64imafdc_zicsr_zifencei_zicntr -mabi=lp64d -mcmodel=medany)
gcc_include=$("$CC" -print-file-name=include)
libc_dir=$(dirname "$lq_libc")
crt0="$libc_dir/crt0.o"
libgcc=$("$CC" "${archflags[@]}" -print-libgcc-file-name)

"$CC" "${archflags[@]}" -std=c11 \
    -D_XOPEN_SOURCE=700 \
    -fPIC -ffreestanding -nostdinc \
    -fno-stack-protector \
    -Wall -Wextra -Wno-unused-parameter -O2 -g \
    -isystem "$gcc_include" \
    -isystem "$ROOT/libc/include" \
    -MD -MP -c -o "$helper_obj" "$helper_src"

"$CC" -nostdlib -no-pie \
    -Wl,--dynamic-linker=/lib/ld-qsoe.so.1 \
    -L"$libc_dir" -Wl,-rpath,"$libc_dir" \
    -Wl,--no-warn-rwx-segments \
    -Wl,-z,now \
    -Wl,--unresolved-symbols=ignore-in-shared-libs \
    -o "$helper" "$crt0" "$helper_obj" -lc "$libgcc"

echo "rust-pipe-data-smoke.sh: building base LQ modpkg.cpio"
"$MAKE" -C "$ROOT/quser" cpio --no-print-directory \
    MODPKG_CPIO="$base_cpio" \
    LIBC_SO="$lq_libc" \
    RTLD_SO="$lq_rtld" \
    DYNLIBC_SO="$lq_libc"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/qsoe-rust-pipe-data-cpio.XXXXXX")
cleanup_tmp() {
    rm -rf "$tmp"
}
trap 'cleanup_tmp; cleanup' EXIT

list="$tmp/filelist"
rootdir="$tmp/root"
mkdir -p "$rootdir"

cpio --quiet -it < "$base_cpio" > "$list"
if ! grep -Fxq "sbin/pipe" "$list"; then
    echo "rust-pipe-data-smoke.sh: base cpio has no sbin/pipe entry" >&2
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
        --file="$selected_cpio" < "$list"
)
touch "$selected_cpio"
echo "rust-pipe-data-smoke.sh: wrote $selected_cpio"

fsqrv_bins="$ROOT/quser/build/test/suite/suite.elf:suite"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/test/msgpass/test_msgpass.elf:test_msgpass"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/test/syncspace/test_syncspace.elf:test_syncspace"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/utils/time.elf:time"
fsqrv_bins="$fsqrv_bins $ROOT/quser/build/utils/sysinfo.elf:sysinfo"
fsqrv_bins="$fsqrv_bins $helper:test_pipe_data"

echo "rust-pipe-data-smoke.sh: rebuilding virtio qrvfs image with pipe helper"
"$MAKE" -C "$ROOT" virtio FSQRV_BINS="$fsqrv_bins" --no-print-directory

if ! strings -a "$ROOT/build/fsqrv-root/bin/test_pipe_data" | \
        grep -Fq "[test_pipe_data] pipe round-trip ok"; then
    echo "rust-pipe-data-smoke.sh: staged test_pipe_data helper is unexpected" >&2
    exit 1
fi

echo "rust-pipe-data-smoke.sh: rebuilding LQ QEMU image with $pipe_mode pipe cpio"
"$MAKE" -C "$ROOT/lq" MODPKG_CPIO="$selected_cpio" --no-print-directory

boot_args=(-k lq -t "$timeout_s" -o "$log")
if [ "$keep_running" -eq 1 ]; then
    boot_args+=(--keep-running)
fi
if [ "${#emu_args[@]}" -gt 0 ]; then
    boot_args+=(-- "${emu_args[@]}")
fi

echo "rust-pipe-data-smoke.sh: booting $pipe_mode pipe data smoke"
expected_markers=(
    "$registration" \
    "$round_trip" \
    "$eof_marker" \
    "$exit_marker"
)
boot_extra_patterns=$(printf '%s\n' "${expected_markers[@]}")
FSQRV_BINS="$fsqrv_bins" \
    QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
    QSOE_BOOT_EXTRA_PATTERNS="$boot_extra_patterns" \
    "$ROOT/scripts/boot-smoke.sh" "${boot_args[@]}"

for expected in "${expected_markers[@]}"; do
    if ! log_has_marker "$expected"; then
        echo "rust-pipe-data-smoke.sh: missing marker in $log: $expected" >&2
        exit 1
    fi
done

echo "rust-pipe-data-smoke.sh: $pipe_mode pipe data-path smoke passed"
