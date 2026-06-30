# `qsoe-tm-sysmap` Rust-Default Release Candidate

Captured: 2026-06-30 CEST.

This note records the `tm_sysmap` Rust-default release-candidate path with C
rollback still available.

## Rust Migration: `tm_sysmap`

Status: Rust default RC.
Release or build: `qsoe-tm-sysmap-rc1`, introduced by the
`codex/tm-sysmap-rust-default-rc` branch.

### Language Change

- Previous default implementation: C `lq/taskman/sys/sysmap.c`
- New RC default implementation: Rust `qsoe-tm-sysmap`
- Rust artifact or crate: `rust/crates/qsoe-tm-sysmap`
- Taskman Rust link model: selected providers are packaged through the shared
  `build/rust/tm-providers/libqsoe_tm_providers.a` archive
- C implementation status during this RC: rollback-only through
  `QSOE_RUST_TM_SYSMAP=0`
- User-visible behavior changes: none expected for the `PSYS` page layout,
  timebase, PLIC, PCI ECAM, or DesignWare fields consumed by children

The RC changes only the selected provider for the LQ sysmap page builder. FDT
parsing, syscfg construction, process tables, child VSpace mapping, capability
ownership, memory management, IRQ setup, and seL4 object code remain C.

## Rollback

- Rollback available during RC: yes
- Rollback selector: `QSOE_RUST_TM_SYSMAP=0`
- Rollback command:

```sh
make tm-sysmap-rc-rollback-smoke
```

Default RC smoke:

```sh
make tm-sysmap-rc-smoke
```

Rollback window: open. Do not remove `lq/taskman/sys/sysmap.c` until #26's C
retirement checklist is satisfied and a separate removal PR records fresh
evidence.

## Test Evidence

- C model fixture: `make check-tm-sysmap-model`
- Rust host tests: `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-sysmap --features host-tests`
- Artifact and membership audit: `make tm-sysmap-evidence`
- Existing Rust-selected runtime smoke: `make tm-sysmap-runtime-smoke`
- Rust-default RC smoke: `make tm-sysmap-rc-smoke`
- C rollback RC smoke: `make tm-sysmap-rc-rollback-smoke`

The RC smoke builds LQ taskman in the default selector mode and verifies that
C `sys/sysmap.o` is absent from the link plan. The rollback smoke repeats the
link-plan check with `QSOE_RUST_TM_SYSMAP=0`, where C `sys/sysmap.o` must be
present. Both modes boot QSOE/L with a staged sysinit fragment that runs
`/usr/bin/sysinfo` and checks the QEMU timebase, PLIC, and PCI output from the
mapped child `PSYS` page.

## Known Limitations

- No C source is removed by this RC.
- The RC covers QSOE/L QEMU runtime behavior, not a full hardware release.
- Only the LQ sysmap page builder is selected through Rust. FDT/syscfg
  discovery, process lifecycle, child VSpace mapping, IPC, and seL4 object code
  remain C.

## Review Notes

- Unsafe review: no new Rust unsafe code in this RC target wiring.
- Data or on-disk format migration: none.
- Operator impact: use `make tm-sysmap-rc-smoke` to validate the Rust default
  RC path and `make tm-sysmap-rc-rollback-smoke` to validate rollback.
