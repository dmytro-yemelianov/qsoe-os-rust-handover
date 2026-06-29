# Task Manager `/sys` Provider

Captured: 2026-06-29 CEST.

`tm_sysfs` is a bounded task-manager Rust provider for the portable read-only
`/sys` model:

```text
libtaskman/src/tm_sysfs.c
libtaskman/include/tm_sysfs.h
```

## Scope

The Rust provider exports the existing `tm_sysfs.h` C ABI:

```text
void tm_sysfs_init(const char *osname, const char *board,
                   const char *cmdline, const char *version,
                   const char *builddate);
int tm_sysfs_resolve(const char *path, unsigned *idx_out);
int tm_sysfs_path_exists(const char *path);
const char *tm_sysfs_content(unsigned idx, unsigned *len_out);
unsigned tm_sysfs_nentries(void);
const char *tm_sysfs_entry_name(unsigned idx);
```

It owns only the static snapshot buffers, path resolution, entry order, content
lengths, and directory names for:

```text
/sys/board
/sys/builddate
/sys/cmdline
/sys/osname
/sys/version
```

It does not replace sysmap/syscfg discovery, process creation, init path
selection, open/read/readdir dispatch, connection state, IPC decoding, or any
seL4 object manipulation. NQ and LQ taskman still gather the source strings in
C and still serve `/sys` through their existing C path layers.

## Selector

Normal taskman builds remain C-default:

```text
QSOE_RUST_TM_SYSFS=0  -> C `libtaskman/src/tm_sysfs.c` remains selected
QSOE_RUST_TM_SYSFS=1  -> Rust `qsoe-tm-sysfs` staticlib is linked instead
```

When Rust is selected, `libtaskman/Makefile` excludes `tm_sysfs.o` from
`libtaskman.a`, and the NQ/LQ taskman links add the shared provider archive:

```text
build/rust/tm-providers/libqsoe_tm_providers.a
```

The archive is built for `riscv64imac-unknown-none-elf` so it matches
taskman's soft-float ABI.

Multiple taskman Rust providers may be selected together. The shared
`qsoe-tm-providers` archive packages the selected provider crates behind one
no-std panic handler. Legacy targets such as `make rust-tm-sysfs-provider`
still produce the historical single-provider output path for focused evidence.

## Evidence

The C behavior baseline is covered by:

```sh
make check-tm-sysfs-model
```

That fixture verifies newline and NUL snapshot behavior, null or empty source
fallback, truncation, `/sys` path resolution, entry order, content lookup, and
out-of-range behavior.

The Rust provider has equivalent host coverage:

```sh
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-sysfs --features host-tests
```

The full opt-in evidence gate is:

```sh
make tm-sysfs-evidence
make tm-sysfs-runtime-smoke
```

It runs the C fixture, Rust host tests, builds and audits the Rust staticlib,
checks exported symbols, verifies all archive members are RVC soft-float, and
links both NQ and LQ taskman in C rollback and Rust-selected modes. The gate
also verifies `tm_sysfs.o` is present for `QSOE_RUST_TM_SYSFS=0` and absent for
`QSOE_RUST_TM_SYSFS=1`.

`make tm-sysfs-runtime-smoke` verifies the Rust-selected provider in a booted
LQ image. The smoke:

- rebuilds QSOE/L with `QSOE_RUST_TM_SYSFS=1` and mandatory
  `QSOE_RUST_TM_PROCFS=1`;
- verifies the selected `libtaskman.a` no longer contains C `tm_sysfs.o`;
- verifies the shared Rust provider archive exports all six `tm_sysfs_*` ABI
  symbols;
- waits for taskman's `syscfg built from FDT` and `sysmap page built` markers;
- runs `/bin/ls /sys` from sysinit to exercise `tm_sysfs_nentries()` and
  `tm_sysfs_entry_name()` through LQ's existing C readdir path;
- reads `/sys/board`, `/sys/builddate`, `/sys/cmdline`, `/sys/osname`, and
  `/sys/version` from sysinit to exercise path resolution and content lookup.

Expected runtime markers:

```text
syscfg built from FDT
sysmap page built
tm-sysfs-runtime-smoke: /sys readdir ok
tm-sysfs-runtime-smoke: /sys/board ok
tm-sysfs-runtime-smoke: /sys/builddate ok
tm-sysfs-runtime-smoke: /sys/cmdline ok
tm-sysfs-runtime-smoke: /sys/osname ok
tm-sysfs-runtime-smoke: /sys/version ok
```

## Current State

`tm_sysfs` is Rust opt-in only. It is not a Rust-default release candidate and
has no C retirement approval. Keep `libtaskman/src/tm_sysfs.c` as the rollback
implementation until a separate Rust-default RC decision exists; C retirement
still requires the global retirement checklist and a separate removal PR.
