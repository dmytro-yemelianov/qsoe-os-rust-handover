# QSOE `pipe` Second-Service Mini-Spec

Selected: 2026-06-24 01:47 CEST.

`pipe` is the selected second Rust service candidate. It ranked first in
`SERVICE_RANKING.md` because it is small, bounded, useful for shell pipelines,
and shaped like a resource manager without touching storage or console-driver
hardware.

The existing C implementation remains the default and rollback path. A Rust
implementation now exists as an explicit opt-in.

## Current C Component

- Source: `quser/sbin/pipe/main.c`
- Binary: `quser/build/sbin/pipe/pipe.elf`
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

## Rust Opt-In Implementation

The Rust version is split into:

- `qsoe-pipe`: dependency-free `no_std` ring and state machine with host tests.
- `qsoe-pipe-rs`: QSOE userland staticlib that owns only channel registration,
  request decode/reply, and calls into `qsoe-pipe`.

Unsafe code stays in the service boundary and FFI calls. The ring/state crate
does not allocate and reports explicit reply outcomes for immediate replies,
parked callers, and parked-caller wakeups.

The implemented opt-in targets are:

```sh
make rust-pipe-link-smoke
QSOE_RUST_PIPE=1 make pipe-artifact
make rust-pipe-smoke
```

`make rust-pipe-smoke` replaces only `/sbin/pipe` in a temporary LQ boot CPIO,
starts it from a temporary sysinit fragment, reaches `login:`, and requires:

- `[pipe-rs] /dev/pipe registered`
- `rust-pipe-smoke: started /sbin/pipe`

## C Baseline Smoke

Run the C registration smoke:

```sh
make pipe-smoke
```

The smoke creates a temporary `/usr/conf/sysinit/*.sh` fragment, rebuilds the
normal QSOE/L image, boots it, starts the current C `/sbin/pipe` after `/usr`
mounts, and requires:

- `[pipe] registered at /dev/pipe`
- `pipe-smoke: started /sbin/pipe`
- the normal `login:` boot milestone

This proves the selected service can start and register cleanly before any Rust
implementation is introduced.

## Later Rust Acceptance

Before selecting Rust `pipe` by default:

- host tests must continue to cover ring wrap, EOF, wrong-end errors, parked
  reader, parked writer, close wakeups, and pool exhaustion
- the Rust binary must continue to link and pass
  `scripts/audit-elf.sh --strict-qsoe-user`
- the opt-in boot smoke must continue to replace only `/sbin/pipe` and preserve
  login
- once libc/taskman pipe creation is fully wired, add a data-path smoke for a
  simple shell pipeline or a dedicated pipe helper; tracked by #90
