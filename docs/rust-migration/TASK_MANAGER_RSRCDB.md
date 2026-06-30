# Task Manager Resource DB Rust-Default RC Provider

Captured: 2026-06-30 CEST.

## Scope

`qsoe-tm-rsrcdb` is a Rust-default RC provider for the LQ task-manager resource
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

Normal LQ taskman builds use Rust by default:

```sh
QSOE_RUST_TM_RSRCDB=1 make -C lq taskman
```

The C rollback path remains explicit:

```sh
QSOE_RUST_TM_RSRCDB=0 make -C lq taskman
```

The top-level evidence and RC targets are:

```sh
make tm-rsrcdb-evidence
make tm-rsrcdb-runtime-smoke
make tm-rsrcdb-rc-smoke
make tm-rsrcdb-rc-rollback-smoke
```

Multiple taskman Rust providers may be selected together. The shared
`qsoe-tm-providers` archive packages the selected provider crates behind one
no-std panic handler. Legacy targets such as `make rust-tm-rsrcdb-provider`
still produce the historical single-provider output path for focused evidence.

## Evidence

Local validation on 2026-06-30:

```sh
make check-tm-rsrcdb-model
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-rsrcdb --features host-tests
cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-rsrcdb --features host-tests -- -D warnings
make rust-tm-rsrcdb-provider
make tm-rsrcdb-evidence
make tm-rsrcdb-runtime-smoke
make tm-rsrcdb-rc-smoke
make tm-rsrcdb-rc-rollback-smoke
```

`make tm-rsrcdb-evidence` verified:

- C host fixture passes against `lq/taskman/sys/rsrcdb.c`;
- Rust host tests pass for exported ABI behavior;
- Rust staticlib builds for `riscv64imac-unknown-none-elf`;
- Rust provider archive members report RVC soft-float ABI;
- Rust provider archive exports all `tm_rsrc_*` symbols;
- LQ Rust-default dry-run and final taskman link omit C `sys/rsrcdb.o` and
  link the shared taskman Rust provider archive.
- LQ C-rollback dry-run and final taskman link include C `sys/rsrcdb.o`.
- `make tm-rsrcdb-runtime-smoke` boots LQ with Rust `tm_rsrcdb` selected,
  verifies the Rust-default taskman link plan omits C `sys/rsrcdb.o`, verifies
  the shared Rust provider archive exports the `tm_rsrc_*` ABI, and exercises
  live `rsrcdbmgr_*` create, attach, query, detach, and destroy calls through a
  qrvfs-staged `/usr/bin/rsrcdb_probe` helper.
- `make tm-rsrcdb-rc-smoke` repeats the Rust-default selector check and runtime
  smoke under the RC target.
- `make tm-rsrcdb-rc-rollback-smoke` sets `TM_RSRCDB_RC_ROLLBACK=1`, verifies
  the C rollback link plan includes `sys/rsrcdb.o`, and runs the same live
  probe with `TM_RSRCDB_RUNTIME_ALLOW_C=1`.

The C and Rust fixtures also assert the real `rsrc_request_t` ABI size is 56
bytes on RV64-style layouts. Taskman's dispatcher currently replies enough
bytes for the mutated request fields; it does not need to echo the trailing
name pointer.

## C Rollback

C remains the rollback path:

- `QSOE_RUST_TM_RSRCDB=0` keeps `lq/taskman/sys/rsrcdb.c`;
- `QSOE_RUST_TM_RSRCDB=1` excludes `sys/rsrcdb.o` and links
  the shared taskman Rust provider archive.

This RC does not retire C. C removal remains blocked on #26's checklist and a
separate removal PR after the Rust-default path has enough trusted evidence.
