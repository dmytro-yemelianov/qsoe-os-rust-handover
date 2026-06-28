# QSOE OS Rust Migration Handover

This repository is the GitHub handover workspace for migrating selected QSOE
OS components from C to Rust. The migration is intentionally incremental:
existing C components stay the default and rollback path until each Rust
candidate has tests, ELF audit evidence, boot evidence, and a release-candidate
window with C rollback still available.

Detailed planning lives under `docs/rust-migration/`. Start with:

- `docs/rust-migration/HANDOVER.md` for the current repository state and next
  work.
- `docs/rust-migration/STATUS.md` for component-by-component migration state.
- `docs/rust-migration/RETIREMENT.md` for the gate before any C code removal.
- `docs/rust-migration/DEVLOG.md` for command history and validation evidence.

## Current Progress

| Area | Current state | Evidence / next gate |
| --- | --- | --- |
| Baseline and tooling | Complete | Linux/container workflows, boot smokes, artifact audit, C indexing, clangd, clang-tidy wrapper, pinned Rust toolchain, cargo-deny, fuzz smoke, and coverage targets are in place. |
| Rust ABI/FFI foundation | Complete | `qsoe-abi`, `qsoe-ffi`, and `qsoe-ressrv` compile for the QSOE target with layout tests and reviewed unsafe boundaries. |
| Host qrvfs parser | Rust opt-in | Rust fixture checks compare against the existing C host tool; C remains the fixture oracle. |
| `slogger` service | Rust default RC | `slogger-rs` links, boots, registers `/dev/slog`, has C-selected plus Rust-selected `/dev/slog` readback smokes, and has accepted #95 local-equivalent RC evidence for `slogger-rc-*` targets with C rollback. Next gate: #26 retirement checklist and a separate removal PR before any C retirement decision. |
| `devb-virtio` block driver | Rust default RC | Rust MMIO/virtqueue model, host queue tests, opt-in boot/file-read smokes, and `make virtio-rc-file-smoke` plus `make virtio-rc-rollback-smoke` cover the Rust-default file-read RC path with C rollback. Next gate: #26 retirement checklist and a separate removal PR before any C retirement decision. |
| Shared parsers | Complete for current scope | CPIO, syscfg/sysmap, and ELF inspection crates exist with host tests and host/guest reuse coverage. |
| `pipe` service | Rust default RC | `qsoe-pipe` host tests pass, `pipe-rs` links and audits, `make rust-pipe-smoke` boots LQ with Rust `/sbin/pipe` registered, `make rust-pipe-data-smoke` proves a libc/taskman `pipe(2)` write/read round trip, and `make pipe-rc-data-smoke` selects Rust by default with `make pipe-rc-rollback-smoke` preserving C rollback. Next gate: #26 retirement checklist and a separate removal PR before any C retirement decision. |
| `test_msgpass` helper | Rust default RC | `test_msgpass-rs` links, can be selected into the qrvfs test image, passes the existing suite `[msgpass]` section through `make rust-test-msgpass-smoke`, and has `make test-msgpass-rc-smoke` plus `make test-msgpass-rc-rollback-smoke` for the Rust-default test-image RC path. Next gate: #26 retirement checklist and a separate removal PR before any C retirement decision. |
| `tm_procfs` task-manager pilot | Rust default RC | `qsoe-tm-procfs` exports the existing C ABI behind `QSOE_RUST_TM_PROCFS=1`; `make tm-procfs-rc-smoke` selects Rust by default for the RC image and `make tm-procfs-rc-rollback-smoke` restores C. Host model tests, Rust host tests, selected NQ/LQ taskman links, `make tm-procfs-evidence`, and `/proc` smokes cover the gate. Next gate: #26 retirement checklist and a separate removal PR before any C retirement decision. |
| Kernel Rust | Deferred | Current decision rejects near-term Rust in `nq` kernel code; only fixture/audit candidates are documented. |
| C retirement | Blocked by policy | No C implementation is currently approved for removal; #26's checklist and a separate removal PR are still required for every component. |

## Current Follow-ups

- The draft PR stack through #89 was merged into `main` on 2026-06-24. The
  former #42 runner blocker, #60 CodeRabbit blocker, and bottom-up merge tracker
  are closed as #82, #83, and #84.
- `pipe-rs` now has a Rust-default release-candidate path with explicit C
  rollback. Keep C retirement blocked until #26's checklist and a separate
  removal PR.
- `slogger-rs` now has a Rust-default release-candidate path with explicit C
  rollback. #95's local-equivalent RC evidence window is accepted; keep C
  retirement blocked until #26's checklist and a separate removal PR.
- `test_msgpass-rs` now has a Rust-default test-image release-candidate path
  with explicit C rollback. Keep C retirement blocked until #26's checklist and
  a separate removal PR.
- `devb-virtio-rs` now has a Rust-default release-candidate path with explicit
  C rollback through the `/usr` file-read smoke. Keep C retirement blocked
  until #26's checklist and a separate removal PR.
- `tm_procfs` now has a Rust-default release-candidate path with explicit C
  rollback through the `/proc` smoke. Keep C retirement blocked until #26's
  checklist and a separate removal PR.

## Useful Commands

```sh
make rust-fast
make rust-quality
make rust-abi
make slog-readback-smoke
make rust-slog-readback-smoke
make slogger-rc-readback-smoke
make slogger-rc-rollback-smoke
make rust-virtio-file-smoke
make virtio-rc-file-smoke
make virtio-rc-rollback-smoke
make rust-test-msgpass-smoke
make pipe-smoke
make rust-pipe-smoke
make rust-pipe-data-smoke
make pipe-rc-data-smoke
make pipe-rc-rollback-smoke
make check-tm-procfs-model
make rust-tm-procfs-provider
make tm-procfs-evidence
make tm-procfs-rc-smoke
make tm-procfs-rc-rollback-smoke
QSOE_RUST_TM_PROCFS=1 make procfs-smoke
make procfs-smoke
```

Generated artifacts stay out of git under `build/`, `rust/target/`, and
`sel4-bootstrap/`.
