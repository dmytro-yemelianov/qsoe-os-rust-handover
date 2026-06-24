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
| `slogger` service | Rust opt-in | `slogger-rs` links, boots, registers `/dev/slog`, and has C-selected plus Rust-selected `/dev/slog` readback smokes. Next gate: Rust-default release candidate with C rollback. |
| `devb-virtio` block driver | Rust opt-in | Rust MMIO/virtqueue model, host queue tests, opt-in boot smoke, and file-read smoke exist. Next gate: Rust-default release candidate with C rollback. |
| Shared parsers | Complete for current scope | CPIO, syscfg/sysmap, and ELF inspection crates exist with host tests and host/guest reuse coverage. |
| `pipe` service | Rust opt-in | `qsoe-pipe` host tests pass, `pipe-rs` links and audits, and `make rust-pipe-smoke` boots LQ with Rust `/sbin/pipe` registered. Next gate: data-path smoke once libc/taskman pipe creation is wired; tracked by #90. |
| `test_msgpass` helper | Rust opt-in | `test_msgpass-rs` links, can be selected into the qrvfs test image, and passes the existing suite `[msgpass]` section through `make rust-test-msgpass-smoke`. C remains the default helper. |
| `tm_procfs` task-manager pilot | Selected, not implemented in Rust | Boundary and C smoke are documented. Next gate: host tests for the portable procfs model before any task-manager wiring. |
| Kernel Rust | Deferred | Current decision rejects near-term Rust in `nq` kernel code; only fixture/audit candidates are documented. |
| C retirement | Blocked by policy | No C implementation is approved for removal until at least one component ships through a Rust-default release candidate with C rollback. |

## Current Follow-ups

- The draft PR stack through #89 was merged into `main` on 2026-06-24. The
  former #42 runner blocker, #60 CodeRabbit blocker, and bottom-up merge tracker
  are closed as #82, #83, and #84.
- Add a Rust pipe data-path smoke before any Rust-default pipe decision.
  Tracked by #90.
- Keep C retirement blocked until at least one component ships through a
  Rust-default release candidate with C rollback. Tracked by #26.

## Useful Commands

```sh
make rust-fast
make rust-quality
make rust-abi
make slog-readback-smoke
make rust-slog-readback-smoke
make rust-virtio-file-smoke
make rust-test-msgpass-smoke
make pipe-smoke
make rust-pipe-smoke
make procfs-smoke
```

Generated artifacts stay out of git under `build/`, `rust/target/`, and
`sel4-bootstrap/`.
