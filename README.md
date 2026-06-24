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
| `devb-virtio` block driver | Rust opt-in | Rust MMIO/virtqueue model, host queue tests, opt-in boot smoke, and file-read smoke exist. Next gate: Rust-default release candidate with C rollback. |
| Shared parsers | Complete for current scope | CPIO, syscfg/sysmap, and ELF inspection crates exist with host tests and host/guest reuse coverage. |
| `pipe` service | Rust opt-in | `qsoe-pipe` host tests pass, `pipe-rs` links and audits, `make rust-pipe-smoke` boots LQ with Rust `/sbin/pipe` registered, and `make rust-pipe-data-smoke` proves a libc/taskman `pipe(2)` write/read round trip. Next gate: green CI evidence for the data-path smoke before a Rust-default release candidate with C rollback. |
| `test_msgpass` helper | Rust opt-in | `test_msgpass-rs` links, can be selected into the qrvfs test image, and passes the existing suite `[msgpass]` section through `make rust-test-msgpass-smoke`. Next gate: green trusted CI evidence through #97 before any Rust-default test-image decision. |
| `tm_procfs` task-manager pilot | Rust opt-in | `qsoe-tm-procfs` exports the existing C ABI behind `QSOE_RUST_TM_PROCFS=1`; C remains default/rollback. Host model tests, Rust host tests, selected NQ/LQ taskman links, `make tm-procfs-evidence`, and `QSOE_RUST_TM_PROCFS=1 make procfs-smoke` cover the gate. Next gate: green #103 trusted CI evidence before any default-selection decision. |
| Kernel Rust | Deferred | Current decision rejects near-term Rust in `nq` kernel code; only fixture/audit candidates are documented. |
| C retirement | Blocked by policy | No C implementation is approved for removal until at least one component ships through a Rust-default release candidate with C rollback. |

## Current Follow-ups

- The draft PR stack through #89 was merged into `main` on 2026-06-24. The
  former #42 runner blocker, #60 CodeRabbit blocker, and bottom-up merge tracker
  are closed as #82, #83, and #84.
- Use the Rust pipe data-path smoke evidence before any Rust-default pipe
  release-candidate decision. CI now includes `container-rust-pipe-data-smoke`
  on the configured `[self-hosted, X64]` runner for trusted PRs and pushes.
- `slogger-rs` now has a Rust-default release-candidate path with explicit C
  rollback. #95's local-equivalent RC evidence window is accepted; keep C
  retirement blocked until #26's checklist and a separate removal PR.
- Track the Rust `test_msgpass` trusted-CI evidence gate in #97 before any
  default test-image decision.
- `tm_procfs` now has a Rust opt-in provider behind `QSOE_RUST_TM_PROCFS=1`.
  CI now includes `container-tm-procfs-evidence` on the configured
  `[self-hosted, X64]` runner for trusted PRs and pushes. Keep C as the default
  while #103 collects the default-selection evidence.

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
make rust-test-msgpass-smoke
make pipe-smoke
make rust-pipe-smoke
make rust-pipe-data-smoke
make check-tm-procfs-model
make rust-tm-procfs-provider
make tm-procfs-evidence
QSOE_RUST_TM_PROCFS=1 make procfs-smoke
make procfs-smoke
```

Generated artifacts stay out of git under `build/`, `rust/target/`, and
`sel4-bootstrap/`.
