# Task Manager Resource DB Rust Opt-in Provider

Captured: 2026-06-29 CEST.

## Scope

`qsoe-tm-rsrcdb` is a Rust opt-in provider for the LQ task-manager resource
database in:

```text
lq/taskman/sys/rsrcdb.c
lq/taskman/sys/rsrcdb.h
```

It exports the existing `tm_rsrc_*` ABI used by `lq/taskman/main.c` for
`TM_REQ_RSRC_*` requests.

It covers:

- fixed 256-entry resource pool initialization;
- per-class sorted range lists;
- create and exact destroy;
- attach range search, alignment, splitting, granted-range echo, and rollback
  on partial attach failure;
- detach and adjacent free-range merge;
- query count mode and entry-list mode;
- process-exit release by owner pid;
- boot seeding from `TM_SYSCFG_TAG_MEMORY` records.

It does not replace:

- the public libc `rsrcdbmgr_*` wrappers;
- taskman's IPC dispatcher;
- IRQ attach/detach;
- FDT parsing or syscfg construction;
- path dispatch, process ownership, capability ownership, or seL4 object
  manipulation.

## Selector

Normal LQ taskman builds remain C-default:

```sh
QSOE_RUST_TM_RSRCDB=0 make -C lq taskman
```

The Rust opt-in path is:

```sh
QSOE_RUST_TM_RSRCDB=1 make -C lq taskman
```

The top-level evidence target is:

```sh
make tm-rsrcdb-evidence
```

Current taskman Rust providers are mutually exclusive. Do not set more than one
`QSOE_RUST_TM_*` taskman provider selector until the providers are packaged into
one shared staticlib.

## Evidence

Local validation on 2026-06-29:

```sh
make check-tm-rsrcdb-model
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-rsrcdb --features host-tests
cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-rsrcdb --features host-tests -- -D warnings
make rust-tm-rsrcdb-provider
make tm-rsrcdb-evidence
```

`make tm-rsrcdb-evidence` verified:

- C host fixture passes against `lq/taskman/sys/rsrcdb.c`;
- Rust host tests pass for exported ABI behavior;
- Rust staticlib builds for `riscv64imac-unknown-none-elf`;
- Rust provider archive members report RVC soft-float ABI;
- Rust provider archive exports all `tm_rsrc_*` symbols;
- LQ C-default dry-run and final taskman link include C `sys/rsrcdb.o`;
- LQ Rust-selected dry-run and final taskman link omit C `sys/rsrcdb.o` and
  link `build/rust/tm-rsrcdb/libqsoe_tm_rsrcdb.a`.

The C and Rust fixtures also assert the real `rsrc_request_t` ABI size is 56
bytes on RV64-style layouts. Taskman's dispatcher currently replies enough
bytes for the mutated request fields; it does not need to echo the trailing
name pointer.

## C Rollback

C remains the default and rollback path:

- `QSOE_RUST_TM_RSRCDB=0` keeps `lq/taskman/sys/rsrcdb.c`;
- `QSOE_RUST_TM_RSRCDB=1` excludes `sys/rsrcdb.o` and links
  `build/rust/tm-rsrcdb/libqsoe_tm_rsrcdb.a`.

Do not promote this provider to a Rust-default RC until runtime coverage proves
resource attach/query/detach behavior through `rsrcdbmgr_*` callers, and do not
retire C until #26 is satisfied in a separate removal PR.
