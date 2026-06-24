# QSOE Rust Bindings

This document records the first Rust ABI and resource-server binding layer.
The scope is deliberately narrow: compile-time shape checks and raw FFI first,
then small wrappers that can support a `slogger-rs` pilot.

## Crates

### `qsoe-abi`

`qsoe-abi` is `no_std` and contains C-compatible public ABI shapes:

- QSOE scalar aliases such as `PidT`, `ModeT`, `OffT`, `SizeT`, and `SsizeT`.
- IPC constants such as `TASKMAN_COID`, `TASKMAN_CHID`, `QSOE_MI_PULSE`, and
  `QSOE_RCVID_SAVED`.
- `#[repr(C)]` message structs:
  - `QsoeMsgInfo`
  - `QsoeCredInfo`
  - `QsoeClientInfo`
  - `QsoePulse`

Layout tests assert the current RV64 C ABI sizes and alignments.

### `qsoe-ffi`

`qsoe-ffi` is `no_std` and exposes raw `extern "C"` bindings for actual
linkable QSOE libc symbols:

- channel and connection calls.
- `MsgSend` / `MsgReceive` / `MsgReply` / pulse calls.
- `_r` message and connection variants where available.
- `procmgr_detach`.
- path-manager registration and resolve.
- debug write.
- `qsoe_mmap` and `qsoe_alloc_phys`.

`qsoe_errno` is not bound because it is a C macro over the current thread
block, not a linkable symbol. Rust code should prefer `_r` forms or C helper
APIs that already return negative errno.

### `qsoe-ressrv`

`qsoe-ressrv` is `no_std` and mirrors `quser/ressrv/include/ressrv.h`:

- `Attr`
- `Open`
- `Handle`
- `ProviderVtable`
- `Provider`
- `Server`
- opaque `Call`

It also exposes raw C lifecycle functions and thin wrappers for:

- provider initialization.
- provider listen.
- dispatch loop entry.

For direct resource servers that do not use the C dispatch framework yet, such
as the current C `slogger`, it also exposes a safe direct-service surface:

- `Channel` owns `ChannelCreate` / `ChannelDestroy`.
- `DirectService::register` creates a channel and registers a C string path
  with the path manager.
- `DirectService::detach_ready` wraps `procmgr_detach`.
- `receive_bytes` and `receive_request` wrap `MsgReceive` and distinguish
  messages from pulses.
- `ReceivedMessage` consumes the receive token when sending status-only,
  word-sized, or byte-slice replies through `MsgReply`.
- `IoRequest` and `IoReply` model the fixed 40-byte request header,
  32-byte pure reply header, and `TM_IO_MAX` inline payload shape used by
  `slogger`.
- `DirectServer` and `DirectRequestHandler` provide the shared register,
  daemon-ready, receive-loop, pulse, and receive-error path for direct services.
  `slogger-rs` and `qsoe-service-example-rs` both use this bootstrap.
  The example service documents and tests a minimal request/reply policy for
  lifecycle, read, write, and unsupported operations.
- `DirectServer::dispatch_received` is the host-testable receive-state step
  used by the infinite `run` loop; tests cover message, pulse, and receive
  error dispatch without requiring QEMU.
- `ReplyStatus` models direct `MsgReply` labels: `0`/`EOK` on success and a
  positive QSOE errno on failure.
- `MethodStatus` models the C resource-server method convention: non-negative
  success values, `-errno` failures, or the existing `QSOE_DEFER` sentinel.
  It only converts into `ReplyStatus` for the `-errno` case, preserving the
  current QSOE ABI instead of adding a Rust-specific status layer.

Layout tests assert the current RV64 C ABI sizes and alignments.

### `qsoe-slogger`

`qsoe-slogger` is `no_std` and contains the pure ring-buffer logic for the
future `slogger-rs` binary. It preserves the implemented 64 KiB byte-ring
behavior and uses the current 24-byte LP64 `qsoe_slog_event_t` header size when
sizing events.

Host tests cover append, drain, wraparound, exact-full behavior, drop-oldest
eviction, oversized record rejection, incomplete event reads, read caps, and
corrupt head-event clamping during eviction.

## Current Boundary

The bindings are suitable for compiling Rust code that can describe QSOE
resource-server objects and link against the C framework later.

They are not yet a full safe resource-server framework. In particular:

- callback implementors still receive raw provider/handle pointers.
- method callbacks are `unsafe extern "C"` functions.
- buffer validity remains the caller/framework contract.
- no Rust allocator contract is assumed.
- `qsoe_errno` access is intentionally absent.
- direct services still own their request parsing and policy decisions.

## Validation

Run:

```sh
make rust-check
```

This includes:

- formatting.
- workspace `cargo check`.
- clippy with warnings denied.
- layout tests for `qsoe-abi` and `qsoe-ressrv`.

Run the RISC-V compile-only path:

```sh
QSOE_RUST_COMPILE=1 scripts/rust-check.sh
```
