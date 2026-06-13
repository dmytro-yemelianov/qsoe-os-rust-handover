#!/usr/bin/env python3
# gptextract.py: copy one partition's bytes out of a GPT disk image.
#
# Copyright (c) 2026 Yuri Zaporozhets <yuriz@qsoe.net>
# SPDX-License-Identifier: Apache-2.0
#
# The inverse of host_tools/mkgpt.py: instead of writing a GPT, read the
# PRIMARY GPT (header at LBA 1, entry array pointed to by the header) and
# dump the byte range of a single partition to a standalone file.  Used by
# the boot Makefile to ship just the fs-qrv partition (p8) to hardware
# rather than the whole multi-partition scratch image.
#
# Bit-compatible with mkgpt.py / libgpt: 512-byte LBAs, header at LBA 1,
# little-endian fields.  Reads the primary GPT only (no backup), matching
# what libgpt itself trusts.
#
# Usage: gptextract.py <image> <part_index_1based> <output>

import struct
import sys

LBA_SIZE      = 512
HEADER_LBA    = 1                # primary GPT header lives at LBA 1
GPT_SIGNATURE = b"EFI PART"

# Field offsets within the 92-byte GPT header (UEFI spec, table 5-5).
HDR_SIG_OFF        = 0           # 8  bytes: "EFI PART"
HDR_ENTRIES_LBA    = 72          # Q: starting LBA of the entry array
HDR_NUM_ENTRIES    = 80          # I: number of entries
HDR_ENTRY_SIZE     = 84          # I: bytes per entry

# Field offsets within a 128-byte partition entry.
ENT_FIRST_LBA      = 32          # Q: first LBA (inclusive)
ENT_LAST_LBA       = 40          # Q: last  LBA (inclusive)

COPY_CHUNK = 1 << 20             # 1 MiB streaming copy unit


def die(msg):
    print(f"gptextract: {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) != 4:
        print("usage: gptextract.py <image> <part_index_1based> <output>",
              file=sys.stderr)
        sys.exit(1)
    img_path = sys.argv[1]
    index    = int(sys.argv[2])          # 1-based partition number
    out_path = sys.argv[3]

    if index < 1:
        die(f"partition index {index} must be >= 1")

    with open(img_path, "rb") as f:
        f.seek(HEADER_LBA * LBA_SIZE)
        hdr = f.read(LBA_SIZE)
        if hdr[HDR_SIG_OFF:HDR_SIG_OFF + len(GPT_SIGNATURE)] != GPT_SIGNATURE:
            die(f"{img_path}: no GPT signature at LBA {HEADER_LBA}")

        entries_lba = struct.unpack_from("<Q", hdr, HDR_ENTRIES_LBA)[0]
        num_entries = struct.unpack_from("<I", hdr, HDR_NUM_ENTRIES)[0]
        entry_size  = struct.unpack_from("<I", hdr, HDR_ENTRY_SIZE)[0]

        if index > num_entries:
            die(f"partition {index} out of range (disk has {num_entries} slots)")

        entry_off = entries_lba * LBA_SIZE + (index - 1) * entry_size
        f.seek(entry_off)
        ent = f.read(entry_size)
        first_lba = struct.unpack_from("<Q", ent, ENT_FIRST_LBA)[0]
        last_lba  = struct.unpack_from("<Q", ent, ENT_LAST_LBA)[0]

        if first_lba == 0 and last_lba == 0:
            die(f"partition {index} is unused (empty GPT entry)")
        if last_lba < first_lba:
            die(f"partition {index} has a corrupt LBA range "
                f"({first_lba}..{last_lba})")

        nbytes = (last_lba - first_lba + 1) * LBA_SIZE

        f.seek(first_lba * LBA_SIZE)
        with open(out_path, "wb") as out:
            remaining = nbytes
            while remaining > 0:
                chunk = f.read(min(COPY_CHUNK, remaining))
                if not chunk:
                    die(f"image truncated: wanted {nbytes} bytes from p{index}")
                out.write(chunk)
                remaining -= len(chunk)

    print(f"gptextract: p{index} -> {out_path} "
          f"(LBA {first_lba}..{last_lba}, {nbytes // (1024 * 1024)} MiB)")


if __name__ == "__main__":
    main()
