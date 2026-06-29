# Task Manager CPIO Provider

Captured: 2026-06-29 CEST.

`tm_cpio` is a bounded task-manager Rust provider for the portable in-memory
`newc` archive model:

```text
libtaskman/src/cpio.c
libtaskman/include/tm_cpio.h
```

## Scope

The Rust provider exports the existing `tm_cpio.h` C ABI:

```text
int tm_cpio_check_valid(const uint8_t *data, uint64_t size);
void tm_cpio_iterate(const uint8_t *data, uint64_t size,
                     tm_cpio_callback_t cb, void *user);
int tm_cpio_find_file(const uint8_t *data, uint64_t size,
                      const char *filename, tm_cpio_file_info_t *info);
int tm_cpio_resolve_path(const uint8_t *data, uint64_t size,
                         const char *path,
                         char *out_path, unsigned out_cap,
                         tm_cpio_file_info_t *out_info);
int tm_cpio_dirent_at(const uint8_t *data, uint64_t size,
                      const char *prefix,
                      uint32_t index,
                      unsigned *out_type,
                      char *out_name_buf, unsigned out_name_cap,
                      unsigned *out_namelen);
int tm_cpio_dir_exists(const uint8_t *data, uint64_t size,
                       const char *prefix);
```

It owns only byte-level archive walking, exact file lookup, symlink resolution,
directory-entry synthesis, and directory-existence checks over caller-owned
archive bytes. It does not replace taskman spawn, CPIO-backed file descriptor
state, path-manager registration, ELF loading, relocation, process creation,
or any seL4 object manipulation.

The provider intentionally preserves the C walker's forgiving behavior:
iteration stops at the first malformed header or `TRAILER!!!` entry rather than
turning malformed later records into hard errors. It also follows the C
implementation's absolute pointer-alignment behavior when the archive pointer
itself is not 4-byte aligned.

## Selector

Normal taskman builds are in a Rust-default RC window:

```text
QSOE_RUST_TM_CPIO=1  -> Rust `qsoe-tm-cpio` provider is selected (default)
QSOE_RUST_TM_CPIO=0  -> C `libtaskman/src/cpio.c` rollback is selected
```

When Rust is selected, `libtaskman/Makefile` excludes `cpio.o` from
`libtaskman.a`, and the NQ/LQ taskman links add the shared provider archive:

```text
build/rust/tm-providers/libqsoe_tm_providers.a
```

The archive is built for `riscv64imac-unknown-none-elf` so it matches
taskman's soft-float ABI.

Multiple taskman Rust providers may be selected together. The shared
`qsoe-tm-providers` archive packages the selected provider crates behind one
no-std panic handler. Legacy targets such as `make rust-tm-cpio-provider`
still produce the historical single-provider output path for focused evidence.

## Evidence

The C behavior baseline is covered by:

```sh
make check-tm-cpio-model
```

That fixture verifies archive iteration, exact lookup, symlink resolution,
directory existence, directory-entry synthesis, short output buffers, missing
paths, and malformed-archive stopping behavior.

The Rust provider has equivalent host coverage:

```sh
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-cpio --features host-tests
```

The full opt-in evidence gate is:

```sh
make tm-cpio-evidence
```

It runs the C fixture, Rust host tests, builds and audits the Rust staticlib,
checks exported archive and linked taskman symbols, verifies all archive members
are RVC soft-float, and links both NQ and LQ taskman in C rollback and
Rust-selected modes. The gate also verifies `cpio.o` is present for
`QSOE_RUST_TM_CPIO=0` and absent for `QSOE_RUST_TM_CPIO=1`.

The focused runtime smoke is:

```sh
make tm-cpio-runtime-smoke
```

It rebuilds QSOE/L with `QSOE_RUST_TM_CPIO=1` and mandatory
`QSOE_RUST_TM_PROCFS=1`, injects a temporary sysinit fragment, and boots the
image. The fragment verifies CPIO-root symlink readlink output
(`/etc -> /usr/conf` and `/home -> /usr/home`), `/etc/passwd` access through
the CPIO symlink into mounted `/usr`, direct `/sbin/init` reads from the boot
CPIO, and `/bin/sh` symlink spawn.

The Rust-default RC and rollback smokes are:

```sh
make tm-cpio-rc-smoke
make tm-cpio-rc-rollback-smoke
```

The RC smoke first builds NQ and LQ taskman in the default selector mode and
verifies C `cpio.o` is absent from `libtaskman.a`. The rollback smoke repeats
the same archive-membership and live runtime checks with
`QSOE_RUST_TM_CPIO=0`, where C `cpio.o` must be present.

The multi-provider link gate is:

```sh
make tm-providers-evidence
```

It currently selects `tm_cpio` and `tm_procfs` together to prove the shared
archive, single panic handler, final taskman ELF audits, and dual-provider
`/proc` smoke.

## Current State

`tm_cpio` is a Rust-default release candidate with C rollback still available.
It has no C retirement approval. Keep `libtaskman/src/cpio.c` as the rollback
implementation until the global retirement checklist is satisfied and a
separate removal PR is reviewed.
