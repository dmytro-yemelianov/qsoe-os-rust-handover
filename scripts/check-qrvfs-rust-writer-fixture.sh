#!/usr/bin/env bash
#
# Generate a qrvfs fixture with the retired-C Rust writer and inspect it with Rust.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIXTURE="$ROOT/build/fixtures/qrvfs-rust-writer"
ROOTDIR="$FIXTURE/root"
IMG="$FIXTURE/qrvfs-rust-writer.img"
MKFS_LOG="$FIXTURE/mkfs-rust.log"
TREE_LOG="$FIXTURE/tree-rust.log"
MANIFEST="$ROOT/rust/Cargo.toml"

. "$ROOT/scripts/rust-env.sh"
qsoe_cargo_set_target_dir "$ROOT" host

if ! command -v cargo >/dev/null 2>&1; then
    echo "check-qrvfs-rust-writer-fixture.sh: cargo not found" >&2
    exit 127
fi

mkdir -p "$FIXTURE"

cargo build \
    --quiet \
    --manifest-path "$MANIFEST" \
    -p qsoe-qrvfs \
    --bin mkfs-qrv-rs \
    --bin qrvfs-tree

rm -rf "$ROOTDIR"
mkdir -p "$ROOTDIR/bin" "$ROOTDIR/conf" "$ROOTDIR/home/user"

printf '#!/bin/sh\nprintf "hello from rust qrvfs writer\\n"\n' > "$ROOTDIR/bin/hello"
chmod 755 "$ROOTDIR/bin/hello"

python3 - "$ROOTDIR/bin/large.bin" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
size = 3 * 1024 * 1024
chunk = bytes((idx % 251 for idx in range(4096)))
with path.open("wb") as f:
    for _ in range(size // len(chunk)):
        f.write(chunk)
PY
chmod 644 "$ROOTDIR/bin/large.bin"

printf 'root:x:0:0:root:/root:/bin/qsh\nuser:x:1000:1000:user:/home/user:/bin/qsh\n' \
    > "$ROOTDIR/conf/passwd"
chmod 644 "$ROOTDIR/conf/passwd"

printf 'PATH=/bin:/sbin\nexport PATH\n' > "$ROOTDIR/home/user/profile"
chmod 644 "$ROOTDIR/home/user/profile"

"$CARGO_TARGET_DIR/debug/mkfs-qrv-rs" -s 8 -n 64 "$IMG" "$ROOTDIR" > "$MKFS_LOG"
"$CARGO_TARGET_DIR/debug/qrvfs-tree" "$IMG" > "$TREE_LOG"

require() {
    pattern=$1
    file=$2
    if ! grep -Fq "$pattern" "$file"; then
        echo "check-qrvfs-rust-writer-fixture.sh: missing pattern in $file: $pattern" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        exit 1
    fi
}

require "mkfs-qrvfs-rs: done. Root inode=1" "$MKFS_LOG"
require "qrvfs v2, 2048 blocks, 64 inodes" "$TREE_LOG"
require "bin" "$TREE_LOG"
require "hello" "$TREE_LOG"
require "large.bin" "$TREE_LOG"
require "3145728" "$TREE_LOG"
require "conf" "$TREE_LOG"
require "passwd" "$TREE_LOG"
require "home" "$TREE_LOG"
require "user" "$TREE_LOG"
require "profile" "$TREE_LOG"
require "4 directories, 4 files" "$TREE_LOG"

python3 - "$IMG" <<'PY'
import struct
import sys

img = sys.argv[1]
QRVFS_MAGIC = 0x51525631
QRVFS_VERSION = 2
QRVFS_BSIZE = 4096

with open(img, "rb") as f:
    f.seek(QRVFS_BSIZE)
    sb = f.read(struct.calcsize("<IIQQQQQQQQ"))

fields = struct.unpack("<IIQQQQQQQQ", sb)
magic, version, size, nblocks, ninodes, nlog, logstart, inodestart, bmapstart, datastart = fields

checks = [
    (magic == QRVFS_MAGIC, f"magic 0x{magic:08x}"),
    (version == QRVFS_VERSION, f"version {version}"),
    (size == 2048, f"size {size}"),
    (ninodes == 64, f"ninodes {ninodes}"),
    (nlog == 0, f"nlog {nlog}"),
    (logstart == 2, f"logstart {logstart}"),
    (inodestart == 2, f"inodestart {inodestart}"),
    (bmapstart == 4, f"bmapstart {bmapstart}"),
    (datastart == 5, f"datastart {datastart}"),
    (nblocks == 2043, f"nblocks {nblocks}"),
]

bad = [msg for ok, msg in checks if not ok]
if bad:
    for msg in bad:
        print(f"rust qrvfs writer fixture check failed: {msg}", file=sys.stderr)
    sys.exit(1)
PY

echo "check-qrvfs-rust-writer-fixture.sh: ok"
echo "  image: $IMG"
echo "  tree:  $TREE_LOG"
