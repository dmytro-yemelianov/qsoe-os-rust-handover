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
- The C `tm_procfs`, `tm_cpio`, `tm_cred`, `tm_script`, `tm_elf`,
  `tm_syscfg`, `tm_sysmap`, `tm_sysfs`, `tm_pathmgr`, `tm_pseudodev`, and
  `tm_rsrcdb` task-manager providers are retired; taskman now links their Rust
  providers through the shared `qsoe-tm-providers` archive.
- `qsoe-tm-fdt` remains in Rust-default RC with C rollback. Selected
  task-manager Rust providers are packaged through the shared
  `qsoe-tm-providers` archive so multiple providers can link behind one panic
  handler; C remains the normal taskman default for each remaining opt-in
  provider.
- Rust `mkfs-qrv-rs` has fixture, production-root, target-initialization,
  bounded triple-indirect allocator, live virtio `/usr`, and C rollback smoke
  evidence.
- Future C retirements still require #26's checklist and a separate removal PR.
  C remains the rollback path for all non-retired migration candidates.

Detailed planning lives under `docs/rust-migration/`. Start with:

- [Rust migration roadmap dashboard](https://dmytro-yemelianov.github.io/qsoe-os-rust-handover/)
  for the issue-backed roadmap dashboard published through GitHub Pages,
  including component state and tooling gates.
- [GitHub Issues filtered by `roadmap`](https://github.com/dmytro-yemelianov/qsoe-os-rust-handover/issues?q=label%3Aroadmap)
  for the canonical migration tracker.
- `docs/rust-migration/HANDOVER.md` for the current repository state and next
  work.
- `docs/rust-migration/INVENTORY.md` for the OS-wide C inventory and remaining
  translation buckets.
- `docs/rust-migration/STATUS.md` for component-by-component migration state.
- `docs/rust-migration/WORKFLOW.md` for the quality tiers, Codebase Memory
  discovery order, `make roadmap-validate`, `make roadmap-component-gate`, and
  issue-backed tooling gates (#200 through #203).
- `docs/rust-migration/RETIREMENT.md` for the gate before any C code removal.
- `docs/rust-migration/DEVLOG.md` for command history and validation evidence.

## Current Progress

| Area | Current state | Evidence / next gate |
| --- | --- | --- |
| Baseline and tooling | Complete | Linux/container workflows, boot smokes, artifact audit, C indexing, clangd, clang-tidy wrapper, pinned Rust toolchain, cargo-deny, fuzz smoke, coverage targets, issue-backed roadmap gates, and scoped CI Cargo/`sccache` cache wiring are in place. |
| Rust ABI/FFI foundation | Complete | `qsoe-abi`, `qsoe-ffi`, and `qsoe-ressrv` compile for the QSOE target with layout tests and reviewed unsafe boundaries. |
| Host qrvfs tools | Rust default RC for inspector and writer | Rust fixture checks compare against the existing C host tool; `make tree` selects Rust `qrvfs-tree` by default, and `make treeqrvfs-rc-rollback-smoke` preserves C rollback. `make mkfs-qrv-rc-live-smoke` selects Rust `mkfs-qrv-rs` by default for the writer RC, and `make mkfs-qrv-rc-rollback-smoke` restores C. Fixture, production-root, stale-target, bounded triple-indirect allocator, and live `/usr` smokes cover the writer path. Production C remains rollback. |
| `slogger` service | Retired C service | `slogger-rs` links, boots, registers `/dev/slog`, is staged as `/sbin/slogger` in normal NQ/LQ images, and passes the `/dev/slog` readback smoke through `make slogger-rc-readback-smoke`. The C service source and rollback targets are removed by the retirement PR. |
| `devb-virtio` block driver | Retired C driver | Rust MMIO/virtqueue model, host queue tests, link/boot/file-read smokes, and `make virtio-rc-file-smoke` cover the Rust-only file-read path. Normal NQ/LQ images stage Rust `devb-virtio-rs` as `/sbin/devb-virtio`; the C driver source and rollback target are removed by the retirement PR. |
| Shared parsers | Complete for current scope | CPIO, syscfg/sysmap, and ELF inspection crates exist with host tests and host/guest reuse coverage. |
| `pipe` service | Retired C service | `qsoe-pipe` host tests pass, `pipe-rs` links and audits, `make rust-pipe-smoke` boots LQ with Rust `/sbin/pipe` registered, `make rust-pipe-data-smoke` proves a libc/taskman `pipe(2)` write/read round trip, and `make pipe-rc-data-smoke` validates the Rust-only service path. The C service source and rollback targets are removed by the retirement PR. |
| `test_msgpass` helper | Retired C helper | `test_msgpass-rs` links, is always staged into the qrvfs test image as `/usr/bin/test_msgpass`, and passes the existing suite `[msgpass]` section through `make rust-test-msgpass-smoke` and `make test-msgpass-rc-smoke`. The C helper source and rollback target are removed by the retirement PR. |
| `tm_procfs` task-manager pilot | Retired C provider | `qsoe-tm-procfs` exports the existing C ABI and is mandatory in taskman through the shared `qsoe-tm-providers` archive. `make tm-procfs-evidence` verifies Rust host tests, archive audit, no `tm_procfs.o` in NQ/LQ `libtaskman.a`, retired selector rejection, and the Rust-only `/proc` smoke. |
| Task-manager Rust provider archive | Shared provider link unit | `qsoe-tm-providers` packages selected taskman Rust providers into one `libqsoe_tm_providers.a` with one panic handler. `make tm-providers-evidence` selects the current shared provider set including `tm_cpio`, `tm_cred`, `tm_fdt`, `tm_pathmgr`, `tm_procfs`, `tm_pseudodev`, and `tm_rsrcdb`, audits the soft-float archive and final taskman ELFs, verifies selected portable C objects are absent, and runs the shared-provider `/proc` smoke. |
| `tm_cpio` task-manager provider | Retired C provider | `qsoe-tm-cpio` exports the existing `tm_cpio.h` ABI and is mandatory in normal NQ/LQ taskman builds. `QSOE_RUST_TM_CPIO=0` fails fast, `libtaskman/src/cpio.c` is removed, and `make tm-cpio-evidence` verifies Rust host tests, soft-float archive audit, no C `cpio.o` in NQ/LQ taskman links, retired selector rejection, and exported symbols. `make tm-cpio-rc-smoke` boots LQ through CPIO symlink/read/spawn paths on the Rust-only path. |
| `tm_cred` task-manager provider | Retired C provider | `qsoe-tm-cred` exports the existing `tm_cred.h` ABI and is mandatory in normal NQ/LQ taskman builds. `QSOE_RUST_TM_CRED=0` fails fast, `libtaskman/src/cred.c` is removed, and `make tm-cred-evidence` verifies Rust host tests, soft-float archive audit, no C `cred.o` in NQ/LQ taskman links, retired selector rejection, and exported symbols. `make tm-cred-rc-smoke` boots LQ through live uid/gid mutation, umask, cwd, permission rejection, and spawn inheritance on the Rust-only path. |
| `tm_elf` task-manager provider | Retired C provider | `qsoe-tm-elf` exports the existing `tm_elf.h` ABI and is mandatory in normal NQ/LQ taskman builds. `QSOE_RUST_TM_ELF=0` fails fast, `libtaskman/src/elf.c` is removed, and `make tm-elf-evidence` verifies Rust host tests, soft-float archive audit, no C `elf.o` in NQ/LQ taskman links, retired selector rejection, and exported symbols. `make tm-elf-rc-smoke` boots LQ through a dynamic `/usr/bin/sysinfo` spawn on the Rust-only path. |
| `tm_fdt` task-manager provider | Rust default RC | `qsoe-tm-fdt` exports the existing LQ `tm_fdt_*` ABI and is selected by default through `QSOE_RUST_TM_FDT=1`; `make tm-fdt-evidence` runs C/Rust host tests, audits the soft-float staticlib, and verifies LQ taskman links with Rust default and C rollback. `make tm-fdt-rc-smoke` boots LQ through `/chosen` bootargs, syscfg/sysmap construction, `/sys`, and `sysinfo` consumers on the Rust-default path. `make tm-fdt-rc-rollback-smoke` keeps C `sys/fdt.o` rollback live. |
| `tm_pathmgr` task-manager provider | Retired C provider | `qsoe-tm-pathmgr` exports the existing `tm_pathmgr.h` ABI and is mandatory through `QSOE_RUST_TM_PATHMGR=1`; `QSOE_RUST_TM_PATHMGR=0` fails fast, `libtaskman/src/pathmgr.c` is removed, and `make tm-pathmgr-evidence` verifies Rust host tests, soft-float archive audit, no C `pathmgr.o` in NQ/LQ taskman links, retired selector rejection, and exported symbols. `make tm-pathmgr-rc-smoke` covers the Rust-only namespace path through `/dev` readdir, `/etc` symlink file access, `/dev/console` repath, dynamic helper registration, duplicate rejection, MsgSend through the resolved binding, and unregister-on-exit cleanup. |
| `tm_pseudodev` task-manager provider | Retired C provider | `qsoe-tm-pseudodev` exports the existing LQ `/dev/null` and `/dev/zero` ABI and is mandatory through `QSOE_RUST_TM_PSEUDODEV=1`; `QSOE_RUST_TM_PSEUDODEV=0` fails fast, C `sys/devnull.c` and `sys/devzero.c` are removed by the component override, and `make tm-pseudodev-evidence` verifies Rust host tests, soft-float archive audit, no C pseudo-device objects in LQ taskman links, retired selector rejection, and exported symbols. `make tm-pseudodev-rc-smoke` covers the Rust-only `/dev/null` and `/dev/zero` open, write, read, and fstat path. |
| `tm_rsrcdb` task-manager provider | Retired C provider | `qsoe-tm-rsrcdb` exports the existing LQ `tm_rsrc_*` ABI and is mandatory through `QSOE_RUST_TM_RSRCDB=1`; `QSOE_RUST_TM_RSRCDB=0` fails fast, C `sys/rsrcdb.c` is removed by the component override, and `make tm-rsrcdb-evidence` verifies Rust host tests, soft-float archive audit, no C `sys/rsrcdb.o` in LQ taskman links, retired selector rejection, and exported symbols. `make tm-rsrcdb-rc-smoke` covers the Rust-only live `rsrcdbmgr_*` create, attach, query, detach, and destroy path. |
| `tm_script` task-manager provider | Retired C provider | `qsoe-tm-script` exports the existing `tm_script.h` ABI and is mandatory in normal NQ/LQ taskman builds. `QSOE_RUST_TM_SCRIPT=0` fails fast, `libtaskman/src/script.c` is removed, and `make tm-script-evidence` verifies Rust host tests, soft-float archive audit, no C `script.o` in NQ/LQ taskman links, retired selector rejection, and exported symbols. `make tm-script-rc-smoke` boots LQ through direct shebang-backed script spawn on the Rust-only path. |
| `tm_syscfg` task-manager provider | Retired C provider | `qsoe-tm-syscfg` exports the existing `tm_syscfg.h` ABI and is mandatory in normal NQ/LQ taskman builds. `QSOE_RUST_TM_SYSCFG=0` fails fast, `libtaskman/src/syscfg.c` is removed, and `make tm-syscfg-evidence` verifies Rust host tests, soft-float archive audit, no C `syscfg.o` in NQ/LQ `libtaskman.a`, and retired selector rejection. `make tm-syscfg-rc-smoke` boots LQ through syscfg-backed `/sys` and `sysinfo` consumers while LQ's private runtime syscfg builder remains C. |
| `tm_sysmap` task-manager provider | Retired C provider | `qsoe-tm-sysmap` exports the existing LQ `tm_sysmap_*` ABI and is mandatory in normal LQ taskman builds. `QSOE_RUST_TM_SYSMAP=0` fails fast, `lq/taskman/sys/sysmap.c` is removed by the component override, and `make tm-sysmap-evidence` verifies Rust host tests, soft-float archive audit, no C `sys/sysmap.o` in LQ taskman links, retired selector rejection, and exported symbols. `make tm-sysmap-rc-smoke` boots LQ through spawned-child `sysinfo` consumers of the mapped `PSYS` page on the Rust-only path. |
| `tm_sysfs` task-manager provider | Retired C provider | `qsoe-tm-sysfs` exports the existing `tm_sysfs.h` ABI and is mandatory in normal NQ/LQ taskman builds. `QSOE_RUST_TM_SYSFS=0` fails fast, `libtaskman/src/tm_sysfs.c` is removed, and `make tm-sysfs-evidence` verifies Rust host tests, soft-float archive audit, no C `tm_sysfs.o` in NQ/LQ taskman links, retired selector rejection, and exported symbols. `make tm-sysfs-rc-smoke` boots LQ through `/sys` readdir plus all five portable `/sys` file reads on the Rust-only path. |
| Kernel Rust | Deferred | Current decision rejects near-term Rust in `nq` kernel code; only fixture/audit candidates are documented. |
| C retirement | Fifteen removals complete | `test_msgpass` is the first retired C helper; `slogger`, `pipe`, and `devb-virtio` are retired C production paths after their Rust-default RC evidence; `tm_procfs` is the first retired task-manager provider, followed by `tm_cpio`, `tm_cred`, `tm_script`, `tm_elf`, `tm_syscfg`, `tm_sysmap`, `tm_sysfs`, `tm_pathmgr`, `tm_pseudodev`, and `tm_rsrcdb`. Future removals still require #26's checklist and a separate removal PR. |

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
- `tm_procfs`, `tm_script`, `tm_cpio`, `tm_cred`, `tm_elf`, `tm_syscfg`,
  `tm_sysmap`, and `tm_sysfs`
  have moved past their
  Rust-default release-candidate paths into C provider retirement. The old C
  rollback selectors now fail fast; normal NQ/LQ taskman builds link Rust
  `qsoe-tm-procfs`, `qsoe-tm-script`, `qsoe-tm-cpio`, `qsoe-tm-cred`,
  `qsoe-tm-elf`, `qsoe-tm-syscfg`, `qsoe-tm-sysmap`, and `qsoe-tm-sysfs`
  through the shared provider archive.
- `tm_pathmgr`, `tm_pseudodev`, and `tm_rsrcdb` have moved past their
  Rust-default release-candidate paths into C provider retirement. The old C
  rollback selectors now fail fast; normal NQ/LQ taskman builds link Rust
  `qsoe-tm-pathmgr`, `qsoe-tm-pseudodev`, and `qsoe-tm-rsrcdb` through the
  shared provider archive.
- `tm_fdt` remains a Rust-default task-manager RC with C rollback. Keep its C
  provider until #26's checklist and a separate removal PR are satisfied.

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
make tm-cpio-rc-smoke
make check-tm-cred-model
make rust-tm-cred-provider
make tm-cred-evidence
make tm-cred-runtime-smoke
make tm-cred-rc-smoke
make check-tm-elf-model
make rust-tm-elf-provider
make tm-elf-evidence
make tm-elf-runtime-smoke
make tm-elf-rc-smoke
make check-tm-fdt-model
make rust-tm-fdt-provider
make tm-fdt-evidence
make tm-fdt-runtime-smoke
make tm-fdt-rc-smoke
make tm-fdt-rc-rollback-smoke
make check-tm-pathmgr-model
make rust-tm-pathmgr-provider
make tm-pathmgr-evidence
make tm-pathmgr-runtime-smoke
make tm-pathmgr-rc-smoke
make check-tm-procfs-model
make rust-tm-procfs-provider
make tm-procfs-evidence
make rust-tm-pseudodev-provider
make tm-pseudodev-evidence
make tm-pseudodev-runtime-smoke
make tm-pseudodev-rc-smoke
make check-tm-rsrcdb-model
make rust-tm-rsrcdb-provider
make tm-rsrcdb-evidence
make tm-rsrcdb-runtime-smoke
make tm-rsrcdb-rc-smoke
make check-tm-script-model
make rust-tm-script-provider
make tm-script-evidence
make tm-script-runtime-smoke
make tm-script-rc-smoke
make check-tm-syscfg-model
make rust-tm-syscfg-provider
make tm-syscfg-evidence
make tm-syscfg-runtime-smoke
make tm-syscfg-rc-smoke
make check-tm-sysmap-model
make rust-tm-sysmap-provider
make tm-sysmap-evidence
make tm-sysmap-runtime-smoke
make tm-sysmap-rc-smoke
make check-tm-sysfs-model
make rust-tm-sysfs-provider
make tm-sysfs-evidence
make tm-sysfs-runtime-smoke
make tm-sysfs-rc-smoke
make tm-procfs-rc-smoke
QSOE_RUST_TM_PROCFS=1 make procfs-smoke
make procfs-smoke
```

Generated artifacts stay out of git under `build/`, `rust/target/`, and
`sel4-bootstrap/`.
