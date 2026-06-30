# `qsoe-tm-script` Rust-Default Release Candidate

Captured: 2026-06-30 CEST.

This historical note records the `tm_script` Rust-default release-candidate
path and the C rollback drill that existed before C provider retirement.
Current Rust-only retirement status lives in `TASK_MANAGER_SCRIPT_RETIREMENT.md`.

## Rust Migration: `tm_script`

Status: Historical Rust default RC; C provider is now retired.
Release or build: `qsoe-tm-script-rc1`, introduced by the
`codex/tm-script-rust-default-rc` branch.

### Language Change

- Previous default implementation: C `libtaskman/src/script.c`
- New RC default implementation: Rust `qsoe-tm-script`
- Rust artifact or crate: `rust/crates/qsoe-tm-script`
- Taskman Rust link model: selected providers are packaged through the shared
  `build/rust/tm-providers/libqsoe_tm_providers.a` archive
- C implementation status during this historical RC: rollback-only through
  `QSOE_RUST_TM_SCRIPT=0`
- User-visible behavior changes: none expected for shebang parsing, direct
  script spawn, interpreter path handling, or optional argument parsing

The RC changes only the selected provider for the portable task-manager
shebang parser. Interpreter loading, argv construction, CPIO lookup, ELF
loading, relocation, process tables, and seL4 invocation code remain C.

## Rollback

- Rollback available during this historical RC: yes
- Rollback selector: `QSOE_RUST_TM_SCRIPT=0`
- Rollback command:

```sh
make tm-script-rc-rollback-smoke
```

Default RC smoke:

```sh
make tm-script-rc-smoke
```

Rollback window: closed by `TASK_MANAGER_SCRIPT_RETIREMENT.md`.

## Test Evidence

- C model fixture: `make check-tm-script-model`
- Rust host tests: `cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-script --features host-tests`
- Artifact and membership audit: `make tm-script-evidence`
- Existing Rust-selected runtime smoke: `make tm-script-runtime-smoke`
- Rust-default RC smoke: `make tm-script-rc-smoke`
- C rollback RC smoke: `make tm-script-rc-rollback-smoke`

The RC smoke builds NQ and LQ taskman in the default selector mode and verifies
that C `script.o` is absent from `libtaskman.a`. The rollback smoke repeats
the archive-membership check with `QSOE_RUST_TM_SCRIPT=0`, where C `script.o`
must be present. Both modes boot QSOE/L with a staged executable
`/usr/bin/tm_script_probe` shell script and run it directly from sysinit, which
forces taskman spawn to parse the shebang before loading `/bin/sh`.

## Known Limitations

- No C source was removed by this RC; the later retirement removed
  `libtaskman/src/script.c`.
- The RC covers QSOE/L QEMU runtime behavior, not a full hardware release.
- Only the portable shebang parser is selected through Rust. Task-manager
  spawn orchestration, CPIO file access, loader, process lifecycle, and seL4
  object code remain C.

## Review Notes

- Unsafe review: no new Rust unsafe code in this RC target wiring.
- Data or on-disk format migration: none.
- Operator impact at the time: `make tm-script-rc-smoke` validated the Rust
  default RC path and `make tm-script-rc-rollback-smoke` validated rollback.
  Current rollback selectors fail fast after retirement.
