#!/usr/bin/env bash
#
# Generate and inspect a small qrvfs fixture using the retired-C Rust host tools.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIXTURE="$ROOT/build/fixtures/qrvfs"
ROOTDIR="$FIXTURE/root"
IMG="$FIXTURE/qrvfs-fixture.img"
MKFS_LOG="$FIXTURE/mkfs.log"
TREE_LOG="$FIXTURE/tree.log"
MANIFEST="$ROOT/rust/Cargo.toml"

. "$ROOT/scripts/rust-env.sh"
qsoe_cargo_set_target_dir "$ROOT" host

if ! command -v cargo >/dev/null 2>&1; then
    echo "check-qrvfs-fixture.sh: cargo not found" >&2
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

printf '#!/bin/sh\nprintf "hello from qrvfs fixture\\n"\n' > "$ROOTDIR/bin/hello"
chmod 755 "$ROOTDIR/bin/hello"

printf 'root:x:0:0:root:/root:/bin/qsh\nuser:x:1000:1000:user:/home/user:/bin/qsh\n' \
    > "$ROOTDIR/conf/passwd"
chmod 644 "$ROOTDIR/conf/passwd"

printf 'PATH=/bin:/sbin\nexport PATH\n' > "$ROOTDIR/home/user/profile"
chmod 644 "$ROOTDIR/home/user/profile"

"$CARGO_TARGET_DIR/debug/mkfs-qrv-rs" -s 2 -n 64 "$IMG" "$ROOTDIR" > "$MKFS_LOG"
"$CARGO_TARGET_DIR/debug/qrvfs-tree" "$IMG" > "$TREE_LOG"

require() {
    pattern=$1
    file=$2
    if ! grep -Fq "$pattern" "$file"; then
        echo "check-qrvfs-fixture.sh: missing pattern in $file: $pattern" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        exit 1
    fi
}

require "mkfs-qrvfs-rs: done. Root inode=1" "$MKFS_LOG"
require "qrvfs v2, 512 blocks, 64 inodes" "$TREE_LOG"
require "bin" "$TREE_LOG"
require "hello" "$TREE_LOG"
require "conf" "$TREE_LOG"
require "passwd" "$TREE_LOG"
require "home" "$TREE_LOG"
require "user" "$TREE_LOG"
require "profile" "$TREE_LOG"
require "4 directories, 3 files" "$TREE_LOG"

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
    (size == 512, f"size {size}"),
    (ninodes == 64, f"ninodes {ninodes}"),
    (nlog == 0, f"nlog {nlog}"),
    (logstart == 2, f"logstart {logstart}"),
    (inodestart == 2, f"inodestart {inodestart}"),
    (bmapstart == 4, f"bmapstart {bmapstart}"),
    (datastart == 5, f"datastart {datastart}"),
    (nblocks == 507, f"nblocks {nblocks}"),
]

bad = [msg for ok, msg in checks if not ok]
if bad:
    for msg in bad:
        print(f"qrvfs fixture check failed: {msg}", file=sys.stderr)
    sys.exit(1)
PY

echo "check-qrvfs-fixture.sh: ok"
echo "  image: $IMG"
echo "  tree:  $TREE_LOG"
