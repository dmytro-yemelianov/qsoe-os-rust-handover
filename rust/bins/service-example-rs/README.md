# qsoe-service-example-rs

`qsoe-service-example-rs` is the minimal Rust direct resource-server example.
It is intentionally small and is not selected for any boot image by default.

The service registers `/dev/rust-example`, signals `procmgr_detach(0)`, and
then enters the shared `DirectServer` receive loop from `qsoe-ressrv`.

The request/reply policy is:

- `IO_CONNECT`, `IO_DUP`, and `TM_REQ_CLOSE` reply with status `0`.
- `TM_REQ_IO_WRITE` replies with the accepted inline payload byte count.
- `TM_REQ_IO_READ` replies with `qsoe-rs\n`, capped to the requested count.
- unknown requests reply with `ENOSYS`.

Run the host-side checks with:

```sh
make rust-quality
```

Build and link the example through the QSOE userland CRT/libc path with:

```sh
make rust-service-example-link-smoke
```

The container equivalent is:

```sh
make container-rust-service-example-link-smoke
```
