# `devb-virtio-rs` Rust-Default Release Candidate

Captured: 2026-06-28 20:46 CEST.

This note records the `devb-virtio` Rust-default release-candidate path. It
does not retire the C implementation. Normal source builds still preserve the C
driver, and the RC image path keeps a one-command C rollback drill.

## Rust Migration: `devb-virtio`

Status: Rust default RC.
Release or build: `devb-virtio-rs-rc1`, introduced by the
`codex/virtio-rust-default-rc` branch.

### Language Change

- Previous default implementation: C `/sbin/devb-virtio`
- New RC default implementation: Rust `devb-virtio-rs`
- Rust artifact or crate: `rust/bins/devb-virtio-rs`, linked to
  `build/rust/qsoe-devb-virtio-rs.elf`
- C implementation status: rollback-only for the RC image path; still present
  in tree and still used by non-RC normal builds
- User-visible behavior changes: none expected for `/dev/vblk0`, `/usr`, or
  qrvfs readers

Known startup-log difference:

- C prints:
  - `devb-virtio: /dev/vblk0 ready (...)`
- Rust prints:
  - `[devb-virtio-rs] alive`
  - `[devb-virtio-rs] /dev/vblk0 ready`

## Rollback

- Rollback available: yes
- Rollback flag: `QSOE_VIRTIO_RC_ROLLBACK=1`
- Rollback command:

```sh
make virtio-rc-rollback-smoke
```

Default RC file-read smoke:

```sh
make virtio-rc-file-smoke
```

Rollback window: still open until the C retirement gate in `RETIREMENT.md` is
satisfied and a separate removal PR is reviewed.

Rollback limitations: none known for the QSOE/L QEMU file-read smoke path. The
rollback image uses the same C `/sbin/devb-virtio` artifact as the pre-RC path.

## Test Evidence

- Host tests: `make rust-quality`
- Artifact audit: `make rust-virtio-link-smoke`
- Existing opt-in file-read smoke: `make rust-virtio-file-smoke`
- Rust-default RC file-read smoke: `make virtio-rc-file-smoke`
- C rollback file-read smoke: `make virtio-rc-rollback-smoke`

The file-read smoke boots QSOE/L, starts `/sbin/devb-virtio`, mounts the qrvfs
image from `/dev/vblk0` at `/usr`, and verifies `/bin/cat` can read
`/usr/conf/passwd` through the selected block driver before reaching `login:`.

## Known Limitations

- No C source is removed by this RC.
- The RC covers QSOE/L QEMU file-read behavior, not a full hardware release.
- Writes remain disabled through the resource-server surface, matching the C
  driver behavior.
- C retirement remains blocked by #26 until the retirement checklist is
  reviewed; this RC evidence does not remove or disable the C implementation.

## Review Notes

- Unsafe review: no new Rust unsafe code in this RC target wiring.
- Data or on-disk format migration: none.
- Operator impact: use `make virtio-rc-file-smoke` to validate the Rust
  default RC path and `make virtio-rc-rollback-smoke` to validate rollback.
