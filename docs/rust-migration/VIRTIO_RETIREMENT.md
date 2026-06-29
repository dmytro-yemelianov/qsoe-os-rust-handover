# `devb-virtio` C Driver Retirement

Captured: 2026-06-29 19:49 CEST.

This note records retirement of the C `quser/dev/virtio` block driver after
the Rust-default `devb-virtio-rs` release-candidate path in `VIRTIO_RC.md`.
The stable image path remains `/sbin/devb-virtio`, but the implementation is
now Rust-only in tracked NQ/LQ images.

## Scope

- Removed C implementation: `quser/dev/virtio/{Makefile,main.c,virtio_blk.c,virtio_blk.h}`
- Rust implementation: `rust/bins/devb-virtio-rs`
- Selected artifact: `build/rust/selected/sbin/devb-virtio.elf`
- Image path: `/sbin/devb-virtio`
- Component override: `patches/components/quser-retire-virtio-c.patch`
- NQ/LQ packaging overrides:
  - `patches/components/nq-makefile-rust-virtio-retired.patch`
  - `patches/components/lq-makefile-rust-virtio-retired.patch`

Fresh NQ/LQ CPIO builds now call the top-level `make virtio-artifact` selector
and pass `SBIN_VIRTIO_ELF` into `quser`, matching the already-retired
`slogger` and `pipe` image-artifact pattern.

## Rollback Status

C rollback is closed for this component.

- `QSOE_RUST_VIRTIO=0 make virtio-artifact` fails fast with status 2.
- `QSOE_VIRTIO_RC_ROLLBACK=1 scripts/virtio-rc-file-smoke.sh` fails fast with
  status 2.
- `make virtio-rc-file-smoke` remains as a Rust-only compatibility smoke for
  the previous RC command name.
- `make virtio-rc-rollback-smoke` is removed from the top-level Makefile.

## Evidence

Retirement validation for this PR:

- `./scripts/apply-component-overrides.sh`
- `patch -d nq --reverse --silent --dry-run -p1 < patches/components/nq-makefile-rust-virtio-retired.patch`
- `patch -d lq --reverse --silent --dry-run -p1 < patches/components/lq-makefile-rust-virtio-retired.patch`
- `patch -d quser --reverse --silent --dry-run -p1 < patches/components/quser-retire-virtio-c.patch`
- `bash -n scripts/apply-component-overrides.sh scripts/select-virtio-artifact.sh scripts/rust-virtio-boot-smoke.sh scripts/rust-virtio-file-smoke.sh scripts/virtio-rc-file-smoke.sh scripts/boot-smoke.sh scripts/rust-mkfs-qrv-live-smoke.sh scripts/mkfs-qrv-rc-live-smoke.sh scripts/rust-slogger-boot-smoke.sh scripts/rust-pipe-smoke.sh scripts/rust-pipe-data-smoke.sh scripts/capture-elf-baseline.sh`
- `QSOE_RUST_VIRTIO=0 make virtio-artifact`
- `QSOE_VIRTIO_RC_ROLLBACK=1 scripts/virtio-rc-file-smoke.sh`
- `make rust-virtio-link-smoke`
- `make check-elf-reloc-fixture`
- `make virtio-artifact`
- `make slogger-artifact pipe-artifact virtio-artifact && make -C quser cpio`
- CPIO inspection confirms `/sbin/devb-virtio` contains
  `[devb-virtio-rs] /dev/vblk0 ready`
- `scripts/c-index.sh files`

Runtime and repository gates for this PR:

- `make rust-check`
- `make rust-virtio-file-smoke`
- `make virtio-rc-file-smoke`
- `make mkfs-qrv-rc-live-smoke`
- `make mkfs-qrv-rc-rollback-smoke`
- `make rust-pipe-data-smoke`
- `make`
- `scripts/boot-smoke.sh -k lq -t 120`
- `make rust-slogger-boot-smoke`
- `make rust-pipe-smoke`
- `git diff --check`

## Operator Impact

Operators should keep using `/sbin/devb-virtio` and existing boot scripts. The
implementation-language change is visible only through the startup marker:

```text
[devb-virtio-rs] /dev/vblk0 ready
```

The external contract is unchanged: the driver publishes `/dev/vblk0`, `fs-qrv`
mounts the raw qrvfs image at `/usr`, and `/usr` file reads continue through
the resource-server block-device path.
