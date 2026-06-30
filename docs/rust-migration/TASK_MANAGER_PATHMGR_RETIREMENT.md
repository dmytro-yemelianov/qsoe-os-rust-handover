# `tm_pathmgr` C Provider Retirement

Captured: 2026-06-30 CEST.

This note records task-manager path registry C retirement after the
Rust-default release-candidate path documented in `TASK_MANAGER_PATHMGR_RC.md`
and the shared task-manager provider archive documented in
`TASK_MANAGER_PROVIDERS.md`.

## Rust Migration: `tm_pathmgr`

Status: Retired C provider.
Release or build: `qsoe-tm-pathmgr-retired`, introduced by the
`codex/tm-pathmgr-rsrcdb-pseudodev-retirement` branch.

### Language Change

- Previous default implementation: C `libtaskman/src/pathmgr.c`
- New default implementation: Rust `qsoe-tm-pathmgr`
- Rust artifact or crate: `rust/crates/qsoe-tm-pathmgr`, linked through the
  shared `build/rust/tm-providers/libqsoe_tm_providers.a` archive
- Removed C source: `libtaskman/src/pathmgr.c`
- Removed C host fixture: `tests/tm_pathmgr_model_test.c`
- Public ABI retained: `libtaskman/include/tm_pathmgr.h`; taskman path,
  process, and service-registration code still calls the `tm_pathmgr_*`
  functions exported by Rust
- User-visible behavior changes: none expected for path registration,
  unregister-on-exit cleanup, longest-prefix resolution, symlink expansion,
  repath, or PMDIR child iteration

## Rollback

- Rollback available: no C rollback target remains.
- `QSOE_RUST_TM_PATHMGR=0` now fails fast in taskman builds and provider
  archive builds.
- `TM_PATHMGR_RC_ROLLBACK=1 scripts/tm-pathmgr-rc-smoke.sh` now fails fast.
- Historical rollback evidence lives in `TASK_MANAGER_PATHMGR_RC.md`.

## Test Evidence

- Rust host tests: `make check-tm-pathmgr-model`
- Rust provider archive audit, NQ/LQ taskman membership, exported symbol audit,
  and retired selector rejection: `make tm-pathmgr-evidence`
- Runtime smoke: `make tm-pathmgr-runtime-smoke`
- Retired compatibility smoke: `make tm-pathmgr-rc-smoke`

The runtime smoke boots QSOE/L with the Rust-only path registry, verifies C
`pathmgr.o` is absent, stages `/usr/bin/pathmgr_probe`, and checks `/dev`
PMDIR readdir, `/etc/passwd` through the cpio-root symlink, `/dev/console`
repath, dynamic helper registration, duplicate registration rejection, MsgSend
through the resolved external binding, and unregister-on-exit cleanup.

## Review Notes

- Unsafe review: no new Rust unsafe code in the retirement wiring.
- Data or on-disk format migration: none.
- Link review: `tm_pathmgr` is mandatory in the shared provider archive, so
  taskman can still combine it with other Rust task-manager providers through
  one no-std panic handler.
- Operator impact: `tm_pathmgr` rollback flags now fail fast; use
  `make tm-pathmgr-evidence`, `make tm-pathmgr-runtime-smoke`, or
  `make tm-pathmgr-rc-smoke` to validate the Rust-only provider path.
