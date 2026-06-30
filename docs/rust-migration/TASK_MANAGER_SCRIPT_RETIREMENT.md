# `tm_script` C Provider Retirement

Captured: 2026-06-30 CEST.

This note records the task-manager shebang parser C retirement after the
Rust-default release-candidate path documented in `TASK_MANAGER_SCRIPT_RC.md`
and the shared task-manager provider archive documented in
`TASK_MANAGER_PROVIDERS.md`.

## Rust Migration: `tm_script`

Status: Retired C provider.
Release or build: `qsoe-tm-script-retired`, introduced by the
`codex/tm-script-c-retirement` branch.

### Language Change

- Previous default implementation: C `libtaskman/src/script.c`
- New default implementation: Rust `qsoe-tm-script`
- Rust artifact or crate: `rust/crates/qsoe-tm-script`, linked through the
  shared `build/rust/tm-providers/libqsoe_tm_providers.a` archive
- Removed C source: `libtaskman/src/script.c`
- Public ABI retained: `libtaskman/include/tm_script.h`; taskman C spawn code
  still calls `tm_script_parse_shebang`, now exported by Rust
- User-visible behavior changes: none expected for shebang parsing, direct
  script spawn, interpreter path handling, or optional argument parsing

## Rollback

- Rollback available: no C rollback target remains.
- `QSOE_RUST_TM_SCRIPT=0` now fails fast in taskman builds and provider
  archive builds.
- `TM_SCRIPT_RC_ROLLBACK=1 scripts/tm-script-rc-smoke.sh` now fails fast.
- Historical rollback evidence lives in `TASK_MANAGER_SCRIPT_RC.md`.

## Test Evidence

- Rust host tests: `make check-tm-script-model`
- Rust provider archive audit: `make rust-tm-script-provider`
- Rust-only taskman membership and retired selector rejection:
  `make tm-script-evidence`
- Runtime smoke: `make tm-script-runtime-smoke`
- Retired compatibility smoke: `make tm-script-rc-smoke`

The runtime smoke boots QSOE/L, stages a temporary executable
`/usr/bin/tm_script_probe` shell script, runs it directly from sysinit, and
checks the expected marker plus clean exit marker. This forces taskman spawn to
parse the shebang before loading `/bin/sh`.

## Review Notes

- Unsafe review: no new Rust unsafe code in the retirement wiring.
- Data or on-disk format migration: none.
- Link review: `tm_script` is mandatory in the shared provider archive, so
  taskman can still combine it with other Rust task-manager providers through
  one no-std panic handler.
- Operator impact: `tm_script` rollback flags now fail fast; use
  `make tm-script-evidence`, `make tm-script-runtime-smoke`, or
  `make tm-script-rc-smoke` to validate the Rust-only provider path.
