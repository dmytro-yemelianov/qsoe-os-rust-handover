# `qsoe-tm-sysmap` Historical Rust-Default Release Candidate

Captured: 2026-06-30 CEST.

This note records the former `tm_sysmap` Rust-default release-candidate path.
The C rollback window is now closed; see
`TASK_MANAGER_SYSMAP_RETIREMENT.md` for the retirement record.

## Rust Migration: `tm_sysmap`

Status: historical Rust-default RC, later retired.
Release or build: `qsoe-tm-sysmap-rc1`, introduced by the
`codex/tm-sysmap-rust-default-rc` branch.

### Language Change

- Previous default implementation: C `lq/taskman/sys/sysmap.c`
- RC default implementation: Rust `qsoe-tm-sysmap`
- Rust artifact or crate: `rust/crates/qsoe-tm-sysmap`
- Taskman Rust link model: selected providers are packaged through the shared
  `build/rust/tm-providers/libqsoe_tm_providers.a` archive
- C implementation status during the RC: rollback-only through
  `QSOE_RUST_TM_SYSMAP=0`
- Current C implementation status: removed from LQ taskman by component
  override

The RC changed only the selected provider for the LQ sysmap page builder. FDT
parsing, syscfg construction, process tables, child VSpace mapping, capability
ownership, memory management, IRQ setup, and seL4 object code remained C.

## Former Rollback

The former rollback selector was:

```sh
QSOE_RUST_TM_SYSMAP=0
```

The former rollback smoke was:

```sh
make tm-sysmap-rc-rollback-smoke
```

Both now fail fast after C provider retirement.

## Test Evidence

- C model fixture: historical `make check-tm-sysmap-model`
- Rust host tests: `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-sysmap --features host-tests`
- Artifact and membership audit: `make tm-sysmap-evidence`
- Existing Rust-selected runtime smoke: `make tm-sysmap-runtime-smoke`
- Rust-default RC smoke: `make tm-sysmap-rc-smoke`
- Former C rollback RC smoke: `make tm-sysmap-rc-rollback-smoke`

The RC smoke built LQ taskman in the default selector mode and verified that C
`sys/sysmap.o` was absent from the link plan. The rollback smoke repeated the
link-plan check with `QSOE_RUST_TM_SYSMAP=0`, where C `sys/sysmap.o` was
present. Both modes booted QSOE/L with a staged sysinit fragment that ran
`/usr/bin/sysinfo` and checked the QEMU timebase, PLIC, and PCI output from the
mapped child `PSYS` page.

## Known Limitations

- The RC covered QSOE/L QEMU runtime behavior, not a full hardware release.
- Only the LQ sysmap page builder was selected through Rust. FDT/syscfg
  discovery, process lifecycle, child VSpace mapping, IPC, and seL4 object code
  remained C.

## Review Notes

- Unsafe review: no new Rust unsafe code was added in the RC target wiring.
- Data or on-disk format migration: none.
- Operator impact after retirement: use `make tm-sysmap-rc-smoke` to validate
  the Rust-only path; no rollback target remains.
