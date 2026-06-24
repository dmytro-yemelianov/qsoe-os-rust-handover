#!/usr/bin/env bash
#
# Link a Rust staticlib behind QSOE crt0/libc as a smoke test.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST="$ROOT/rust/Cargo.toml"
RUST_TARGET=${RUST_TARGET:-riscv64gc-unknown-none-elf}
RUST_PACKAGE=${RUST_PACKAGE:-qsoe-minimal-rs}
RUST_LIB=${RUST_LIB:-$(printf '%s' "$RUST_PACKAGE" | tr '-' '_')}
RUST_EXTRA_LDFLAGS=${RUST_EXTRA_LDFLAGS:-}
RUST_EXTRA_LDLIBS=${RUST_EXTRA_LDLIBS:-}
CROSS=${CROSS:-riscv64-linux-gnu-}
CC=${CC:-${CROSS}gcc}
OBJCOPY=${OBJCOPY:-${CROSS}objcopy}
ARCHFLAGS=${ARCHFLAGS:-"-march=rv64imafdc_zicsr_zifencei_zicntr -mabi=lp64d -mcmodel=medany"}
LIBC_SO=${LIBC_SO:-"$ROOT/nq/build/libc/libc.so"}
LIBC_DIR=$(dirname "$LIBC_SO")
CRT0=${CRT0:-"$LIBC_DIR/crt0.o"}
OUTDIR="$ROOT/build/rust"
OUT=${RUST_OUT:-"$OUTDIR/$RUST_PACKAGE.elf"}

. "$ROOT/scripts/rust-env.sh"
qsoe_cargo_set_target_dir "$ROOT" qsoe-link

need_file() {
    if [ ! -f "$1" ]; then
        echo "rust-qsoe-link-smoke.sh: missing $2: $1" >&2
        return 1
    fi
}

if ! command -v "$CC" >/dev/null 2>&1; then
    echo "rust-qsoe-link-smoke.sh: compiler not found: $CC" >&2
    echo "Install the RISC-V GNU toolchain or set CROSS=/path/prefix." >&2
    exit 127
fi

if ! rustup target list --installed 2>/dev/null | grep -Fxq "$RUST_TARGET"; then
    echo "rust-qsoe-link-smoke.sh: Rust target not installed: $RUST_TARGET" >&2
    echo "Install it with: rustup target add $RUST_TARGET" >&2
    exit 1
fi

need_file "$CRT0" "QSOE crt0.o" || exit 1
need_file "$LIBC_SO" "QSOE libc.so" || exit 1

cargo build \
    --manifest-path "$MANIFEST" \
    -p "$RUST_PACKAGE" \
    --target "$RUST_TARGET" \
    --release

STATICLIB="$CARGO_TARGET_DIR/$RUST_TARGET/release/lib$RUST_LIB.a"
need_file "$STATICLIB" "Rust staticlib" || exit 1

mkdir -p "$OUTDIR"

LIBGCC=$("$CC" $ARCHFLAGS -print-libgcc-file-name)

"$CC" $ARCHFLAGS \
    -nostdlib -no-pie \
    -Wl,--dynamic-linker=/lib/ld-qsoe.so.1 \
    -L"$LIBC_DIR" -Wl,-rpath,"$LIBC_DIR" \
    $RUST_EXTRA_LDFLAGS \
    -Wl,--no-warn-rwx-segments \
    -Wl,--no-eh-frame-hdr \
    -Wl,--gc-sections \
    -Wl,-z,now \
    -Wl,--unresolved-symbols=ignore-in-shared-libs \
    -o "$OUT" \
    "$CRT0" "$STATICLIB" $RUST_EXTRA_LDLIBS -lc "$LIBGCC"

if command -v "$OBJCOPY" >/dev/null 2>&1; then
    "$OBJCOPY" \
        --remove-section=.eh_frame \
        --remove-section=.eh_frame_hdr \
        --remove-section=.gcc_except_table \
        --remove-section=.debug_frame \
        "$OUT"
fi

echo "rust-qsoe-link-smoke.sh: linked $OUT"

if "$ROOT/scripts/audit-elf.sh" --strict-qsoe-user "$OUT"; then
    :
else
    echo "rust-qsoe-link-smoke.sh: audit failed for $OUT" >&2
    exit 1
fi
