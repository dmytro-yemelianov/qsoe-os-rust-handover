# `qsoe-tm-sysfs` Rust-Default Release Candidate

Captured: 2026-06-30 CEST.

This note records the `tm_sysfs` Rust-default release-candidate path with C
rollback still available.

## Rust Migration: `tm_sysfs`

Status: Rust default RC.
Release or build: `qsoe-tm-sysfs-rc1`, introduced by the
`codex/tm-sysfs-rust-default-rc` branch.

### Language Change

- Previous default implementation: C `libtaskman/src/tm_sysfs.c`
- New RC default implementation: Rust `qsoe-tm-sysfs`
- Rust artifact or crate: `rust/crates/qsoe-tm-sysfs`
- Taskman Rust link model: selected providers are packaged through the shared
  `build/rust/tm-providers/libqsoe_tm_providers.a` archive
- C implementation status during this RC: rollback-only through
  `QSOE_RUST_TM_SYSFS=0`
- User-visible behavior changes: none expected for `/sys` entry order, path
  resolution, read content, or content lengths

The RC changes only the selected provider for the portable read-only `/sys`
model. Syscfg/FDT discovery, sysmap construction, open/read/readdir dispatch,
process tables, IPC decoding, and seL4 object code remain C.

## Rollback

- Rollback available during RC: yes
- Rollback selector: `QSOE_RUST_TM_SYSFS=0`
- Rollback command:

```sh
make tm-sysfs-rc-rollback-smoke
```

Default RC smoke:

```sh
make tm-sysfs-rc-smoke
```

Rollback window: open. Do not remove `libtaskman/src/tm_sysfs.c` until #26's
C retirement checklist is satisfied and a separate removal PR records fresh
evidence.

## Test Evidence

- C model fixture: `make check-tm-sysfs-model`
- Rust host tests: `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-sysfs --features host-tests`
- Artifact and membership audit: `make tm-sysfs-evidence`
- Existing Rust-selected runtime smoke: `make tm-sysfs-runtime-smoke`
- Rust-default RC smoke: `make tm-sysfs-rc-smoke`
- C rollback RC smoke: `make tm-sysfs-rc-rollback-smoke`

The RC smoke builds NQ and LQ taskman in the default selector mode and verifies
that C `tm_sysfs.o` is absent from `libtaskman.a`. The rollback smoke repeats
the archive-membership check with `QSOE_RUST_TM_SYSFS=0`, where C
`tm_sysfs.o` must be present. Both modes boot QSOE/L with a staged sysinit
fragment that enumerates `/sys` and reads `/sys/board`, `/sys/builddate`,
`/sys/cmdline`, `/sys/osname`, and `/sys/version`.

## Known Limitations

- No C source is removed by this RC.
- The RC covers QSOE/L QEMU runtime behavior, not a full hardware release.
- Only the portable `/sys` data model is selected through Rust. Syscfg/FDT
  discovery, sysmap construction, path dispatch, process lifecycle, IPC, and
  seL4 object code remain C.

## Review Notes

- Unsafe review: no new Rust unsafe code in this RC target wiring.
- Data or on-disk format migration: none.
- Operator impact: use `make tm-sysfs-rc-smoke` to validate the Rust default
  RC path and `make tm-sysfs-rc-rollback-smoke` to validate rollback.
