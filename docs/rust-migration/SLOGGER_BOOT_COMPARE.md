# C vs Rust `slogger` Boot Log Comparison

Compared on 2026-06-23 with QSOE/L under QEMU.

## Inputs

- C log: `build/boot-smoke-lq-c-compare.log`
- Rust log: `build/boot-smoke-lq-20260623-223518.log`

The Rust log came from `make rust-slogger-boot-smoke`. The C log came from
rebuilding the default C `modpkg.cpio` and running:

```sh
scripts/boot-smoke.sh -k lq -t 180 -o build/boot-smoke-lq-c-compare.log
```

## Shared Milestones

Both logs reached the same boot milestones:

```text
spawning /sbin/init (pid=2)...
dispatcher ready
[init] starting slogger...
[init] starting devb-virtio...
devb-virtio: /dev/vblk0 ready (16 MiB)
fs-qrv: mounted qrvfs at /usr (dev=/dev/vblk0)
login:
```

## `slogger` Startup Lines

C `slogger`:

```text
[slogger] alive, pid=3
[slogger] /dev/slog registered (chid=2, ring=65536 bytes)
[slogger] entering MsgReceive loop on chid=2
```

Rust `slogger-rs`:

```text
[slogger-rs] alive
[slogger-rs] /dev/slog registered
[slogger-rs] entering MsgReceive loop
```

## Reviewed Differences

- Rust uses `qsoe_dbg_write` for startup messages, so it currently omits the C
  service's `pid`, `chid`, and ring-size details.
- The `/dev/slog` registration point is unchanged.
- Virtio disk startup, qrvfs mount, and login timing milestones remained
  observable in both boots.
- The Rust path is still opt-in through `make rust-slogger-boot-smoke`; the C
  service remains the default build path.

## Follow-Up

- Decide whether `slogger-rs` should grow tiny integer formatting for pid/chid
  parity before broader boot-image use.
- Keep `/dev/slog` readback smoke in the gate before replacing the default C
  service.
