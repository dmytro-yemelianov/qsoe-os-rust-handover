# `tm_cred` C Provider Retirement

Captured: 2026-06-30 CEST.

This note records task-manager credential policy provider C retirement after the
Rust-default release-candidate path documented in `TASK_MANAGER_CRED_RC.md` and
the shared task-manager provider archive documented in
`TASK_MANAGER_PROVIDERS.md`.

## Rust Migration: `tm_cred`

Status: Retired C provider.
Release or build: `qsoe-tm-cred-retired`, introduced by the
`codex/tm-cred-c-retirement` branch.

### Language Change

- Previous default implementation: C `libtaskman/src/cred.c`
- New default implementation: Rust `qsoe-tm-cred`
- Rust artifact or crate: `rust/crates/qsoe-tm-cred`, linked through the shared
  `build/rust/tm-providers/libqsoe_tm_providers.a` archive
- Removed C source: `libtaskman/src/cred.c`
- Removed C host fixture: `tests/tm_cred_model_test.c`
- Public ABI retained: `libtaskman/include/tm_cred.h`; taskman process code
  still calls the `tm_cred_*` functions exported by Rust
- User-visible behavior changes: none expected for uid/gid mutation, cwd
  storage, umask exchange, permission checks, or spawn inheritance

## Rollback

- Rollback available: no C rollback target remains.
- `QSOE_RUST_TM_CRED=0` now fails fast in taskman builds and provider archive
  builds.
- `TM_CRED_RC_ROLLBACK=1 scripts/tm-cred-rc-smoke.sh` now fails fast.
- Historical rollback evidence lives in `TASK_MANAGER_CRED_RC.md`.

## Test Evidence

- Rust host tests: `make check-tm-cred-model`
- Rust provider archive audit, NQ/LQ taskman membership, exported symbol audit,
  and retired selector rejection: `make tm-cred-evidence`
- Runtime smoke: `make tm-cred-runtime-smoke`
- Retired compatibility smoke: `make tm-cred-rc-smoke`

The runtime smoke boots QSOE/L with the Rust-only credential provider, stages
`/usr/bin/cred_probe` into the smoke qrvfs image, and checks initial root ids,
cwd round-trip through `/usr/conf`, umask exchange, held-id uid/gid transitions,
non-root `setuid(0)` rejection, and child spawn inheritance.

## Review Notes

- Unsafe review: no new Rust unsafe code in the retirement wiring.
- Data or on-disk format migration: none.
- Link review: `tm_cred` is mandatory in the shared provider archive, so
  taskman can still combine it with other Rust task-manager providers through
  one no-std panic handler.
- Operator impact: `tm_cred` rollback flags now fail fast; use
  `make tm-cred-evidence`, `make tm-cred-runtime-smoke`, or
  `make tm-cred-rc-smoke` to validate the Rust-only provider path.
