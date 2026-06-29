# QSOE OS Rust Migration Handover

This repository is the GitHub handover workspace for migrating selected QSOE
OS components from C to Rust. The migration is intentionally incremental:
existing C components stay the default and rollback path until each Rust
candidate has tests, ELF audit evidence, boot evidence, and a release-candidate
window with C rollback still available.

## Why This Exists

This project exists to make QSOE's C-to-Rust migration measurable, reversible,
and reviewable instead of a rewrite for its own sake. Rust is used where it can
remove concrete C failure modes such as memory unsafety, unchecked parsing,
state-machine drift, and fragile error-path handling. C remains in place for
paths where Rust would add more risk than value today, especially early boot,
loader, process-spawn, capability-management, and kernel-adjacent code.

The repo also exists as an evidence log. Every Rust candidate should have a
clear selector, C rollback path, host tests, boot or runtime smoke evidence,
and documentation before it can become a default. No C implementation is
removed just because a Rust version exists.

## Current Status

- Rust-default release-candidate paths exist for `qrvfs-tree`, `mkfs-qrv-rs`,
  `slogger-rs`, `devb-virtio-rs`, `pipe-rs`, `test_msgpass-rs`, and
  `qsoe-tm-procfs`.
- Rust opt-in task-manager providers exist for `qsoe-tm-cpio`,
  `qsoe-tm-cred`, `qsoe-tm-pseudodev`, `qsoe-tm-script`, and
  `qsoe-tm-sysfs`; C remains the normal taskman default for each.
- Rust `mkfs-qrv-rs` has fixture, production-root, target-initialization,
  bounded triple-indirect allocator, live virtio `/usr`, and C rollback smoke
  evidence.
- No tracked C component is retired. C is still the rollback path everywhere.
- The next host qrvfs gate is the #26 retirement checklist and a separate
  removal PR before any C writer is removed.

Detailed planning lives under `docs/rust-migration/`. Start with:

- [Rust migration roadmap dashboard](https://dmytro-yemelianov.github.io/qsoe-os-rust-handover/)
  for the issue-backed roadmap dashboard published through GitHub Pages.
- [GitHub Issues filtered by `roadmap`](https://github.com/dmytro-yemelianov/qsoe-os-rust-handover/issues?q=label%3Aroadmap)
  for the canonical migration tracker.
- `docs/rust-migration/HANDOVER.md` for the current repository state and next
  work.
- `docs/rust-migration/INVENTORY.md` for the OS-wide C inventory and remaining
  translation buckets.
- `docs/rust-migration/STATUS.md` for component-by-component migration state.
- `docs/rust-migration/RETIREMENT.md` for the gate before any C code removal.
- `docs/rust-migration/DEVLOG.md` for command history and validation evidence.

## Current Progress

| Area | Current state | Evidence / next gate |
| --- | --- | --- |
| Baseline and tooling | Complete | Linux/container workflows, boot smokes, artifact audit, C indexing, clangd, clang-tidy wrapper, pinned Rust toolchain, cargo-deny, fuzz smoke, and coverage targets are in place. |
| Rust ABI/FFI foundation | Complete | `qsoe-abi`, `qsoe-ffi`, and `qsoe-ressrv` compile for the QSOE target with layout tests and reviewed unsafe boundaries. |
| Host qrvfs tools | Rust default RC for inspector and writer | Rust fixture checks compare against the existing C host tool; `make tree` selects Rust `qrvfs-tree` by default, and `make treeqrvfs-rc-rollback-smoke` preserves C rollback. `make mkfs-qrv-rc-live-smoke` selects Rust `mkfs-qrv-rs` by default for the writer RC, and `make mkfs-qrv-rc-rollback-smoke` restores C. Fixture, production-root, stale-target, bounded triple-indirect allocator, and live `/usr` smokes cover the writer path. Production C remains rollback. |
| `slogger` service | Rust default RC | `slogger-rs` links, boots, registers `/dev/slog`, has C-selected plus Rust-selected `/dev/slog` readback smokes, and has accepted #95 local-equivalent RC evidence for `slogger-rc-*` targets with C rollback. Next gate: #26 retirement checklist and a separate removal PR before any C retirement decision. |
| `devb-virtio` block driver | Rust default RC | Rust MMIO/virtqueue model, host queue tests, opt-in boot/file-read smokes, and `make virtio-rc-file-smoke` plus `make virtio-rc-rollback-smoke` cover the Rust-default file-read RC path with C rollback. Next gate: #26 retirement checklist and a separate removal PR before any C retirement decision. |
| Shared parsers | Complete for current scope | CPIO, syscfg/sysmap, and ELF inspection crates exist with host tests and host/guest reuse coverage. |
| `pipe` service | Rust default RC | `qsoe-pipe` host tests pass, `pipe-rs` links and audits, `make rust-pipe-smoke` boots LQ with Rust `/sbin/pipe` registered, `make rust-pipe-data-smoke` proves a libc/taskman `pipe(2)` write/read round trip, and `make pipe-rc-data-smoke` selects Rust by default with `make pipe-rc-rollback-smoke` preserving C rollback. Next gate: #26 retirement checklist and a separate removal PR before any C retirement decision. |
| `test_msgpass` helper | Rust default RC | `test_msgpass-rs` links, can be selected into the qrvfs test image, passes the existing suite `[msgpass]` section through `make rust-test-msgpass-smoke`, and has `make test-msgpass-rc-smoke` plus `make test-msgpass-rc-rollback-smoke` for the Rust-default test-image RC path. Next gate: #26 retirement checklist and a separate removal PR before any C retirement decision. |
| `tm_procfs` task-manager pilot | Rust default RC | `qsoe-tm-procfs` exports the existing C ABI behind `QSOE_RUST_TM_PROCFS=1`; `make tm-procfs-rc-smoke` selects Rust by default for the RC image and `make tm-procfs-rc-rollback-smoke` restores C. Host model tests, Rust host tests, selected NQ/LQ taskman links, `make tm-procfs-evidence`, and `/proc` smokes cover the gate. Next gate: #26 retirement checklist and a separate removal PR before any C retirement decision. |
| `tm_cpio` task-manager provider | Rust opt-in | `qsoe-tm-cpio` exports the existing `tm_cpio.h` ABI behind `QSOE_RUST_TM_CPIO=1`; `make tm-cpio-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies NQ/LQ taskman links with C rollback and Rust-selected archives. Next gate: add boot/runtime coverage for CPIO-backed spawn and file access before any Rust-default RC decision. |
| `tm_cred` task-manager provider | Rust opt-in | `qsoe-tm-cred` exports the existing `tm_cred.h` ABI behind `QSOE_RUST_TM_CRED=1`; `make tm-cred-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies NQ/LQ taskman links with C rollback and Rust-selected archives. Next gate: add a credential-specific runtime smoke before any Rust-default RC decision. |
| `tm_pseudodev` task-manager provider | Rust opt-in | `qsoe-tm-pseudodev` exports the existing LQ `/dev/null` and `/dev/zero` ABI behind `QSOE_RUST_TM_PSEUDODEV=1`; `make tm-pseudodev-evidence` runs Rust host tests, audits the soft-float staticlib, and verifies LQ C-default/Rust-selected taskman links. Next gate: add a focused `/dev/null` and `/dev/zero` runtime smoke before any Rust-default RC decision. |
| `tm_script` task-manager provider | Rust opt-in | `qsoe-tm-script` exports the existing `tm_script.h` ABI behind `QSOE_RUST_TM_SCRIPT=1`; `make tm-script-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies NQ/LQ taskman links with C rollback and Rust-selected archives. Next gate: add script-spawn runtime coverage before any Rust-default RC decision. |
| `tm_sysfs` task-manager provider | Rust opt-in | `qsoe-tm-sysfs` exports the existing `tm_sysfs.h` ABI behind `QSOE_RUST_TM_SYSFS=1`; `make tm-sysfs-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies NQ/LQ taskman links with C rollback and Rust-selected archives. Next gate: add a focused `/sys` runtime smoke before any Rust-default RC decision. |
| Kernel Rust | Deferred | Current decision rejects near-term Rust in `nq` kernel code; only fixture/audit candidates are documented. |
| C retirement | Blocked by policy | No C implementation is currently approved for removal; #26's checklist and a separate removal PR are still required for every component. |

## Current Follow-ups

- The draft PR stack through #89 was merged into `main` on 2026-06-24. The
  former #42 runner blocker, #60 CodeRabbit blocker, and bottom-up merge tracker
  are closed as #82, #83, and #84.
- Host `qrvfs-tree` now has a Rust-default release-candidate path for the
  read-only `make tree` inspector with explicit C rollback. `mkfs-qrv` remains
  C, and C retirement stays blocked until #26's checklist and a separate
  removal PR.
- `mkfs-qrv-rs` now has Rust-default writer RC and C rollback smokes. Keep
  `host_tools/mkfs-qrv.c` until #26's checklist and a separate removal PR.
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
- `tm_cpio`, `tm_cred`, `tm_pseudodev`, `tm_script`, and `tm_sysfs` are Rust
  opt-in task-manager providers only. Keep them C-default until runtime smoke
  coverage and a separate RC decision exist.

## Useful Commands

```sh
make rust-fast
make rust-quality
make rust-abi
make treeqrvfs-rc-smoke
make treeqrvfs-rc-rollback-smoke
make check-qrvfs-rust-writer-fixture
make check-qrvfs-rust-writer-production-root
make rust-mkfs-qrv-live-smoke
make mkfs-qrv-rc-live-smoke
make mkfs-qrv-rc-rollback-smoke
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
make check-tm-cpio-model
make rust-tm-cpio-provider
make tm-cpio-evidence
make check-tm-cred-model
make rust-tm-cred-provider
make tm-cred-evidence
make check-tm-procfs-model
make rust-tm-procfs-provider
make tm-procfs-evidence
make rust-tm-pseudodev-provider
make tm-pseudodev-evidence
make check-tm-script-model
make rust-tm-script-provider
make tm-script-evidence
make check-tm-sysfs-model
make rust-tm-sysfs-provider
make tm-sysfs-evidence
make tm-procfs-rc-smoke
make tm-procfs-rc-rollback-smoke
QSOE_RUST_TM_PROCFS=1 make procfs-smoke
make procfs-smoke
```

Generated artifacts stay out of git under `build/`, `rust/target/`, and
`sel4-bootstrap/`.
