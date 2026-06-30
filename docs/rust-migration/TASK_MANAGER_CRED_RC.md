# Task Manager Credential Rust-Default RC

Captured: 2026-06-30 CEST.

`tm_cred` is in a Rust-default release-candidate window. Normal umbrella,
standalone `libtaskman`, and applied NQ/LQ taskman builds select
`QSOE_RUST_TM_CRED=1` by default. The C provider is not retired:
`QSOE_RUST_TM_CRED=0` remains the rollback path and keeps
`libtaskman/src/cred.c` linked as `cred.o`.

## Selector Contract

```text
QSOE_RUST_TM_CRED=1      Rust `qsoe-tm-cred` selected; `cred.o` absent
QSOE_RUST_TM_CRED=0      C rollback selected; `cred.o` present
TM_CRED_RC_ROLLBACK=1    shorthand for the rollback smoke
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

This RC is not C retirement approval. `libtaskman/src/cred.c` remains tracked
and must stay buildable until the RC accumulates trusted CI evidence, the global
retirement checklist is satisfied, and a separate removal PR explicitly retires
the C provider.
