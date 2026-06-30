# Task Manager Resource DB Historical Rust-Default RC

Captured: 2026-06-30 CEST.

This page records the Rust-default release-candidate path and C rollback drill
that existed before C provider retirement. Current builds are Rust-only; see
`TASK_MANAGER_RSRCDB_RETIREMENT.md` for the retired state.

During the RC window, normal LQ taskman builds used `qsoe-tm-rsrcdb` through
the shared `qsoe-tm-providers` archive. The C provider in
`lq/taskman/sys/rsrcdb.c` remained available as explicit rollback with
`QSOE_RUST_TM_RSRCDB=0`.

## Selectors

```sh
make tm-rsrcdb-rc-smoke
make tm-rsrcdb-rc-rollback-smoke
make tm-rsrcdb-evidence
QSOE_RUST_TM_RSRCDB=0 make -C lq taskman
```

`make tm-rsrcdb-rc-smoke` verifies that the LQ taskman link plan omits
`sys/rsrcdb.o`, builds the Rust-default taskman, and boots through the
existing `rsrcdb_probe` runtime smoke. `make tm-rsrcdb-rc-rollback-smoke`
verifies that the C rollback link plan includes `sys/rsrcdb.o` and boots the
same `rsrcdbmgr_*` probe with `QSOE_RUST_TM_RSRCDB=0`.

## Evidence Boundary

The RC covers the current live resource DB manager surface:

- resource creation and exact destroy;
- attach range search, alignment, split, and granted-range echo;
- query count mode and entry-list mode;
- detach and adjacent free-range merge;
- process-owned range cleanup through normal taskman runtime behavior.

This RC did not change taskman's IPC dispatcher, public libc `rsrcdbmgr_*`
wrappers, IRQ attach/detach plumbing, syscfg construction, or seL4 object
management. C is now retired: `lq/taskman/sys/rsrcdb.c` is removed by the
tracked component override, `QSOE_RUST_TM_RSRCDB=0` fails fast, and
`make tm-rsrcdb-rc-rollback-smoke` is no longer a current target. The current
Rust-only evidence lives in `TASK_MANAGER_RSRCDB.md` and
`TASK_MANAGER_RSRCDB_RETIREMENT.md`.
