# `pipe` C Service Retirement

Captured: 2026-06-29 CEST.

This note records the `pipe` C service retirement after the Rust-default
release-candidate path documented in `PIPE_RC.md`.

## Rust Migration: `pipe`

Status: Retired C service.
Release or build: `pipe-rs-retired`, introduced by the
`codex/retire-c-pipe` branch.

### Language Change

- Previous default implementation: C `/sbin/pipe`
- New default implementation: Rust `pipe-rs`
- Rust artifact or crate: `rust/bins/pipe-rs`, staged as
  `build/rust/selected/sbin/pipe.elf` and installed into images as
  `/sbin/pipe`
- Removed C source: `quser/sbin/pipe/main.c` and
  `quser/sbin/pipe/Makefile` through
  `patches/components/quser-retire-pipe-c.patch`
- Image packaging: NQ and LQ CPIO recipes call top-level `make pipe-artifact`
  with their selected `libc.so`, then pass `SBIN_PIPE_ELF` into the `quser`
  CPIO build.
- User-visible behavior changes: startup text uses the Rust markers documented
  in `PIPE_RC.md`; libc `pipe(2)` data-path behavior is preserved by smoke
  evidence.

## Rollback

- Rollback available: no C rollback target remains.
- `QSOE_RUST_PIPE=0 make pipe-artifact` now fails fast.
- `QSOE_PIPE_RC_ROLLBACK=1 scripts/pipe-rc-data-smoke.sh` now fails fast.
- Historical rollback evidence lives in `PIPE_RC.md`.

## Test Evidence

- Shell syntax: `bash -n scripts/apply-component-overrides.sh
  scripts/select-pipe-artifact.sh scripts/rust-pipe-smoke.sh
  scripts/rust-pipe-data-smoke.sh scripts/pipe-rc-data-smoke.sh
  scripts/pipe-smoke.sh`
- Component override replay: `./scripts/apply-component-overrides.sh`
- Patch recognition: reverse dry-runs for
  `patches/components/nq-makefile-rust-pipe-retired.patch`,
  `patches/components/lq-makefile-rust-pipe-retired.patch`, and
  `patches/components/quser-retire-pipe-c.patch`
- Rust quality gate: `make rust-check`
- Artifact link/audit: `make rust-pipe-link-smoke`
- Rust-only selected artifact: `make pipe-artifact`
- Expected retired-C selector failure: `QSOE_RUST_PIPE=0 make pipe-artifact`
- Expected retired-C rollback failure:
  `QSOE_PIPE_RC_ROLLBACK=1 scripts/pipe-rc-data-smoke.sh`
- Runtime data-path smoke: `make rust-pipe-data-smoke`
- Retired compatibility smoke: `make pipe-rc-data-smoke`
- Focused registration boot smoke: `make pipe-smoke`
- Direct userland package build: `make -C quser cpio`
- Normal source build: `make`
- Normal LQ boot smoke: `scripts/boot-smoke.sh -k lq -t 120`

The data-path smoke boots QSOE/L, starts `/sbin/pipe`, runs
`/usr/bin/test_pipe_data`, and verifies registration, libc `pipe(2)` round trip,
EOF behavior, helper exit, and boot-to-login.

## Review Notes

- Unsafe review: no new Rust unsafe code in this retirement wiring.
- Data or on-disk format migration: none.
- Operator impact: `pipe` rollback flags now fail fast; use
  `make pipe-rc-data-smoke` or `scripts/boot-smoke.sh -k lq -t 120` to validate
  the Rust-only service path.
