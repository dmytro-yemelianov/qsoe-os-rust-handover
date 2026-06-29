# QSOE OS Rust Migration Handover

This repository is the GitHub handover workspace for migrating selected QSOE
OS components from C to Rust. The migration is intentionally incremental:
existing C components stay the default and rollback path until each Rust
candidate has tests, ELF audit evidence, boot evidence, and a release-candidate
window with C rollback still available. A C implementation is retired only in a
separate removal step after that evidence exists.

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
removed just because a Rust version exists; removal requires the retirement
gate in `docs/rust-migration/RETIREMENT.md`.

## Current Status

- Rust-default release-candidate paths exist for `qrvfs-tree` and
  `mkfs-qrv-rs`.
- Retired C implementations: the C `test_msgpass` helper is removed from
  tracked `quser` test-image paths, and the C `/sbin/slogger` and `/sbin/pipe`
  services and C `/sbin/devb-virtio` block driver are removed from tracked
  `quser` service paths. Test images stage Rust `test_msgpass-rs` at
  `/usr/bin/test_msgpass`; normal NQ/LQ images stage Rust `slogger-rs` at
  `/sbin/slogger`, Rust `pipe-rs` at `/sbin/pipe`, and Rust
  `devb-virtio-rs` at `/sbin/devb-virtio`.
- The C `tm_procfs` task-manager provider is retired; taskman now links Rust
  `qsoe-tm-procfs` through the shared provider archive.
- Rust opt-in task-manager providers exist for `qsoe-tm-cpio`,
  `qsoe-tm-cred`, `qsoe-tm-elf`, `qsoe-tm-fdt`, `qsoe-tm-pathmgr`,
  `qsoe-tm-pseudodev`, `qsoe-tm-rsrcdb`, `qsoe-tm-script`,
  `qsoe-tm-syscfg`, `qsoe-tm-sysmap`, and `qsoe-tm-sysfs`. Selected
  task-manager Rust providers are packaged through the shared
  `qsoe-tm-providers` archive so multiple providers can link behind one panic
  handler; C remains the normal taskman default for each.
- Rust `mkfs-qrv-rs` has fixture, production-root, target-initialization,
  bounded triple-indirect allocator, live virtio `/usr`, and C rollback smoke
  evidence.
- Future C retirements still require #26's checklist and a separate removal PR.
  C remains the rollback path for all non-retired migration candidates.

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
| `slogger` service | Retired C service | `slogger-rs` links, boots, registers `/dev/slog`, is staged as `/sbin/slogger` in normal NQ/LQ images, and passes the `/dev/slog` readback smoke through `make slogger-rc-readback-smoke`. The C service source and rollback targets are removed by the retirement PR. |
| `devb-virtio` block driver | Retired C driver | Rust MMIO/virtqueue model, host queue tests, link/boot/file-read smokes, and `make virtio-rc-file-smoke` cover the Rust-only file-read path. Normal NQ/LQ images stage Rust `devb-virtio-rs` as `/sbin/devb-virtio`; the C driver source and rollback target are removed by the retirement PR. |
| Shared parsers | Complete for current scope | CPIO, syscfg/sysmap, and ELF inspection crates exist with host tests and host/guest reuse coverage. |
| `pipe` service | Retired C service | `qsoe-pipe` host tests pass, `pipe-rs` links and audits, `make rust-pipe-smoke` boots LQ with Rust `/sbin/pipe` registered, `make rust-pipe-data-smoke` proves a libc/taskman `pipe(2)` write/read round trip, and `make pipe-rc-data-smoke` validates the Rust-only service path. The C service source and rollback targets are removed by the retirement PR. |
| `test_msgpass` helper | Retired C helper | `test_msgpass-rs` links, is always staged into the qrvfs test image as `/usr/bin/test_msgpass`, and passes the existing suite `[msgpass]` section through `make rust-test-msgpass-smoke` and `make test-msgpass-rc-smoke`. The C helper source and rollback target are removed by the retirement PR. |
| `tm_procfs` task-manager pilot | Retired C provider | `qsoe-tm-procfs` exports the existing C ABI and is mandatory in taskman through the shared `qsoe-tm-providers` archive. `make tm-procfs-evidence` verifies Rust host tests, archive audit, no `tm_procfs.o` in NQ/LQ `libtaskman.a`, retired selector rejection, and the Rust-only `/proc` smoke. |
| Task-manager Rust provider archive | Shared opt-in link unit | `qsoe-tm-providers` packages selected taskman Rust providers into one `libqsoe_tm_providers.a` with one panic handler. `make tm-providers-evidence` selects `tm_cpio` and `tm_procfs` together, audits the soft-float archive and final taskman ELFs, verifies the selected C objects are absent, and runs a dual-provider `/proc` smoke. |
| `tm_cpio` task-manager provider | Rust opt-in | `qsoe-tm-cpio` exports the existing `tm_cpio.h` ABI behind `QSOE_RUST_TM_CPIO=1`; `make tm-cpio-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies NQ/LQ taskman links with C rollback and Rust-selected archives. `make tm-cpio-runtime-smoke` boots LQ with Rust `tm_cpio` selected and covers CPIO symlink readlink, `/etc` symlink file access, direct boot-CPIO file read, and `/bin/sh` symlink spawn. Next gate: separate Rust-default RC decision. |
| `tm_cred` task-manager provider | Rust opt-in | `qsoe-tm-cred` exports the existing `tm_cred.h` ABI behind `QSOE_RUST_TM_CRED=1`; `make tm-cred-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies NQ/LQ taskman links with C rollback and Rust-selected archives. Next gate: add a credential-specific runtime smoke before any Rust-default RC decision. |
| `tm_elf` task-manager provider | Rust opt-in | `qsoe-tm-elf` exports the existing `tm_elf.h` ABI behind `QSOE_RUST_TM_ELF=1`; `make tm-elf-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies NQ/LQ taskman links with C rollback and Rust-selected archives. `make tm-elf-runtime-smoke` boots LQ with Rust `tm_elf` selected and runs a dynamic `/usr/bin/sysinfo` spawn through the C loader path. Next gate: separate Rust-default RC decision. |
| `tm_fdt` task-manager provider | Rust opt-in | `qsoe-tm-fdt` exports the existing LQ `tm_fdt_*` ABI behind `QSOE_RUST_TM_FDT=1`; `make tm-fdt-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies LQ taskman links with C rollback and Rust-selected archives. `make tm-fdt-runtime-smoke` boots LQ with Rust `tm_fdt` selected and covers `/chosen` bootargs, syscfg/sysmap construction, `/sys`, and `sysinfo` consumers. Next gate: separate Rust-default RC decision. |
| `tm_pathmgr` task-manager provider | Rust opt-in | `qsoe-tm-pathmgr` exports the existing `tm_pathmgr.h` ABI behind `QSOE_RUST_TM_PATHMGR=1`; `make tm-pathmgr-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies NQ/LQ taskman links with C rollback and Rust-selected archives. `make tm-pathmgr-runtime-smoke` boots LQ with Rust `tm_pathmgr` selected and covers `/dev` readdir, `/etc` symlink file access, `/dev/console` repath, dynamic helper registration, duplicate rejection, MsgSend through the resolved binding, and unregister-on-exit cleanup. Next gate: separate Rust-default RC decision. |
| `tm_pseudodev` task-manager provider | Rust opt-in | `qsoe-tm-pseudodev` exports the existing LQ `/dev/null` and `/dev/zero` ABI behind `QSOE_RUST_TM_PSEUDODEV=1`; `make tm-pseudodev-evidence` runs Rust host tests, audits the soft-float staticlib, and verifies LQ C-default/Rust-selected taskman links. Next gate: add a focused `/dev/null` and `/dev/zero` runtime smoke before any Rust-default RC decision. |
| `tm_rsrcdb` task-manager provider | Rust opt-in | `qsoe-tm-rsrcdb` exports the existing LQ `tm_rsrc_*` ABI behind `QSOE_RUST_TM_RSRCDB=1`; `make tm-rsrcdb-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies LQ C-default/Rust-selected taskman links. Next gate: add runtime coverage through `rsrcdbmgr_*` callers before any Rust-default RC decision. |
| `tm_script` task-manager provider | Rust opt-in | `qsoe-tm-script` exports the existing `tm_script.h` ABI behind `QSOE_RUST_TM_SCRIPT=1`; `make tm-script-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies NQ/LQ taskman links with C rollback and Rust-selected archives. `make tm-script-runtime-smoke` boots LQ with Rust `tm_script` selected and runs a staged `/usr/bin` shebang script directly. Next gate: separate Rust-default RC decision. |
| `tm_syscfg` task-manager provider | Rust opt-in | `qsoe-tm-syscfg` exports the existing `tm_syscfg.h` ABI behind `QSOE_RUST_TM_SYSCFG=1`; `make tm-syscfg-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies NQ/LQ taskman links with C rollback and Rust-selected archives. `make tm-syscfg-runtime-smoke` boots LQ with Rust `tm_syscfg` selected and verifies syscfg-backed `/sys` and `sysinfo` consumers still work while LQ's private runtime syscfg builder remains C. Next gate: separate Rust-default RC decision that accepts this boundary. |
| `tm_sysmap` task-manager provider | Rust opt-in | `qsoe-tm-sysmap` exports the existing LQ `tm_sysmap_*` ABI behind `QSOE_RUST_TM_SYSMAP=1`; `make tm-sysmap-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies LQ taskman links with C rollback and Rust-selected archives. `make tm-sysmap-runtime-smoke` boots LQ with Rust `tm_sysmap` selected and verifies a spawned `sysinfo` child consumes the mapped `PSYS` page for timebase, PLIC, and PCI data. Next gate: separate Rust-default RC decision. |
| `tm_sysfs` task-manager provider | Rust opt-in | `qsoe-tm-sysfs` exports the existing `tm_sysfs.h` ABI behind `QSOE_RUST_TM_SYSFS=1`; `make tm-sysfs-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies NQ/LQ taskman links with C rollback and Rust-selected archives. `make tm-sysfs-runtime-smoke` boots LQ with Rust `tm_sysfs` selected, enumerates `/sys`, and reads all five portable `/sys` files from sysinit. Next gate: separate Rust-default RC decision. |
| Kernel Rust | Deferred | Current decision rejects near-term Rust in `nq` kernel code; only fixture/audit candidates are documented. |
| C retirement | Five removals complete | `test_msgpass` is the first retired C helper; `slogger`, `pipe`, and `devb-virtio` are retired C production paths after their Rust-default RC evidence; `tm_procfs` is the first retired task-manager provider. Future removals still require #26's checklist and a separate removal PR. |

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
- `slogger-rs` has moved past its Rust-default release-candidate path into C
  service retirement. The old C rollback flags now fail fast; normal NQ/LQ
  images stage Rust `slogger-rs` as `/sbin/slogger`.
- `pipe-rs` has moved past its Rust-default release-candidate path into C
  service retirement. The old C rollback flags now fail fast; normal NQ/LQ
  images stage Rust `pipe-rs` as `/sbin/pipe`.
- `test_msgpass-rs` passed its Rust-default test-image release-candidate path
  with explicit C rollback, then became the first C retirement candidate. The
  current image path stages Rust only.
- `devb-virtio-rs` has moved past its Rust-default release-candidate path into
  C driver retirement. The old C rollback flags now fail fast; normal NQ/LQ
  images stage Rust `devb-virtio-rs` as `/sbin/devb-virtio`.
- `tm_procfs` has moved past its Rust-default release-candidate path into C
  provider retirement. The old C rollback selector now fails fast; normal NQ/LQ
  taskman builds link Rust `qsoe-tm-procfs` through the shared provider
  archive.
- `tm_cpio`, `tm_cred`, `tm_elf`, `tm_fdt`, `tm_pathmgr`, `tm_pseudodev`,
  `tm_rsrcdb`, `tm_script`, `tm_syscfg`, `tm_sysmap`, and `tm_sysfs` are Rust
  opt-in task-manager providers only.
  `tm_cpio`, `tm_elf`, `tm_fdt`, `tm_script`, `tm_syscfg`, `tm_sysmap`, and `tm_sysfs` now have focused runtime
  smoke coverage; keep all opt-in providers C-default until their runtime
  evidence and separate RC decisions exist.

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
make rust-virtio-file-smoke
make virtio-rc-file-smoke
make rust-test-msgpass-smoke
make test-msgpass-rc-smoke
make pipe-smoke
make rust-pipe-smoke
make rust-pipe-data-smoke
make pipe-rc-data-smoke
make check-tm-cpio-model
make rust-tm-cpio-provider
make tm-cpio-evidence
make tm-cpio-runtime-smoke
make check-tm-cred-model
make rust-tm-cred-provider
make tm-cred-evidence
make check-tm-elf-model
make rust-tm-elf-provider
make tm-elf-evidence
make tm-elf-runtime-smoke
make check-tm-fdt-model
make rust-tm-fdt-provider
make tm-fdt-evidence
make tm-fdt-runtime-smoke
make check-tm-pathmgr-model
make rust-tm-pathmgr-provider
make tm-pathmgr-evidence
make tm-pathmgr-runtime-smoke
make check-tm-procfs-model
make rust-tm-procfs-provider
make tm-procfs-evidence
make rust-tm-pseudodev-provider
make tm-pseudodev-evidence
make check-tm-script-model
make rust-tm-script-provider
make tm-script-evidence
make tm-script-runtime-smoke
make check-tm-syscfg-model
make rust-tm-syscfg-provider
make tm-syscfg-evidence
make tm-syscfg-runtime-smoke
make check-tm-sysmap-model
make rust-tm-sysmap-provider
make tm-sysmap-evidence
make tm-sysmap-runtime-smoke
make check-tm-sysfs-model
make rust-tm-sysfs-provider
make tm-sysfs-evidence
make tm-sysfs-runtime-smoke
make tm-procfs-rc-smoke
QSOE_RUST_TM_PROCFS=1 make procfs-smoke
make procfs-smoke
```

Generated artifacts stay out of git under `build/`, `rust/target/`, and
`sel4-bootstrap/`.
