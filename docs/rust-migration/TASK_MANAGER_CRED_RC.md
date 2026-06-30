# Task Manager Credential Rust-Default RC

Captured: 2026-06-30 CEST.

Historical note: `tm_cred` passed through a Rust-default release-candidate
window before C provider retirement. During that RC, normal umbrella,
standalone `libtaskman`, and applied NQ/LQ taskman builds selected
`QSOE_RUST_TM_CRED=1` by default while `QSOE_RUST_TM_CRED=0` preserved C
rollback and kept `libtaskman/src/cred.c` linked as `cred.o`.

## Selector Contract

```text
QSOE_RUST_TM_CRED=1      Rust `qsoe-tm-cred` selected; `cred.o` absent
QSOE_RUST_TM_CRED=0      historical C rollback selected; `cred.o` present
TM_CRED_RC_ROLLBACK=1    historical shorthand for the rollback smoke
```

The RC does not change taskman ownership of process records, IPC decoding,
path validation, or seL4 object lifetime. Only the portable credential, cwd,
and umask policy provider changes implementation language.

## Evidence

```sh
make tm-cred-evidence
make tm-cred-runtime-smoke
make tm-cred-rc-smoke
make tm-cred-rc-rollback-smoke
```

`make tm-cred-evidence` verifies C host behavior, Rust host tests, soft-float
archive properties, exported `tm_cred_*` symbols, and NQ/LQ archive membership
for both selector values.

`make tm-cred-rc-smoke` verifies NQ and LQ `libtaskman.a` omit `cred.o` under
the default Rust selection, then boots QSOE/L and runs `/usr/bin/cred_probe`
from sysinit. The probe covers initial root ids, cwd round-trip, umask exchange,
held-id uid/gid transitions, non-root permission rejection, and spawn
inheritance.

`make tm-cred-rc-rollback-smoke` sets `TM_CRED_RC_ROLLBACK=1`, verifies NQ and
LQ `libtaskman.a` contain `cred.o`, and runs the same live probe with
`TM_CRED_RUNTIME_ALLOW_C=1`.

## Retirement Boundary

This RC was not itself C retirement approval. The separate retirement step is
documented in `TASK_MANAGER_CRED_RETIREMENT.md`; after that step,
`QSOE_RUST_TM_CRED=0`, `TM_CRED_RC_ROLLBACK=1`, and
`make tm-cred-rc-rollback-smoke` are no longer supported.
