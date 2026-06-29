# `qsoe-tm-cpio` Rust-Default Release Candidate

Captured: 2026-06-29 CEST.

This note records the `tm_cpio` Rust-default release-candidate path with C
rollback still available.

## Rust Migration: `tm_cpio`

Status: Rust default RC.
Release or build: `qsoe-tm-cpio-rc1`, introduced by the
`codex/tm-cpio-rust-default-rc` branch.

### Language Change

- Previous default implementation: C `libtaskman/src/cpio.c`
- New RC default implementation: Rust `qsoe-tm-cpio`
- Rust artifact or crate: `rust/crates/qsoe-tm-cpio`
- Taskman Rust link model: selected providers are packaged through the shared
  `build/rust/tm-providers/libqsoe_tm_providers.a` archive
- C implementation status during this RC: rollback-only through
  `QSOE_RUST_TM_CPIO=0`
- User-visible behavior changes: none expected for boot CPIO lookup, symlink
  resolution, directory iteration, file reads, or symlink-backed spawn

The RC changes only the selected provider for the portable task-manager CPIO
archive model. CPIO-backed file descriptor state, path dispatch, spawn, ELF
loading, relocation, process tables, and seL4 invocation code remain C.

## Rollback

- Rollback available during RC: yes
- Rollback selector: `QSOE_RUST_TM_CPIO=0`
- Rollback command:

```sh
make tm-cpio-rc-rollback-smoke
```

Default RC smoke:

```sh
make tm-cpio-rc-smoke
```

Rollback window: open. Do not remove `libtaskman/src/cpio.c` until #26's C
retirement checklist is satisfied and a separate removal PR records fresh
evidence.

## Test Evidence

- C model fixture: `make check-tm-cpio-model`
- Rust host tests: `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-cpio --features host-tests`
- Artifact and membership audit: `make tm-cpio-evidence`
- Existing Rust-selected runtime smoke: `make tm-cpio-runtime-smoke`
- Rust-default RC smoke: `make tm-cpio-rc-smoke`
- C rollback RC smoke: `make tm-cpio-rc-rollback-smoke`

The RC smoke builds NQ and LQ taskman in the default selector mode and verifies
that C `cpio.o` is absent from `libtaskman.a`. The rollback smoke repeats the
archive-membership check with `QSOE_RUST_TM_CPIO=0`, where C `cpio.o` must be
present. Both modes boot QSOE/L through the CPIO symlink listing,
`/etc/passwd` symlink read, direct `/sbin/init` boot-CPIO read, and `/bin/sh`
symlink spawn probes.

## Known Limitations

- No C source is removed by this RC.
- The RC covers QSOE/L QEMU runtime behavior, not a full hardware release.
- Only the portable archive model is selected through Rust. Task-manager
  process lifecycle, CPIO file-descriptor state, path-manager registration,
  loader, and seL4 object code remain C.

## Review Notes

- Unsafe review: no new Rust unsafe code in this RC target wiring.
- Data or on-disk format migration: none.
- Operator impact: use `make tm-cpio-rc-smoke` to validate the Rust default RC
  path and `make tm-cpio-rc-rollback-smoke` to validate rollback.
