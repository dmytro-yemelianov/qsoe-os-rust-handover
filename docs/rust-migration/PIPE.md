# QSOE `pipe` Second-Service Mini-Spec

Selected: 2026-06-24 01:47 CEST.

`pipe` is the selected second Rust service candidate. It ranked first in
`SERVICE_RANKING.md` because it is small, bounded, useful for shell pipelines,
and shaped like a resource manager without touching storage or console-driver
hardware.

The Rust implementation is now the default and only staged service. The former C
implementation is retained in this document as historical behavior context.

## Historical C Component

- Former source: `quser/sbin/pipe/main.c`
- Former binary: `quser/build/sbin/pipe/pipe.elf`
- Registered path: `/dev/pipe`
- Scope: anonymous pipes only
- Out of scope: named FIFOs, multi-waiter queues, changing taskman pipe minting,
  changing libc `pipe(2)` semantics

Startup behavior:

1. Print `[pipe] alive, pid=N`.
2. Create one QNX-shape channel with `ChannelCreate(0)`.
3. Register `/dev/pipe` with the path manager.
4. Print `[pipe] registered at /dev/pipe on chid=N`.
5. Call `procmgr_detach(0)`.
6. Enter a `MsgReceive`/`MsgReply` loop.

## Protocol

Taskman owns pipe creation. A future caller of libc `pipe(fd)` sends
`TM_REQ_PIPE_CREATE` to taskman. Taskman resolves `/dev/pipe`, allocates a pipe
ID, and mints two badged send caps onto the pipe manager channel:

```text
badge = (pipe_id << 1) | direction
direction: 0 = read end, 1 = write end
```

The pipe service receives normal I/O requests on those badged connections:

- `TM_REQ_IO_READ`: valid only on the read end.
- `TM_REQ_IO_WRITE`: valid only on the write end.
- `TM_REQ_CLOSE`: decrements the matching end count and recycles the slot when
  both ends close.

Unknown request labels return `ENOSYS`. Wrong-end reads or writes return
`EBADF`. Writes after all readers close return `EPIPE`.

## State Model

The C implementation has a fixed pool of 16 pipe slots. Each slot contains:

- one 4 KiB ring buffer with one byte reserved to distinguish full from empty
- one reader count and one writer count
- at most one parked reader rcvid
- at most one parked writer rcvid and remaining write payload state

Blocking behavior follows the current QNX-style saved-rcvid pattern:

- read on non-empty pipe drains bytes immediately
- read on empty pipe with live writers parks the reader
- read on empty pipe with no writers returns EOF
- write with a parked reader replies to that reader directly
- write with remaining data fills the ring and may park the writer
- close wakes parked opposite-end callers where required

## Rust Implementation

The Rust version is split into:

- `qsoe-pipe`: dependency-free `no_std` ring and state machine with host tests.
- `qsoe-pipe-rs`: QSOE userland staticlib that owns only channel registration,
  request decode/reply, and calls into `qsoe-pipe`.

Unsafe code stays in the service boundary and FFI calls. The ring/state crate
does not allocate and reports explicit reply outcomes for immediate replies,
parked callers, and parked-caller wakeups.

The current Rust-only targets are:

```sh
make rust-pipe-link-smoke
make pipe-artifact
make rust-pipe-smoke
make rust-pipe-data-smoke
```

`make pipe-artifact` always stages Rust `pipe-rs` to
`build/rust/selected/sbin/pipe.elf`. `QSOE_RUST_PIPE=0` is rejected because the
C service is retired.

`make rust-pipe-smoke` boots an LQ image with Rust `/sbin/pipe`, starts it from
a temporary sysinit fragment, reaches `login:`, and requires:

- `[pipe-rs] /dev/pipe registered`
- `rust-pipe-smoke: started /sbin/pipe`

`make rust-pipe-data-smoke` uses the same opt-in replacement pattern and also
stages `/usr/bin/test_pipe_data` into a temporary qrvfs image. That helper calls
normal libc `pipe(2)`, writes to the write end, reads the same payload from the
read end, closes the writer, and verifies EOF on the read end.

## Rust-Only Image Path

`pipe-rs` moved through a Rust-default release-candidate path and is now retired
from C:

```sh
make pipe-rc-data-smoke
```

The compatibility target validates the Rust-only `/sbin/pipe` data path.
`QSOE_PIPE_RC_ROLLBACK=1` is rejected because the rollback window is closed. See
`PIPE_RC.md` for historical RC evidence and `PIPE_RETIREMENT.md` for the
retirement record.

## Historical C Baseline Smoke

The former C registration smoke was:

```sh
make pipe-smoke
```

The current `make pipe-smoke` target has been updated to validate the Rust
service in the normal QSOE/L image. The former C smoke created a temporary
`/usr/conf/sysinit/*.sh` fragment, rebuilt QSOE/L, booted it, started the C
`/sbin/pipe` after `/usr` mounted, and required:

- `[pipe] registered at /dev/pipe`
- `pipe-smoke: started /sbin/pipe`
- the normal `login:` boot milestone

That historical smoke proved the selected C service could start and register
cleanly before Rust implementation work began.

## Current Acceptance

For the retired Rust-only path:

- host tests must continue to cover ring wrap, EOF, wrong-end errors, parked
  reader, parked writer, close wakeups, and pool exhaustion
- the Rust binary must continue to link and pass
  `scripts/audit-elf.sh --strict-qsoe-user`
- the boot smoke must continue to start `/sbin/pipe` and preserve login
- keep `make rust-pipe-data-smoke` passing on the hosted runner; trusted
  `main` CI run `28102250069` accepted the #96 data-path evidence
- keep `make pipe-rc-data-smoke` passing for the Rust-only service path
