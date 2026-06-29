# `qsoe-tm-procfs` Rust-Default Release Candidate

Captured: 2026-06-28 21:08 CEST.

This note records the `tm_procfs` Rust-default release-candidate path. It does
not retire the C implementation. Normal source builds still preserve the C
provider, and the RC image path keeps a one-command C rollback drill.

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
- C implementation status: rollback-only for the RC image path; still present
  in tree and still used by non-RC normal builds
- User-visible behavior changes: none expected for `/proc`, `/proc/<pid>`, or
  `/proc/<pid>/info`

The RC changes only the selected provider for the portable task-manager
`tm_procfs` model. LQ process-table ownership, `/proc` path glue, connection
context handling, process lifecycle, spawn, loader, and seL4 invocation code
remain C.

## Rollback

- Rollback available: yes
- Rollback flag: `TM_PROCFS_RC_ROLLBACK=1`
- Rollback command:

```sh
make tm-procfs-rc-rollback-smoke
```

Default RC smoke:

```sh
make tm-procfs-rc-smoke
```

Rollback window: still open until the C retirement gate in `RETIREMENT.md` is
satisfied and a separate removal PR is reviewed.

Rollback limitations: none known for the QSOE/L `/proc` smoke path. The
rollback image uses the same C `tm_procfs.o` provider as the pre-RC path.

## Test Evidence

- Host tests: `make rust-quality`
- C model fixture: `make check-tm-procfs-model`
- Artifact and membership audit: `make tm-procfs-evidence`
- Existing opt-in smoke: `QSOE_RUST_TM_PROCFS=1 make procfs-smoke`
- Rust-default RC smoke: `make tm-procfs-rc-smoke`
- C rollback smoke: `make tm-procfs-rc-rollback-smoke`

The `/proc` smoke boots QSOE/L, injects a temporary sysinit fragment, verifies
`/bin/ls /proc`, reads `/proc/1/info`, and checks the expected `taskman` info
fields before reaching `login:`.

## Known Limitations

- No C source is removed by this RC.
- The RC covers QSOE/L QEMU `/proc` behavior, not a full hardware release.
- Only the portable `tm_procfs` model is selected through Rust; task-manager
  process lifecycle and LQ procfs glue remain C.
- C retirement remains blocked by #26 until the retirement checklist is
  reviewed; this RC evidence does not remove or disable the C implementation.

## Review Notes

- Unsafe review: no new Rust unsafe code in this RC target wiring.
- Data or on-disk format migration: none.
- Operator impact: use `make tm-procfs-rc-smoke` to validate the Rust default
  RC path and `make tm-procfs-rc-rollback-smoke` to validate rollback.
