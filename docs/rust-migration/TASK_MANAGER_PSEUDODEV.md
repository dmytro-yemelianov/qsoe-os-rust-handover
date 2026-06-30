# Task Manager Pseudo-device Provider

Captured: 2026-06-30 CEST.

`tm_pseudodev` is a retired Rust-only LQ task-manager provider for the simple
taskman-hosted character devices:

```text
rust/crates/qsoe-tm-pseudodev
lq/taskman/sys/devnull.h
lq/taskman/sys/devzero.h
```

The previous C providers `lq/taskman/sys/devnull.c` and
`lq/taskman/sys/devzero.c` are removed by the tracked component override. The
headers remain because LQ taskman's C path IO dispatcher still calls the
`tm_devnull_*` and `tm_devzero_*` symbols exported by Rust.

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

`tm_pseudodev` is mandatory after C provider retirement:

```text
QSOE_RUST_TM_PSEUDODEV=1  -> Rust `qsoe-tm-pseudodev` is linked
QSOE_RUST_TM_PSEUDODEV=0  -> rejected; C rollback is retired
```

LQ taskman omits:

```text
build/taskman/sys/devnull.o
build/taskman/sys/devzero.o
```

and links:

```text
build/rust/tm-providers/libqsoe_tm_providers.a
```

The archive is built for `riscv64imac-unknown-none-elf` so it matches
taskman's soft-float ABI. The shared `qsoe-tm-providers` archive packages all
selected taskman Rust providers behind one no-std panic handler. Legacy targets
such as `make rust-tm-pseudodev-provider` still produce the historical focused
archive path for evidence compatibility.

## Evidence

The Rust provider has host coverage for ABI layout, `/dev/null` write/read
behavior, `/dev/zero` write/read behavior, IPC payload zeroing, read clamping,
and both `stat` records:

```sh
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-pseudodev --features host-tests
```

The focused evidence and runtime gates are:

```sh
make tm-pseudodev-evidence
make tm-pseudodev-runtime-smoke
make tm-pseudodev-rc-smoke
```

`make tm-pseudodev-evidence` runs the Rust host tests, builds and audits the
Rust provider archive, checks the six exported symbols, verifies all archive
members are RVC soft-float, verifies LQ taskman link plans and taskman ELFs
omit C `devnull.o` and `devzero.o`, and verifies retired selector rejection for
LQ and the Rust provider builder.

`make tm-pseudodev-runtime-smoke` boots LQ with the Rust-only provider,
verifies the selected LQ taskman dry-run link plan omits C `devnull.o` and
`devzero.o`, verifies the shared Rust provider archive exports all six
`tm_dev*` symbols, and runs a qrvfs-staged `/usr/bin/pseudodev_probe` helper.
The helper checks `/dev/null` write discard, `/dev/null` EOF reads,
`/dev/zero` write discard, `/dev/zero` zero-filled reads, and fstat metadata
for both character devices.

## Rollback

No C rollback target remains.

- `QSOE_RUST_TM_PSEUDODEV=0` fails fast in taskman and provider-archive builds.
- `TM_PSEUDODEV_RC_ROLLBACK=1 scripts/tm-pseudodev-rc-smoke.sh` fails fast.
- Historical RC and rollback evidence is recorded in
  `TASK_MANAGER_PSEUDODEV_RC.md`.

## Current State

`tm_pseudodev` is retired to Rust. Normal LQ taskman builds use the Rust
provider through the shared taskman Rust provider archive while keeping path
dispatch, request decoding, process ownership, and seL4 object handling in C.
