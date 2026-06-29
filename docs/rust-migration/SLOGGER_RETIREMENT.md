# `slogger` C Service Retirement

Captured: 2026-06-29 CEST.

This note records the first production-service C retirement in the Rust
migration: `/sbin/slogger`. The retired service had already passed the
Rust-default release-candidate path documented in `SLOGGER_RC.md`.

## Rust Migration: `slogger`

Status: Retired C service.
Release or build: `slogger-rs-retired`, introduced by the
`codex/retire-c-slogger` branch.

### Language Change

- Previous default implementation: C `/sbin/slogger`
- New default implementation: Rust `slogger-rs`
- Rust artifact or crate: `rust/bins/slogger-rs`, staged as
  `build/rust/selected/sbin/slogger.elf` and installed into images as
  `/sbin/slogger`
- Removed C source: `quser/sbin/slogger/main.c` and
  `quser/sbin/slogger/Makefile` through
  `patches/components/quser-retire-slogger-c.patch`
- Image packaging: NQ and LQ CPIO recipes call top-level `make
  slogger-artifact` with their selected `libc.so`, then pass
  `SBIN_SLOG_ELF` into the `quser` CPIO build.
- User-visible behavior changes: startup text remains shorter than the old C
  service, as documented in `SLOGGER_BOOT_COMPARE.md`; `/dev/slog` readback
  behavior is preserved by smoke evidence.

## Rollback

- Rollback available: no C rollback target remains.
- `QSOE_RUST_SLOGGER=0 make slogger-artifact` now fails fast.
- `QSOE_SLOGGER_RC_ROLLBACK=1 scripts/slogger-rc-boot-smoke.sh
  --prepare-only` now fails fast.
- Historical rollback evidence lives in `SLOGGER_RC.md`.

## Test Evidence

- Shell syntax: `bash -n scripts/apply-component-overrides.sh
  scripts/select-slogger-artifact.sh scripts/rust-slogger-boot-smoke.sh
  scripts/slogger-rc-boot-smoke.sh scripts/capture-elf-baseline.sh`
- Python syntax: `python3 -m py_compile scripts/slog-readback-smoke.py`
- Component override replay: `./scripts/apply-component-overrides.sh`
- Rust quality gate: `make rust-check`
- Artifact link/audit: `make rust-slogger-link-smoke`
- Rust-only selected artifact: `make slogger-artifact`
- Expected retired-C selector failure: `QSOE_RUST_SLOGGER=0 make
  slogger-artifact`
- Expected retired-C rollback failure:
  `QSOE_SLOGGER_RC_ROLLBACK=1 scripts/slogger-rc-boot-smoke.sh
  --prepare-only`
- Runtime readback smoke: `make slogger-rc-readback-smoke`
- Direct userland package build: `make -C quser cpio`
- Normal source build: `make`
- Normal LQ boot smoke: `scripts/boot-smoke.sh -k lq -t 120`

The readback smoke boots QSOE/L into the rescue shell, runs `/bin/sloginfo`,
and verifies a boot-time `pci-server:` slog entry is readable through
`/dev/slog` with Rust `slogger-rs` staged as `/sbin/slogger`.

## Review Notes

- Unsafe review: no new Rust unsafe code in this retirement wiring.
- Data or on-disk format migration: none.
- Operator impact: `slogger` rollback flags now fail fast; use
  `make slogger-rc-readback-smoke` or `scripts/boot-smoke.sh -k lq -t 120` to
  validate the Rust-only service path.
