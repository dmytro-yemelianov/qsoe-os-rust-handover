# `qsoe-tm-procfs` Rust-Default Release Candidate

Captured: 2026-06-28 21:08 CEST.

This note records the historical `tm_procfs` Rust-default release-candidate
path that preceded C provider retirement. The C implementation is now retired;
see `TASK_MANAGER_PROCFS_RETIREMENT.md` for the current Rust-only path.

## Rust Migration: `tm_procfs`

Status: Rust default RC.
Release or build: `qsoe-tm-procfs-rc1`, introduced by the
`codex/tm-procfs-rust-default-rc` branch.

### Language Change

- Previous default implementation: C `libtaskman/src/tm_procfs.c`
- New RC default implementation: Rust `qsoe-tm-procfs`
- Rust artifact or crate: `rust/crates/qsoe-tm-procfs`, linked as
  `build/rust/tm-procfs/libqsoe_tm_procfs.a`
- Current taskman Rust link model: selected providers are packaged through the
  shared `build/rust/tm-providers/libqsoe_tm_providers.a` archive
- C implementation status during this RC: rollback-only for the RC image path;
  later removed by `TASK_MANAGER_PROCFS_RETIREMENT.md`
- User-visible behavior changes: none expected for `/proc`, `/proc/<pid>`, or
  `/proc/<pid>/info`

The RC changes only the selected provider for the portable task-manager
`tm_procfs` model. LQ process-table ownership, `/proc` path glue, connection
context handling, process lifecycle, spawn, loader, and seL4 invocation code
remain C.

## Rollback

- Historical rollback available during RC: yes
- Historical rollback flag: `TM_PROCFS_RC_ROLLBACK=1`
- Historical rollback command:

```sh
make tm-procfs-rc-rollback-smoke
```

Default RC smoke:

```sh
make tm-procfs-rc-smoke
```

Rollback window: closed after the C retirement gate in `RETIREMENT.md` was
satisfied for `tm_procfs`.

Current rollback limitations: the C provider is retired. The historical
rollback image used the same C `tm_procfs.o` provider as the pre-RC path.

## Test Evidence

- Host tests: `make rust-quality`
- C model fixture: `make check-tm-procfs-model`
- Artifact and membership audit: `make tm-procfs-evidence`
- Existing opt-in smoke: `QSOE_RUST_TM_PROCFS=1 make procfs-smoke`
- Rust-default RC smoke: `make tm-procfs-rc-smoke`
- Historical C rollback smoke: `make tm-procfs-rc-rollback-smoke`

The `/proc` smoke boots QSOE/L, injects a temporary sysinit fragment, verifies
`/bin/ls /proc`, reads `/proc/1/info`, and checks the expected `taskman` info
fields before reaching `login:`.

## Known Limitations

- No C source was removed by this RC; removal happened later in
  `TASK_MANAGER_PROCFS_RETIREMENT.md`.
- The RC covers QSOE/L QEMU `/proc` behavior, not a full hardware release.
- Only the portable `tm_procfs` model is selected through Rust; task-manager
  process lifecycle and LQ procfs glue remain C.
- C retirement is now complete; this note remains as prior RC and rollback
  evidence.

## Review Notes

- Unsafe review: no new Rust unsafe code in this RC target wiring.
- Data or on-disk format migration: none.
- Operator impact: use `make tm-procfs-rc-smoke` to validate the current
  Rust-only path. `TM_PROCFS_RC_ROLLBACK=1` now fails fast.
