# QSOE `slogger` Behavior Specification

Captured: 2026-06-23 20:40 EEST.

This document records the current C `slogger` behavior that `slogger-rs` must
preserve unless a later decision explicitly changes it.

Primary sources:

- `quser/sbin/slogger/main.c`
- `libc/qsoe/slog.c`
- `libc/include/sys/slog.h`
- `libc/include/qsoe/tm_msgs.h`
- `quser/bin/sloginfo/main.c`
- `quser/test/suite/slog_test.c`

## Role

`/sbin/slogger` is a single user-space daemon that owns the system log ring and
registers `/dev/slog` with the QSOE path manager.

Clients normally do not speak to it directly. They use libc `slogf`,
`vslogf`, `slogb`, or `slogi`, which lazy-open `/dev/slog` and write one event
per call. Consumers use `read()` on `/dev/slog`; `sloginfo` is the current human
readable consumer.

## Startup Contract

On startup, `slogger`:

1. Prints `[slogger] alive, pid=N`.
2. Creates a channel with `ChannelCreate(0)`.
3. Registers `/dev/slog` with `qsoe_pathmgr_register`.
4. Prints `[slogger] /dev/slog registered (chid=N, ring=65536 bytes)`.
5. Calls `procmgr_detach(0)`.
6. Prints `[slogger] entering MsgReceive loop on chid=N`.
7. Enters an infinite `MsgReceive` loop.

Failure behavior:

- `ChannelCreate` failure prints a message and exits with status `1`.
- path-manager registration failure prints the errno and exits with status `1`.
- `procmgr_detach` failure prints a message but does not stop the service.
- `MsgReceive` returning `-1` is ignored and the loop continues.
- Pulses are ignored.

The dispatch loop intentionally avoids per-message `printf()` calls to avoid
resource-manager self-deadlock through console back-traffic.

## Ring Buffer

The implemented ring is `64 KiB`:

```c
#define SLOG_RING_BYTES (64 * 1024)
```

The ring uses:

- `g_head`: next byte to read.
- `g_tail`: next byte to write.
- `g_used`: bytes currently occupied.

Events are stored back-to-back as:

```text
qsoe_slog_event_t header + payload bytes
```

Eviction policy:

- Appending a record larger than the ring returns without storing it.
- If a new record does not fit, whole records are evicted from the head until
  there is room.
- Eviction sizes records by reading `qsoe_slog_event_t.paylen`.
- If an event header claims a size larger than `g_used`, eviction clamps the
  event size to `g_used`.

Read policy:

- Reads drain from the head.
- Reads return whole events only.
- If the next whole event does not fit in the caller's cap, reading stops.
- If an event header claims a size larger than `g_used`, reading stops.
- Empty or incomplete rings return zero event bytes rather than blocking.

Historical documentation mismatch:

- `libc/include/sys/slog.h` previously said the ring was `256 KiB`.
- The implementation and observed boot log use `64 KiB`.
- The Rust port preserves the implemented `64 KiB` behavior unless a separate
  decision changes the ring size. The component header lives under the ignored
  `libc/` release tree in this handover repo, so the source-comment correction
  remains an upstream component follow-up.

## Wire Protocol

Requests arrive with an opcode in word `0`, followed by scalar words and an
inline payload. The relevant opcode aliases are:

```c
#define TM_REQ_CLOSE    _IO_CLOSE
#define TM_REQ_IO_WRITE _IO_WRITE
#define TM_REQ_IO_READ  _IO_READ
#define TM_REQ_FSTAT    _IO_FSTAT
```

The request shape used by `slogger` is:

```c
typedef struct {
    unsigned long type;
    unsigned long count;
    unsigned long _rsv[3];
    unsigned char data[TM_IO_MAX];
} slog_req_t;
```

`TM_IO_MAX` is `896` bytes.

Replies are pure payload; status is the `MsgReply` status argument. The common
reply payload shape is:

```c
typedef struct {
    unsigned long count;
    unsigned long _rsv[3];
    unsigned char data[TM_IO_MAX];
} slog_reply_t;
```

The reply header is `4 * sizeof(unsigned long)`, currently `32` bytes on
QSOE's LP64 ABI.

## Opcode Behavior

### `TM_REQ_IO_WRITE`

- Reads `req.count` bytes from `req.data`.
- Appends those bytes to the ring.
- Replies `EOK`.
- Reply payload is one `unsigned long` containing the requested byte count.

Current behavior does not validate that the payload is a well-formed slog
event. It stores bytes as supplied.

### `TM_REQ_IO_READ`

- Uses `req.count` as the requested byte cap.
- If `req.count` is zero, uses default `928`, then caps through
  `slog_send_read_reply`.
- Caps the effective read size to `TM_IO_MAX`.
- Drains whole events into `s_reply.data`.
- Sets `s_reply.count` to the number of event bytes returned.
- Replies `EOK` with `SLOG_REPLY_HDR + count` bytes.

### `TM_REQ_FSTAT`

Replies `EOK` with a `tm_stat_t` in `s_reply.data`:

- `st_dev = 7`
- `st_ino = 1`
- `st_mode = TM_S_IFCHR | 0666`
- `st_nlink = 1`
- `st_rdev = (10 << 8) | 100`
- `st_blksize = 256`

`s_reply.count` is `sizeof(tm_stat_t)`.

### `_IO_CONNECT`, `_IO_DUP`, `TM_REQ_CLOSE`

Replies `EOK` with no payload. `slogger` keeps no per-connection state.

### Unknown Opcode

Replies `ENOSYS` with no payload.

## Client Event Format

libc builds one event per `slogf`, `vslogf`, `slogb`, or `slogi` call.

The wire event header is `qsoe_slog_event_t`:

```c
typedef struct {
    uint16_t magic;
    uint8_t  severity;
    uint8_t  flags;
    uint32_t code;
    uint64_t time_us;
    uint16_t pid;
    uint16_t paylen;
} qsoe_slog_event_t;
```

The current LP64 layout is 24 bytes: 20 bytes of fields plus 4 bytes of tail
padding from the `uint64_t` alignment. The Rust port must use `sizeof`-matched
layout, not the stale 16-byte wording that previously appeared in
`libc/include/sys/slog.h`.

Header fields:

- `magic = QSOE_SLOG_MAGIC` (`0x534c`, `SL`).
- `severity` is masked to three bits.
- `flags` includes `QSOE_SLOG_FLAG_TEXT` for text payloads.
- `code` uses `_SLOG_SETCODE(major, minor)`.
- `time_us` is derived from `ClockTime` divided by `1000`.
- `pid` is `qsoe_self_pid` truncated to `uint16_t`.
- `paylen` is payload length.

Payload constraints:

- `QSOE_SLOG_MAX_PAYLOAD` is `240`.
- One event write is at most `24 + 240 = 264` bytes on the current LP64 ABI.
- `vslogf` uses a minimal formatter supporting `%s`, `%d`, `%u`, `%x`, `%p`,
  `%c`, `%%`, and width such as `%08x`.
- `slogb` rejects negative payload sizes and sizes above `240` with `EINVAL`.
- If `/dev/slog` cannot be opened, libc logging calls drop the event and return
  success. This permits early boot callers before `slogger` is registered.

## Consumer Behavior

`sloginfo`:

- Opens `/dev/slog` read-only.
- Reads one `928` byte batch.
- Prints `(slog ring is empty)` when read returns zero bytes.
- Walks events back-to-back.
- Stops on bad magic or incomplete trailing event.
- Prints text events as:

```text
[time_us us]  SEV  major.minor  pid=N  text
```

Binary events print as `<N bytes binary>`.

## Existing Smoke Coverage

`quser/test/suite/slog_test.c` calls:

- `slogf(_SLOGC_TEST, _SLOG_INFO, ...)`
- `slogf(_SLOGC_TEST, _SLOG_WARNING, ...)`
- `slogf(_SLOGC_TEST, _SLOG_DEBUG1, ...)`

It checks return values from `slogf`.

`scripts/slog-readback-smoke.py` boots QSOE/L without the virtio disk so init
falls into the cpio rescue shell after starting `slogger` and `pci-server`.
`pci-server` writes known `slogf` entries during startup. The smoke runs
`/bin/sloginfo` from the rescue shell and verifies that a `pci-server:` entry is
observable through `/dev/slog`.

The same smoke can prepare and boot an opt-in image whose `/sbin/slogger`
artifact is `slogger-rs`:

```sh
make rust-slog-readback-smoke
```

This target keeps the C `slogger` as the default image path while proving that
the Rust-selected service can register `/dev/slog`, store boot-time client log
events, and return them through `sloginfo`.

## Rust Port Acceptance

Before `slogger-rs` is linked into an image:

- Ring-buffer host tests cover append, drain, wraparound, drop-oldest eviction,
  exact-full behavior, oversized append, empty read, incomplete event guard,
  corrupt head-event eviction, and read cap behavior. This is implemented in
  `rust/crates/qsoe-slogger`.
- Wire structs preserve LP64 request and reply layout.
- Startup messages either match the C strings or are intentionally documented
  for boot-log comparison.
- `/dev/slog` registration remains at the same path.
- `_IO_CONNECT`, `_IO_DUP`, and close remain state-free `EOK` replies.
- FSTAT values match the C implementation.
- Unknown opcodes reply `ENOSYS`.
- `make rust-slogger-link-smoke` links `qsoe-slogger-rs` through the same QSOE
  `crt0.o` and `libc.so` userland path as the minimal Rust smoke.
- The artifact passes `scripts/audit-elf.sh --strict-qsoe-user`.
- C `slogger` remains the default until Rust boot smoke, Rust readback smoke,
  and the Rust-default release-candidate gate pass.

## Open Follow-Ups

- Correct the stale `libc/include/sys/slog.h` comments in the component source
  repository.
