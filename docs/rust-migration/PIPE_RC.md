# `pipe-rs` Rust-Default Release Candidate

Captured: 2026-06-24 15:58 CEST.

This historical note records the `pipe` Rust-default release-candidate path that
preceded C service retirement. It documented the rollback window that is now
closed by `PIPE_RETIREMENT.md`.

## Rust Migration: `pipe`

Status: Historical Rust default RC; superseded by `PIPE_RETIREMENT.md`.
Release or build: `pipe-rs-rc1`, introduced by the
`codex/pipe-rust-default-rc` branch.

### Language Change

- Previous default implementation: C `/sbin/pipe`
- New RC default implementation: Rust `pipe-rs`
- Rust artifact or crate: `rust/bins/pipe-rs`, linked to
  `build/rust/qsoe-pipe-rs.elf`
- C implementation status: retired after this RC; no current C rollback target
  remains
- User-visible behavior changes: none expected for libc `pipe(2)` callers

Known startup-log difference:

- C prints:
  - `[pipe] alive, pid=N`
  - `[pipe] registered at /dev/pipe on chid=N`
- Rust prints:
  - `[pipe-rs] alive`
  - `[pipe-rs] /dev/pipe registered`
  - `[pipe-rs] entering MsgReceive loop`

## Rollback

- Rollback available during RC: yes
- Rollback flag: `QSOE_PIPE_RC_ROLLBACK=1`
- Historical rollback command:

```sh
make pipe-rc-rollback-smoke
```

Default RC data-path smoke:

```sh
make pipe-rc-data-smoke
```

Rollback window: closed by the C retirement recorded in `PIPE_RETIREMENT.md`.

Rollback limitations at RC time: none known for the QSOE/L smoke paths. The
historical rollback image used the same C `/sbin/pipe` artifact as the pre-RC
path.

## Test Evidence

- Host tests: `make rust-quality`
- Artifact audit: `make rust-pipe-link-smoke`
- Existing opt-in data-path smoke: `make rust-pipe-data-smoke`
- Rust-default RC data-path smoke: `make pipe-rc-data-smoke`
- C rollback data-path smoke: `make pipe-rc-rollback-smoke`

The data-path smoke boots QSOE/L, starts `/sbin/pipe`, runs
`/usr/bin/test_pipe_data`, and verifies registration, libc `pipe(2)` round
trip, EOF behavior, helper exit, and boot-to-login.

## Known Limitations

- No C source was removed by this RC; the later retirement removed it.
- The RC covers QSOE/L QEMU data-path behavior, not a full hardware release.
- C retirement is now complete; this note remains as prior RC and rollback
  evidence.

## Review Notes

- Unsafe review: no new Rust unsafe code in this RC target wiring.
- Data or on-disk format migration: none.
- Operator impact: use `make pipe-rc-data-smoke` for the current Rust-only
  service path. The old `make pipe-rc-rollback-smoke` target has been removed.
