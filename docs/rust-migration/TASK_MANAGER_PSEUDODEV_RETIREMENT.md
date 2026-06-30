# `tm_pseudodev` C Provider Retirement

Captured: 2026-06-30 CEST.

This note records LQ task-manager pseudo-device C retirement after the
Rust-default release-candidate path documented in
`TASK_MANAGER_PSEUDODEV_RC.md` and the shared task-manager provider archive
documented in `TASK_MANAGER_PROVIDERS.md`.

## Rust Migration: `tm_pseudodev`

Status: Retired C provider.
Release or build: `qsoe-tm-pseudodev-retired`, introduced by the
`codex/tm-pathmgr-rsrcdb-pseudodev-retirement` branch.

### Language Change

- Previous default implementation: C `lq/taskman/sys/devnull.c` and
  `lq/taskman/sys/devzero.c`
- New default implementation: Rust `qsoe-tm-pseudodev`
- Rust artifact or crate: `rust/crates/qsoe-tm-pseudodev`, linked through the
  shared `build/rust/tm-providers/libqsoe_tm_providers.a` archive
- Removed C sources: `lq/taskman/sys/devnull.c` and `lq/taskman/sys/devzero.c`
  by tracked component override
- Public ABI retained: `lq/taskman/sys/devnull.h` and
  `lq/taskman/sys/devzero.h`; LQ taskman path IO still calls the
  `tm_devnull_*` and `tm_devzero_*` functions exported by Rust
- User-visible behavior changes: none expected for `/dev/null` write discard,
  `/dev/null` EOF reads, `/dev/zero` write discard, zero-filled reads, or stat
  metadata

## Rollback

- Rollback available: no C rollback target remains.
- `QSOE_RUST_TM_PSEUDODEV=0` now fails fast in taskman builds and provider
  archive builds.
- `TM_PSEUDODEV_RC_ROLLBACK=1 scripts/tm-pseudodev-rc-smoke.sh` now fails
  fast.
- Historical rollback evidence lives in `TASK_MANAGER_PSEUDODEV_RC.md`.

## Test Evidence

- Rust host tests:
  `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-pseudodev --features host-tests`
- Rust provider archive audit, LQ taskman membership, exported symbol audit,
  and retired selector rejection: `make tm-pseudodev-evidence`
- Runtime smoke: `make tm-pseudodev-runtime-smoke`
- Retired compatibility smoke: `make tm-pseudodev-rc-smoke`

The runtime smoke boots QSOE/L with the Rust-only pseudo-device provider,
verifies C `devnull.o` and `devzero.o` are absent, stages
`/usr/bin/pseudodev_probe`, and checks live `/dev/null` and `/dev/zero` open,
write, read, and fstat calls.

## Review Notes

- Unsafe review: no new Rust unsafe code in the retirement wiring.
- Data or on-disk format migration: none.
- Link review: `tm_pseudodev` is mandatory in the shared provider archive, so
  taskman can still combine it with other Rust task-manager providers through
  one no-std panic handler.
- Operator impact: `tm_pseudodev` rollback flags now fail fast; use
  `make tm-pseudodev-evidence`, `make tm-pseudodev-runtime-smoke`, or
  `make tm-pseudodev-rc-smoke` to validate the Rust-only provider path.
