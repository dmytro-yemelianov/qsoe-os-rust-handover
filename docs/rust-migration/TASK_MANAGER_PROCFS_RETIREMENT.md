# `tm_procfs` C Provider Retirement

Captured: 2026-06-29 CEST.

This note records the first task-manager provider C retirement after the
Rust-default release-candidate path documented in `TASK_MANAGER_PROCFS_RC.md`
and the shared task-manager provider archive documented in
`TASK_MANAGER_PROVIDERS.md`.

## Rust Migration: `tm_procfs`

Status: Retired C provider.
Release or build: `qsoe-tm-procfs-retired`, introduced by the
`codex/tm-procfs-c-retirement` branch.

### Language Change

- Previous default implementation: C `libtaskman/src/tm_procfs.c`
- New default implementation: Rust `qsoe-tm-procfs`
- Rust artifact or crate: `rust/crates/qsoe-tm-procfs`, linked through the
  shared `build/rust/tm-providers/libqsoe_tm_providers.a` archive
- Removed C source: `libtaskman/src/tm_procfs.c`
- Public ABI retained: `libtaskman/include/tm_procfs.h`; NQ/LQ taskman C glue
  still calls the same `tm_procfs_*` symbols exported by Rust
- User-visible behavior changes: none expected for `/proc`, `/proc/<pid>`, or
  `/proc/<pid>/info`

## Rollback

- Rollback available: no C rollback target remains.
- `QSOE_RUST_TM_PROCFS=0` now fails fast in taskman builds and provider
  archive builds.
- `TM_PROCFS_RC_ROLLBACK=1 scripts/tm-procfs-rc-smoke.sh` now fails fast.
- Historical rollback evidence lives in `TASK_MANAGER_PROCFS_RC.md`.

## Test Evidence

- Rust host tests: `make check-tm-procfs-model`
- Rust provider archive audit: `make rust-tm-procfs-provider`
- Rust-only taskman membership and retired selector rejection:
  `make tm-procfs-evidence`
- Runtime smoke: `make tm-procfs-rc-smoke`
- Shared archive regression: `make tm-providers-evidence`
- Full Rust quality gate: `make rust-check`

The `/proc` smoke boots QSOE/L, injects a temporary sysinit fragment, verifies
`/bin/ls /proc`, reads `/proc/1/info`, and checks the expected `taskman` info
fields before reaching `login:`.

## Review Notes

- Unsafe review: no new Rust unsafe code in the retirement wiring.
- Data or on-disk format migration: none.
- Link review: `tm_procfs` is mandatory in the shared provider archive, so
  taskman can still combine it with opt-in Rust task-manager providers through
  one no-std panic handler.
- Operator impact: `tm_procfs` rollback flags now fail fast; use
  `make tm-procfs-evidence`, `make tm-procfs-rc-smoke`, or `make procfs-smoke`
  to validate the Rust-only provider path.
