# `tm_rsrcdb` C Provider Retirement

Captured: 2026-06-30 CEST.

This note records LQ task-manager resource DB C retirement after the
Rust-default release-candidate path documented in `TASK_MANAGER_RSRCDB_RC.md`
and the shared task-manager provider archive documented in
`TASK_MANAGER_PROVIDERS.md`.

## Rust Migration: `tm_rsrcdb`

Status: Retired C provider.
Release or build: `qsoe-tm-rsrcdb-retired`, introduced by the
`codex/tm-pathmgr-rsrcdb-pseudodev-retirement` branch.

### Language Change

- Previous default implementation: C `lq/taskman/sys/rsrcdb.c`
- New default implementation: Rust `qsoe-tm-rsrcdb`
- Rust artifact or crate: `rust/crates/qsoe-tm-rsrcdb`, linked through the
  shared `build/rust/tm-providers/libqsoe_tm_providers.a` archive
- Removed C source: `lq/taskman/sys/rsrcdb.c` by tracked component override
- Removed C host fixture: `tests/tm_rsrcdb_model_test.c`
- Public ABI retained: `lq/taskman/sys/rsrcdb.h`; LQ taskman's IPC dispatcher
  still calls the `tm_rsrc_*` functions exported by Rust
- User-visible behavior changes: none expected for resource create, attach,
  query, detach, destroy, merge, split, rollback, or process-exit cleanup

## Rollback

- Rollback available: no C rollback target remains.
- `QSOE_RUST_TM_RSRCDB=0` now fails fast in taskman builds and provider
  archive builds.
- `TM_RSRCDB_RC_ROLLBACK=1 scripts/tm-rsrcdb-rc-smoke.sh` now fails fast.
- Historical rollback evidence lives in `TASK_MANAGER_RSRCDB_RC.md`.

## Test Evidence

- Rust host tests: `make check-tm-rsrcdb-model`
- Rust provider archive audit, LQ taskman membership, exported symbol audit,
  and retired selector rejection: `make tm-rsrcdb-evidence`
- Runtime smoke: `make tm-rsrcdb-runtime-smoke`
- Retired compatibility smoke: `make tm-rsrcdb-rc-smoke`

The runtime smoke boots QSOE/L with the Rust-only resource DB provider,
verifies C `sys/rsrcdb.o` is absent, stages `/usr/bin/rsrcdb_probe`, and
checks live `rsrcdbmgr_*` create, attach, query, detach, and destroy calls.

## Review Notes

- Unsafe review: no new Rust unsafe code in the retirement wiring.
- Data or on-disk format migration: none.
- Link review: `tm_rsrcdb` is mandatory in the shared provider archive, so
  taskman can still combine it with other Rust task-manager providers through
  one no-std panic handler.
- Operator impact: `tm_rsrcdb` rollback flags now fail fast; use
  `make tm-rsrcdb-evidence`, `make tm-rsrcdb-runtime-smoke`, or
  `make tm-rsrcdb-rc-smoke` to validate the Rust-only provider path.
