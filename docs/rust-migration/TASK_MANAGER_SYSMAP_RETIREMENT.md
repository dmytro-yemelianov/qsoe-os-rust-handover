# Task Manager Sysmap C Retirement

Captured: 2026-06-30 CEST.

## Scope

The LQ task-manager `tm_sysmap` page builder is Rust-only. The retirement
removes:

- `lq/taskman/sys/sysmap.c`
- `tests/tm_sysmap_model_test.c`
- `tests/tm_sysmap_model_prelude.h`

The Rust provider remains in `rust/crates/qsoe-tm-sysmap/src/lib.rs` and
exports the existing `tm_sysmap_build` and `tm_sysmap_get` ABI declared by
`lq/taskman/sys/sysmap.h`.

This retirement covers only the LQ `PSYS` page builder. FDT parsing, syscfg
construction, child VSpace mapping, process tables, capability ownership, and
seL4 object code remain C.

## Selector State

`QSOE_RUST_TM_SYSMAP=1` is mandatory in umbrella and LQ taskman builds.
`QSOE_RUST_TM_SYSMAP=0` now fails fast.

The rollback smoke target was removed:

```sh
make tm-sysmap-rc-rollback-smoke
make container-tm-sysmap-rc-rollback-smoke
```

The retained checks are:

```sh
make check-tm-sysmap-model
make tm-sysmap-evidence
make tm-sysmap-runtime-smoke
make tm-sysmap-rc-smoke
```

`make tm-sysmap-evidence` verifies Rust host tests, soft-float archive shape,
the exported `tm_sysmap_build` and `tm_sysmap_get` symbols, LQ taskman links
without C `sys/sysmap.o`, and retired selector rejection for both the LQ
top-level and LQ taskman makefiles.

`make tm-sysmap-rc-smoke` verifies the retired/default path and boots QSOE/L
through the spawned-child `sysinfo` consumer of the mapped `PSYS` page.

## Adjacent Evidence

Adjacent task-manager evidence that previously pinned
`QSOE_RUST_TM_SYSMAP=0` now pins `QSOE_RUST_TM_SYSMAP=1`:

- `scripts/tm-pathmgr-evidence.sh`

This keeps the path manager test focused on path manager archive membership
while respecting the retired tm_sysmap selector.

## Reintroduction Rule

Do not reintroduce C `tm_sysmap` rollback without a new issue, explicit
rollback justification, and fresh PR evidence.
