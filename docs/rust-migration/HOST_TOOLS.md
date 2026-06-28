# QSOE Host Tool Fixtures And Behavior

This document records the current host-tool behavior that Rust ports must
preserve or intentionally change with a separate design note.

## Scope

The first host-tool baseline covers:

- `host_tools/mkfs-qrv.c`: qrvfs image construction.
- `host_tools/treeqrvfs.c`: qrvfs read-only tree inspection.
- `host_tools/mkgpt.py`: primary GPT skeleton creation and partition payload
  writes.
- `boot/gptextract.py`: primary GPT partition extraction.

The fixture scripts generate temporary artifacts under `build/fixtures/`.
Generated images are not committed.

Run all host-tool fixture checks:

```sh
make check-host-tools
```

## qrvfs Format Baseline

The on-disk format is defined by `quser/fs/qrv/fs.h`.

Important constants:

- Magic: `0x51525631`.
- Version: `2`.
- Block size: `4096`.
- Root inode: `1`.
- Inode size: `128` bytes.
- Directory entry size: `256` bytes.
- Directory name capacity: `252` bytes including NUL.
- Inodes per block: `32`.
- Directory entries per block: `16`.

Superblock layout:

- Block `0`: reserved.
- Block `1`: superblock.
- Block `2..`: log area, currently zero blocks.
- Then inode blocks.
- Then bitmap blocks.
- Then data blocks.

The default qrvfs image built by `mkfs-qrv` is `8 MiB` with `128` inodes.

## `mkfs-qrv` Behavior

Command shape:

```sh
mkfs-qrv [-s size_mb] [-n ninodes] image [populate_dir]
```

Current behavior:

- Creates a qrvfs v2 image.
- For regular files, truncates the target to the requested sparse size.
- For block devices on Linux, tries `BLKZEROOUT` for metadata blocks, then
  falls back to writing metadata blocks manually.
- Writes the superblock to block `1`.
- Marks all metadata blocks as used in the bitmap.
- Allocates root as inode `1`.
- Creates `.` and `..` entries in root.
- Recursively populates regular files and directories from `populate_dir`.
- Preserves lower permission bits from host mode.
- Ignores host entries that are not regular files or directories.
- Rejects names longer than `QRVFS_NAMESIZ - 1`.

Observable success output includes:

- Image path, size in MiB, and total block count.
- Layout line for log, inode, bitmap, and data areas.
- Initialization mode.
- Root inode and data-block count.

## `treeqrvfs` Behavior

Command shape:

```sh
treeqrvfs <qrvfs-image>
```

Current behavior:

- Opens the image read-only.
- Reads the superblock from block `1`.
- Rejects images with a bad magic value.
- Rejects images with an unsupported qrvfs version.
- Prints a header with image path, qrvfs version, block count, and inode count.
- Walks from root inode `1`.
- Skips `.` and `..`.
- Prints directories and files in on-disk directory-entry order.
- Prints mode strings and byte sizes.
- Prints a final count of directories and files, excluding root from the
  directory count.

The fixture script validates a generated image containing:

- `bin/hello`.
- `conf/passwd`.
- `home/user/profile`.

Expected semantic result:

- qrvfs version `2`.
- `512` blocks for a `2 MiB` fixture.
- `64` inodes for the fixture run.
- `4 directories, 3 files`.

Run:

```sh
scripts/check-qrvfs-fixture.sh
```

## Rust qrvfs Inspection Baseline

The initial Rust host-tool port is read-only qrvfs inspection:

```text
rust/crates/qsoe-qrvfs
```

It provides:

- A bounds-checked qrvfs superblock, inode, and directory parser.
- A `qrvfs-tree` binary that emits the same tree format as `treeqrvfs`.
- Unit tests for a minimal in-memory qrvfs image.
- A fixture comparison against the current C inspector.
- A selected `make tree` artifact that uses Rust by default while preserving a
  C rollback selector.

Run the Rust/C comparison:

```sh
make check-qrvfs-rust-fixture
```

The comparison regenerates the qrvfs fixture with the current C tools, runs the
Rust inspector, and fails if the output diverges from `treeqrvfs`.

The host inspector release-candidate selector is:

```sh
make treeqrvfs-rc-smoke
make treeqrvfs-rc-rollback-smoke
```

`make tree` now selects Rust `qrvfs-tree` by default. Set
`QSOE_RUST_TREEQRVFS=0` to build the C `treeqrvfs` rollback artifact instead.
The C `mkfs-qrv` image writer remains unchanged.

## Rust ELF Inspection Baseline

The initial Rust ELF parser is read-only relocation inspection:

```text
rust/crates/qsoe-elf
```

It provides:

- A dependency-free, `no_std` ELF64 little-endian header and section parser.
- REL/RELA relocation iteration.
- RISC-V relocation labels for the current QSOE userland baseline.
- A fixture test against representative built C userland binaries.

Run the relocation fixture:

```sh
make check-elf-reloc-fixture
```

The fixture requires the source tree to have built `quser/build` artifacts. It
fails if the representative binaries are missing or if their relocation type
counts drift from `docs/rust-migration/ELF_BASELINE.md`.

## GPT Behavior

`host_tools/mkgpt.py` writes only the primary GPT structures used by QSOE:

- LBA `0`: protective MBR.
- LBA `1`: primary GPT header.
- LBAs `2..33`: primary partition entry array.

It does not write backup GPT structures.

Default production layout from the umbrella Makefile:

- Raw image: `build/nvme.img`.
- Image size: `192 MiB`.
- Eight partitions.
- Each partition: `16 MiB`.
- Partition `8`: fs-qrv type GUID.

Type GUIDs:

- Linux filesystem data: `0fc63daf-8483-4772-8e79-3d69d8477de4`.
- fs-qrv: `51525611-322e-4017-bae8-e4d9c9d4e979`.

Partition names:

- Default: `qsoe-test-pN`.
- fs-qrv partition: `fsqrv`.

`mkgpt.py --write-part N` recomputes the same packed partition layout from the
partition sizes and writes a payload into partition `N`.

`boot/gptextract.py` reads only the primary GPT and extracts the byte range for
one partition by index.

The GPT fixture script validates:

- Protective MBR signature.
- GPT signature.
- Header CRC.
- Entry-array CRC.
- Entry size and count.
- Packed eight-partition layout.
- `p8` type GUID and name.

Run:

```sh
scripts/check-gpt-fixture.py
```

## Rust Port Acceptance

A Rust replacement for any host tool must:

- Pass the relevant fixture script.
- Preserve documented behavior by default.
- Keep generated image semantics compatible with QSOE runtime consumers.
- Provide byte-for-byte output only where the current tool is deterministic.
- Explain any intentionally nondeterministic fields such as generated GUIDs.
