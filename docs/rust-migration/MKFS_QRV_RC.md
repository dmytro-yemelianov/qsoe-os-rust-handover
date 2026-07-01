# `mkfs-qrv-rs` Rust-Default Release Candidate

Captured: 2026-06-29 09:26 CEST.

Historical note: C `mkfs-qrv` was later retired. The current Rust-only host
qrvfs tool path is documented in `HOST_QRVFS_RETIREMENT.md`.

This note records the host qrvfs image writer Rust-default release-candidate
path. It does not retire the C `mkfs-qrv` writer. The C writer remains present
and is the explicit rollback implementation.

## Rust Migration: Host `mkfs-qrv`

Status: Rust default RC.
Release or build: `mkfs-qrv-rs-rc1`, introduced by the
`codex/mkfs-qrv-rust-default-rc` branch.

Implementation-language change:

- Previous default implementation for the RC target: C `host_tools/mkfs-qrv.c`
- New RC default implementation: Rust `mkfs-qrv-rs`
- Rust artifact or crate: `rust/crates/qsoe-qrvfs`, binary `mkfs-qrv-rs`
- C implementation status: rollback implementation and production fallback
- Inspector status: `qrvfs-tree` already has its own Rust-default RC path

## Scope

Only the qrvfs image writer selected by the RC smoke changes. Normal
`fsqrv-image`, NVMe population, and virtio image generation still default to C
unless `QSOE_RUST_MKFS_QRV=1` or the RC smoke selects Rust.

The RC smoke builds the normal QSOE/L virtio qrvfs image with the selected
writer, boots with the retired Rust-only `devb-virtio-rs` storage path, mounts
`/usr`, and reads `/usr/conf/passwd` from the generated image.

## Rollback

Rollback command:

```sh
make mkfs-qrv-rc-rollback-smoke
```

Equivalent selector:

```sh
QSOE_RUST_MKFS_QRV=0 make fsqrv-image
```

Rollback limitations: none known for the RC smoke path. The rollback artifact
is compiled from the same C `host_tools/mkfs-qrv.c` implementation as the
pre-RC path.

## Evidence

Required local evidence:

- Rust host quality and writer unit tests: `make rust-quality`
- Rust writer fixture with C inspector oracle: `make check-qrvfs-rust-writer-fixture`
- Production-root comparison: `make check-qrvfs-rust-writer-production-root`
- Rust-selected live image smoke: `make rust-mkfs-qrv-live-smoke`
- Rust-default RC live smoke: `make mkfs-qrv-rc-live-smoke`
- C rollback live smoke: `make mkfs-qrv-rc-rollback-smoke`

The live smokes succeed when the boot log contains the guest marker
`rust-virtio-file-smoke: read /usr/conf/passwd ok` and the wrapper prints
`rust-virtio-file-smoke.sh: /usr file read smoke passed`.

## Known Limitations

- This RC does not retire `host_tools/mkfs-qrv.c`; removal still requires the
  retirement checklist and a separate C-removal PR.
- The C writer remains the rollback implementation for qrvfs image creation.
- The RC smoke now uses Rust-only `devb-virtio-rs` because the C storage driver
  rollback is retired. The mkfs-qrv writer rollback remains independent through
  `QSOE_RUST_MKFS_QRV=0`.

## Operator Impact

Use `make mkfs-qrv-rc-live-smoke` to validate the Rust default writer RC path
and `make mkfs-qrv-rc-rollback-smoke` to validate rollback. Use
`QSOE_RUST_MKFS_QRV=0 make fsqrv-image` when the C writer is required
explicitly.
