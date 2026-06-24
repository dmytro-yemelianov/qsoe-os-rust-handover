# Rust Migration Status

Captured: 2026-06-24 12:21 CEST.

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
| `slogger` | Yes: `/sbin/slogger` still uses C in non-RC normal builds and remains rollback. | Yes: `QSOE_RUST_SLOGGER=1 make slogger-artifact`; `make rust-slogger-boot-smoke`; `make rust-slog-readback-smoke`. | RC: `make slogger-rc-readback-smoke` selects `slogger-rs` by default; `make slogger-rc-rollback-smoke` restores C. | No | Behavior spec, C and Rust-selected `/dev/slog` readback smokes, Rust ring tests, link smoke, ELF audit, boot-log comparison, and `SLOGGER_RC.md`. | Complete an accepted RC window before any C retirement decision. |
| `devb-virtio` | Yes: `/sbin/devb-virtio` still uses C normally. | Yes: `QSOE_RUST_VIRTIO=1 make virtio-artifact`; `make rust-virtio-file-smoke`. | No | No | Behavior spec, MMIO and queue tests, link smoke, ELF audit, boot smoke, and file-read smoke. | Rust-default RC with C rollback. |
| `pipe` | Yes: `/sbin/pipe` remains C in normal images. | Yes: `QSOE_RUST_PIPE=1 make pipe-artifact`; `make rust-pipe-link-smoke`; `make rust-pipe-smoke`; `make rust-pipe-data-smoke`. | No | No | C mini-spec, C smoke, `qsoe-pipe` host tests, selector, link smoke, ELF audit, Rust-selected registration boot smoke, and Rust-selected pipe(2) data-path smoke. | Use a green CI run of `container-rust-pipe-data-smoke` as hosted-runner evidence before considering a Rust-default RC with C rollback. |
| `test_msgpass` | Yes: `/usr/bin/test_msgpass` remains the C helper in normal test images. | Yes: `QSOE_RUST_TEST_MSGPASS=1 make test-msgpass-artifact`; `make rust-test-msgpass-link-smoke`; `make rust-test-msgpass-smoke`. | No | No | Helper contract, runtime-buffer Rust helper, selector, link smoke, and Rust-selected suite `[msgpass]` smoke. | Repeat the Rust-selected smoke in CI/hosted runner and decide whether this helper should become the default test-image artifact. |
| `tm_procfs` | Yes: `libtaskman/src/tm_procfs.c` remains selected. | No: boundary reserves future `QSOE_RUST_TM_PROCFS=1`. | No | No | Task-manager inventory, C/Rust boundary review, and C `make procfs-smoke` coverage. | Add host tests, Rust provider, artifact audit, boot smoke, and procfs smoke. |

Only `slogger` has a Rust-default release-candidate path. No tracked component
has reached `Retired` status. C remains the rollback path for every current
migration candidate.
