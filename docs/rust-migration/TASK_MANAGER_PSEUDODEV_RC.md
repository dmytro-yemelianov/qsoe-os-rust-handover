# Task Manager Pseudo-device Historical Rust-Default RC

Captured: 2026-06-30 CEST.

This page records the Rust-default release-candidate path and C rollback drill
that existed before C provider retirement. Current builds are Rust-only; see
`TASK_MANAGER_PSEUDODEV_RETIREMENT.md` for the retired state.

During the RC window, normal umbrella and applied LQ taskman builds selected
Rust with:

```text
QSOE_RUST_TM_PSEUDODEV=1
```

The C implementation remained available as rollback during the RC window:

```text
QSOE_RUST_TM_PSEUDODEV=0
TM_PSEUDODEV_RC_ROLLBACK=1
```

## Scope

The RC covers the LQ taskman pseudo-device handlers for `/dev/null` and
`/dev/zero`: write discard, EOF reads for `/dev/null`, zero-filled reads for
`/dev/zero`, and stat records for both character devices.

It does not replace path lookup, path IO dispatch, file-descriptor state,
connection lookup, IPC request decoding, console IO, or any seL4 object
manipulation.

## Evidence

The focused evidence gate is:

```sh
make tm-pseudodev-evidence
```

It runs Rust host tests, audits the Rust provider archive, and verifies LQ
taskman link plans and taskman ELFs for both Rust-default and C rollback.

The live RC gates during the RC window were:

```sh
make tm-pseudodev-rc-smoke
make tm-pseudodev-rc-rollback-smoke
```

Both verify the LQ taskman dry-run link plan, then boot QSOE/L through the
runtime pseudo-device smoke. The Rust-default path verifies C `sys/devnull.o`
and `sys/devzero.o` are absent from the link plan and the shared Rust provider
exports all `tm_devnull_*` and `tm_devzero_*` ABI symbols. The C rollback path
verifies those C objects remain present.

## Retirement

C is now retired. `lq/taskman/sys/devnull.c` and
`lq/taskman/sys/devzero.c` are removed by the tracked component override,
`QSOE_RUST_TM_PSEUDODEV=0` fails fast, and
`make tm-pseudodev-rc-rollback-smoke` is no longer a current target. The
current Rust-only evidence lives in `TASK_MANAGER_PSEUDODEV.md` and
`TASK_MANAGER_PSEUDODEV_RETIREMENT.md`.
