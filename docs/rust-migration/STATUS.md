# Rust Migration Status

Captured: 2026-06-24 02:38 CEST.

This table tracks components whose current C implementation may be replaced by
Rust. Link-smoke binaries, examples, and reusable parser crates are not listed
unless they replace a C component in an image or test path.

State meanings:

- `C default`: normal builds and images use the C implementation.
- `Rust opt-in`: a narrow build flag or smoke path can select Rust while C
  remains the rollback path.
- `Rust default`: release-candidate or normal images select Rust by default.
- `Retired`: the C implementation is removed from normal source or image paths.

| Component | C default | Rust opt-in | Rust default | Retired | Evidence / selector | Next gate |
| --- | --- | --- | --- | --- | --- | --- |
| Host `treeqrvfs` inspector | Yes: `host_tools/treeqrvfs.c` remains the fixture oracle. | Yes: Rust `qrvfs-tree` runs through `make check-qrvfs-rust-fixture`, but not as a default replacement. | No | No | qrvfs behavior spec, Rust parser tests, and C/Rust fixture comparison. | Promote only after host-tool replacement policy and CLI default selection are written. |
| `slogger` | Yes: `/sbin/slogger` still uses C normally. | Yes: `QSOE_RUST_SLOGGER=1 make slogger-artifact`; `make rust-slogger-boot-smoke`. | No | No | Behavior spec, Rust ring tests, link smoke, ELF audit, and boot-log comparison. | Add `/dev/slog` readback smoke, then Rust-default RC. |
| `devb-virtio` | Yes: `/sbin/devb-virtio` still uses C normally. | Yes: `QSOE_RUST_VIRTIO=1 make virtio-artifact`; `make rust-virtio-file-smoke`. | No | No | Behavior spec, MMIO and queue tests, link smoke, ELF audit, boot smoke, and file-read smoke. | Rust-default RC with C rollback. |
| `pipe` | Yes: `/sbin/pipe` is the selected future service but remains C. | No: Rust implementation and selector do not exist yet. | No | No | C mini-spec and `make pipe-smoke`. | Implement `qsoe-pipe` and an opt-in Rust service artifact. |
| `test_msgpass` | Yes: `/usr/bin/test_msgpass` remains the C helper in test images. | No: Rust helper and selector do not exist yet. | No | No | Helper contract and selection rationale. | Implement Rust helper selector and rerun the suite `[msgpass]` case. |
| `tm_procfs` | Yes: `libtaskman/src/tm_procfs.c` remains selected. | No: boundary reserves future `QSOE_RUST_TM_PROCFS=1`. | No | No | Task-manager inventory, C/Rust boundary review, and C `make procfs-smoke` coverage. | Add host tests, Rust provider, artifact audit, boot smoke, and procfs smoke. |

No tracked component has reached `Rust default` or `Retired` status. C remains
the rollback path for every current migration candidate.
