# Host qrvfs C Tool Retirement

Captured: 2026-07-01 CEST.

This note records retirement of the C host qrvfs inspector and writer after the
Rust-default release-candidate windows documented in `TREEQRVFS_RC.md` and
`MKFS_QRV_RC.md`. The stable host-tool commands remain `make tree`,
`make treeqrvfs-rc-smoke`, `make rust-mkfs-qrv-live-smoke`, and
`make mkfs-qrv-rc-live-smoke`, but the selected implementation is now Rust-only
in the tracked build.

## Scope

- Removed C inspector: `host_tools/treeqrvfs.c`
- Removed C writer: `host_tools/mkfs-qrv.c`
- Rust implementation: `rust/crates/qsoe-qrvfs`
- Rust inspector binary: `qrvfs-tree`
- Rust writer binary: `mkfs-qrv-rs`
- Stable inspector artifact: `build/treeqrvfs`
- Stable writer artifact: `build/mkfs-qrv-rs`
- Production qrvfs image path: `build/fsqrv.img`

`fsqrv-image`, NVMe population, virtio image generation, fixture generation,
and host tree inspection now use Rust `mkfs-qrv-rs` and `qrvfs-tree` without a
C fallback.

## Rollback Status

C rollback is closed for this component.

- `QSOE_RUST_TREEQRVFS=0 make tree` fails fast at the top-level Makefile.
- `QSOE_RUST_MKFS_QRV=0 make fsqrv-image` fails fast at the top-level Makefile.
- `TREEQRVFS_RC_ROLLBACK=1 scripts/treeqrvfs-rc-smoke.sh` fails fast with
  status 2.
- `MKFS_QRV_RC_ROLLBACK=1 scripts/mkfs-qrv-rc-live-smoke.sh` fails fast with
  status 2.
- `make treeqrvfs-rc-rollback-smoke` and `make mkfs-qrv-rc-rollback-smoke` are
  removed from the top-level Makefile.

## Evidence

Retirement validation for this PR:

- `bash -n scripts/treeqrvfs-artifact.sh scripts/treeqrvfs-rc-smoke.sh scripts/check-qrvfs-fixture.sh scripts/check-qrvfs-rust-fixture.sh scripts/check-qrvfs-rust-writer-fixture.sh scripts/check-qrvfs-rust-writer-production-root.sh scripts/mkfs-qrv-rs-artifact.sh scripts/rust-mkfs-qrv-live-smoke.sh scripts/mkfs-qrv-rc-live-smoke.sh`
- `make check-qrvfs-fixture`
- `make check-qrvfs-rust-fixture`
- `make treeqrvfs-rc-smoke`
- `make check-qrvfs-rust-writer-fixture`
- `make check-qrvfs-rust-writer-production-root`
- `make rust-mkfs-qrv-live-smoke`
- `make mkfs-qrv-rc-live-smoke`
- `QSOE_RUST_TREEQRVFS=0 make tree`
- `QSOE_RUST_MKFS_QRV=0 make fsqrv-image`
- `TREEQRVFS_RC_ROLLBACK=1 scripts/treeqrvfs-rc-smoke.sh`
- `MKFS_QRV_RC_ROLLBACK=1 scripts/mkfs-qrv-rc-live-smoke.sh`

The live smokes succeed when the boot log contains the guest marker
`rust-virtio-file-smoke: read /usr/conf/passwd ok` and the wrapper prints
`rust-virtio-file-smoke.sh: /usr file read smoke passed`.

## Operator Impact

Operators should keep using the existing host-tool targets. The implementation
language is no longer selectable:

```sh
make tree
make treeqrvfs-rc-smoke
make fsqrv-image
make rust-mkfs-qrv-live-smoke
make mkfs-qrv-rc-live-smoke
```

The qrvfs on-disk format and image paths are unchanged. Recovering the C tools
requires reverting the retirement PR; there is no supported selector or package
that restores them.
