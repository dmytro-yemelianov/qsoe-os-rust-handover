# `qsoe-tm-syscfg` Rust-Default Release Candidate

Captured: 2026-06-30 CEST.

This note records the `tm_syscfg` Rust-default release-candidate path with C
rollback still available.

## Rust Migration: `tm_syscfg`

Status: Rust default RC.
Release or build: `qsoe-tm-syscfg-rc1`, introduced by the
`codex/tm-syscfg-rust-default-rc` branch.

### Language Change

- Previous default implementation: C `libtaskman/src/syscfg.c`
- New RC default implementation: Rust `qsoe-tm-syscfg`
- Rust artifact or crate: `rust/crates/qsoe-tm-syscfg`
- Taskman Rust link model: selected providers are packaged through the shared
  `build/rust/tm-providers/libqsoe_tm_providers.a` archive
- C implementation status during this RC: rollback-only through
  `QSOE_RUST_TM_SYSCFG=0`
- User-visible behavior changes: none expected for TLV syscfg emission or
  lookup semantics

The RC changes only the selected provider for the portable
`libtaskman/src/syscfg.c` TLV builder/walker. LQ's private FDT-backed runtime
syscfg builder, FDT parsing, sysmap construction, `/sys` file serving, process
tables, IPC decoding, and seL4 object code remain C.

## Rollback

- Rollback available during RC: yes
- Rollback selector: `QSOE_RUST_TM_SYSCFG=0`
- Rollback command:

```sh
make tm-syscfg-rc-rollback-smoke
```

Default RC smoke:

```sh
make tm-syscfg-rc-smoke
```

Rollback window: open. Do not remove `libtaskman/src/syscfg.c` until #26's C
retirement checklist is satisfied and a separate removal PR records fresh
evidence.

## Test Evidence

- C model fixture: `make check-tm-syscfg-model`
- Rust host tests: `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-syscfg --features host-tests`
- Artifact and membership audit: `make tm-syscfg-evidence`
- Existing Rust-selected runtime smoke: `make tm-syscfg-runtime-smoke`
- Rust-default RC smoke: `make tm-syscfg-rc-smoke`
- C rollback RC smoke: `make tm-syscfg-rc-rollback-smoke`

The RC smoke builds NQ and LQ taskman in the default selector mode and verifies
that C `syscfg.o` is absent from `libtaskman.a`. The rollback smoke repeats
the archive-membership check with `QSOE_RUST_TM_SYSCFG=0`, where C `syscfg.o`
must be present. Both modes boot QSOE/L with a staged sysinit fragment that
reads `/sys/board`, checks `/sys/cmdline` for the virtio mainfs argument, and
runs `/usr/bin/sysinfo`.

## Known Limitations

- No C source is removed by this RC.
- The RC covers QSOE/L QEMU runtime behavior, not a full hardware release.
- Only the portable taskman syscfg TLV helper is selected through Rust. The LQ
  private runtime syscfg builder remains C.

## Review Notes

- Unsafe review: no new Rust unsafe code in this RC target wiring.
- Data or on-disk format migration: none.
- Operator impact: use `make tm-syscfg-rc-smoke` to validate the Rust default
  RC path and `make tm-syscfg-rc-rollback-smoke` to validate rollback.
