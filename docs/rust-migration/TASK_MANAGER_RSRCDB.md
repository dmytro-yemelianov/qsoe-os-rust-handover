# Task Manager Resource DB Provider

Captured: 2026-06-30 CEST.

`qsoe-tm-rsrcdb` is the retired Rust-only provider for the LQ task-manager
resource database:

```text
rust/crates/qsoe-tm-rsrcdb
lq/taskman/sys/rsrcdb.h
```

The previous C provider `lq/taskman/sys/rsrcdb.c` is removed by the tracked
component override. The header remains because `lq/taskman/main.c` still calls
the exported `tm_rsrc_*` ABI for `TM_REQ_RSRC_*` requests.

## Scope

The Rust provider covers:

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

`tm_rsrcdb` is mandatory after C provider retirement:

```text
QSOE_RUST_TM_RSRCDB=1  -> Rust `qsoe-tm-rsrcdb` is linked
QSOE_RUST_TM_RSRCDB=0  -> rejected; C rollback is retired
```

LQ taskman omits C `sys/rsrcdb.o` and links:

```text
build/rust/tm-providers/libqsoe_tm_providers.a
```

The archive is built for `riscv64imac-unknown-none-elf` so it matches
taskman's soft-float ABI. The shared `qsoe-tm-providers` archive packages all
selected taskman Rust providers behind one no-std panic handler. Legacy targets
such as `make rust-tm-rsrcdb-provider` still produce the historical focused
archive path for evidence compatibility.

## Evidence

The Rust provider has host coverage through:

```sh
make check-tm-rsrcdb-model
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-rsrcdb --features host-tests
```

The focused evidence and runtime gates are:

```sh
make tm-rsrcdb-evidence
make tm-rsrcdb-runtime-smoke
make tm-rsrcdb-rc-smoke
```

`make tm-rsrcdb-evidence` runs the Rust host tests, builds and audits the Rust
provider archive, checks all exported `tm_rsrc_*` symbols, verifies all archive
members are RVC soft-float, verifies LQ taskman link plans and taskman ELFs
omit C `sys/rsrcdb.o`, and verifies retired selector rejection for LQ and the
Rust provider builder.

`make tm-rsrcdb-runtime-smoke` boots LQ with the Rust-only provider, verifies
the taskman link plan omits C `sys/rsrcdb.o`, verifies the shared Rust provider
archive exports the `tm_rsrc_*` ABI, and exercises live `rsrcdbmgr_*` create,
attach, query, detach, and destroy calls through a qrvfs-staged
`/usr/bin/rsrcdb_probe` helper.

The Rust fixtures assert the real `rsrc_request_t` ABI size is 56 bytes on
RV64-style layouts. Taskman's dispatcher currently replies enough bytes for the
mutated request fields; it does not need to echo the trailing name pointer.

## Rollback

No C rollback target remains.

- `QSOE_RUST_TM_RSRCDB=0` fails fast in taskman and provider-archive builds.
- `TM_RSRCDB_RC_ROLLBACK=1 scripts/tm-rsrcdb-rc-smoke.sh` fails fast.
- Historical RC and rollback evidence is recorded in `TASK_MANAGER_RSRCDB_RC.md`.

## Current State

`tm_rsrcdb` is retired to Rust. Normal LQ taskman builds use the Rust provider
through the shared taskman Rust provider archive while keeping IPC dispatch,
libc wrappers, IRQ handling, syscfg construction, process ownership, and seL4
object handling in C.
