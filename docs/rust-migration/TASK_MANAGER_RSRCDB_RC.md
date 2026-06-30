# Task Manager Resource DB Rust-Default RC

Captured: 2026-06-30 CEST.

`tm_rsrcdb` is in a Rust-default release-candidate window for QSOE/L. Normal
LQ taskman builds use `qsoe-tm-rsrcdb` through the shared
`qsoe-tm-providers` archive. The C provider in `lq/taskman/sys/rsrcdb.c`
remains available as explicit rollback with `QSOE_RUST_TM_RSRCDB=0`.

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

This RC does not retire C and does not change taskman's IPC dispatcher, public
libc `rsrcdbmgr_*` wrappers, IRQ attach/detach plumbing, syscfg construction,
or seL4 object management. C removal remains blocked on the global retirement
checklist and a separate removal PR.
