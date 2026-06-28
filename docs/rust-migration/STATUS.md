# Rust Migration Status

Captured: 2026-06-28 21:17 CEST.

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
| Host `treeqrvfs` inspector | Yes: `host_tools/treeqrvfs.c` remains the fixture oracle and rollback implementation. | Yes: Rust `qrvfs-tree` runs through `make check-qrvfs-rust-fixture`. | RC: `make tree` selects Rust `qrvfs-tree` by default through `build/treeqrvfs`; `make treeqrvfs-rc-rollback-smoke` restores C. | No | qrvfs behavior spec, Rust parser tests, C/Rust fixture comparison, selected artifact smoke, and `TREEQRVFS_RC.md`. | Keep C rollback until #26's retirement checklist and a separate removal PR are satisfied. |
| `slogger` | Yes: `/sbin/slogger` still uses C in non-RC normal builds and remains rollback. | Yes: `QSOE_RUST_SLOGGER=1 make slogger-artifact`; `make rust-slogger-boot-smoke`; `make rust-slog-readback-smoke`. | RC: `make slogger-rc-readback-smoke` selects `slogger-rs` by default; `make slogger-rc-rollback-smoke` restores C. | No | Behavior spec, C and Rust-selected `/dev/slog` readback smokes, Rust ring tests, link smoke, ELF audit, boot-log comparison, `SLOGGER_RC.md`, and accepted #95 local-equivalent RC evidence. | Keep C rollback until #26's retirement checklist and a separate removal PR are satisfied. |
| `devb-virtio` | Yes: `/sbin/devb-virtio` still uses C in non-RC normal builds and remains rollback. | Yes: `QSOE_RUST_VIRTIO=1 make virtio-artifact`; `make rust-virtio-boot-smoke`; `make rust-virtio-file-smoke`. | RC: `make virtio-rc-file-smoke` selects `devb-virtio-rs` by default; `make virtio-rc-rollback-smoke` restores C. | No | Behavior spec, MMIO and queue tests, link smoke, ELF audit, Rust-selected boot and file-read smokes, and `VIRTIO_RC.md`. | Keep C rollback until #26's retirement checklist and a separate removal PR are satisfied. |
| `pipe` | Yes: `/sbin/pipe` still uses C in non-RC normal builds and remains rollback. | Yes: `QSOE_RUST_PIPE=1 make pipe-artifact`; `make rust-pipe-link-smoke`; `make rust-pipe-smoke`; `make rust-pipe-data-smoke`. | RC: `make pipe-rc-data-smoke` selects `pipe-rs` by default; `make pipe-rc-rollback-smoke` restores C. | No | C mini-spec, C smoke, `qsoe-pipe` host tests, selector, link smoke, ELF audit, Rust-selected registration boot smoke, Rust-selected pipe(2) data-path smoke, trusted `main` CI run `28102250069` for #96, and `PIPE_RC.md`. | Keep C rollback until #26's retirement checklist and a separate removal PR are satisfied. |
| `test_msgpass` | Yes: `/usr/bin/test_msgpass` remains the C helper in non-RC test images and remains rollback. | Yes: `QSOE_RUST_TEST_MSGPASS=1 make test-msgpass-artifact`; `make rust-test-msgpass-link-smoke`; `make rust-test-msgpass-smoke`. | RC: `make test-msgpass-rc-smoke` selects `test_msgpass-rs` by default; `make test-msgpass-rc-rollback-smoke` restores C. | No | Helper contract, runtime-buffer Rust helper, selector, link smoke, Rust-selected suite `[msgpass]` smoke, trusted `main` CI run `28102250069` for #97, and `TEST_MSGPASS_RC.md`. | Keep C rollback until #26's retirement checklist and a separate removal PR are satisfied. |
| `tm_procfs` | Yes: `libtaskman/src/tm_procfs.c` remains selected by default in non-RC normal builds and remains rollback. | Yes: `QSOE_RUST_TM_PROCFS=1` excludes C `tm_procfs.o`, links `qsoe-tm-procfs`, and passes `make procfs-smoke`. | RC: `make tm-procfs-rc-smoke` selects `qsoe-tm-procfs` by default; `make tm-procfs-rc-rollback-smoke` restores C. | No | Task-manager inventory, C/Rust boundary review, C host model tests, Rust host tests, selected NQ/LQ taskman links, soft-float Rust archive audit, C-default/Rust-selected procfs smokes, `make tm-procfs-evidence`, `TASK_MANAGER_PROCFS_RC.md`, and trusted `main` CI run `28102250069` for #103. | Keep C rollback until #26's retirement checklist and a separate removal PR are satisfied. |

Only host `treeqrvfs`, `slogger`, `devb-virtio`, `pipe`, `test_msgpass`, and
`tm_procfs` have Rust-default release-candidate paths. No tracked component has
reached `Retired` status. C remains the rollback path for every current
migration candidate.
