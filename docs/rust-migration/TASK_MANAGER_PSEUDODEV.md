# Task Manager Pseudo-device Provider

Captured: 2026-06-29 CEST.

`tm_pseudodev` is a bounded LQ task-manager Rust provider for the simple
taskman-hosted character devices:

```text
lq/taskman/sys/devnull.c
lq/taskman/sys/devzero.c
lq/taskman/sys/devnull.h
lq/taskman/sys/devzero.h
```

## Scope

The Rust provider exports the existing C ABI used by `lq/taskman/path/io.c`:

```text
unsigned tm_devnull_write(unsigned nbytes);
int tm_devnull_read(unsigned want, unsigned *out_got);
int tm_devnull_stat(tm_stat_t *out);

unsigned tm_devzero_write(unsigned nbytes);
int tm_devzero_read(unsigned want, unsigned *out_got);
int tm_devzero_stat(tm_stat_t *out);
```

It does not replace console IO, file-descriptor ownership, path dispatch,
connection lookup, IPC request decoding, process tables, or any seL4 object
manipulation. The C IO dispatcher still routes `/dev/null` and `/dev/zero`
requests to these function symbols.

`/dev/zero` writes zero bytes into the same taskman IPC payload area as the C
implementation: `qsoe_ipcbuf->msg[4..]`, bounded to 928 bytes. The target build
finds the current taskman's IPC buffer through the QSOE TLS `tp` pointer; host
tests use an in-crate IPC buffer fixture.

## Selector

Normal LQ taskman builds remain C-default:

```text
QSOE_RUST_TM_PSEUDODEV=0  -> C `devnull.o` and `devzero.o` remain selected
QSOE_RUST_TM_PSEUDODEV=1  -> Rust `qsoe-tm-pseudodev` staticlib is linked instead
```

When Rust is selected, `lq/taskman/Makefile` omits:

```text
build/taskman/sys/devnull.o
build/taskman/sys/devzero.o
```

and adds:

```text
build/rust/tm-providers/libqsoe_tm_providers.a
```

The archive is built for `riscv64imac-unknown-none-elf` so it matches
taskman's soft-float ABI.

Multiple taskman Rust providers may be selected together. The shared
`qsoe-tm-providers` archive packages the selected provider crates behind one
no-std panic handler. Legacy targets such as `make rust-tm-pseudodev-provider`
still produce the historical single-provider output path for focused evidence.

## Evidence

The Rust provider has host coverage for ABI layout, `/dev/null` write/read
behavior, `/dev/zero` write/read behavior, IPC payload zeroing, read clamping,
and both `stat` records:

```sh
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-pseudodev --features host-tests
```

The full opt-in evidence gate is:

```sh
make tm-pseudodev-evidence
```

It runs the Rust host tests, builds and audits the Rust staticlib, checks the
six exported symbols, verifies all archive members are RVC soft-float, verifies
the LQ C-default dry-run link plan includes `devnull.o` and `devzero.o`, and
verifies the LQ Rust-selected dry-run link plan omits those objects and links
the shared taskman Rust provider archive. It also links LQ taskman in both
C-default and Rust-selected modes and audits the resulting ELF.

## Current State

`tm_pseudodev` is Rust opt-in only. It is not a Rust-default release candidate
and has no C retirement approval. Keep `lq/taskman/sys/devnull.c` and
`lq/taskman/sys/devzero.c` as rollback implementations until the global
retirement checklist and a separate removal PR are satisfied.
