# C Implementation Retirement Gate

Captured: 2026-07-01 CEST.

This document turns the Phase 8 retirement rule into an explicit gate. The
first removal was the in-guest test helper `test_msgpass`, which had a
Rust-default release-candidate path and C rollback drill before its retirement
PR removed the C helper. The next removals were production services
`/sbin/slogger`, `/sbin/pipe`, and `/sbin/devb-virtio` after their own
Rust-default RC evidence. Host qrvfs tools `treeqrvfs` and `mkfs-qrv` are also retired after their own inspector and writer RC windows. The current retired task-manager providers are
`tm_procfs`, `tm_cpio`, `tm_cred`, `tm_script`, `tm_elf`, `tm_fdt`,
`tm_syscfg`, `tm_sysmap`, `tm_sysfs`, `tm_pathmgr`, `tm_pseudodev`, and `tm_rsrcdb` after their own
Rust-default RC evidence and rollback drills. All remaining Rust pilots stay
either opt-in or Rust-default RC paths, and each non-retired C implementation
remains the rollback path until the release-candidate evidence below exists.

## State Model

Every migrated component moves through these states:

| State | Meaning | C implementation |
| --- | --- | --- |
| C default | Normal images install and run the C artifact. | Required |
| Rust opt-in | A build flag can replace the artifact with Rust for focused tests. | Required rollback |
| Rust default RC | Release-candidate images default to Rust while a build flag or release artifact restores C. | Required rollback |
| Retired | The C artifact is removed from normal source and image paths. | Removed for that component |

A component cannot enter `Retired` directly from `Rust opt-in`. It must first
ship through at least one release candidate with Rust selected by default and a
documented C rollback path.

## Mandatory Evidence

A C removal PR must be separate from the PR that flips the default to Rust, and
it must include evidence for all of these items:

- C behavior specification and known Rust differences.
- Host tests or fixtures for pure logic and parser/state behavior.
- QSOE target link output for the Rust artifact.
- Strict ELF audit covering type, machine, interpreter, relocations, TLS,
  unwind metadata, and unsupported runtime references.
- QEMU boot smoke for the image variant that uses the component.
- Targeted in-guest smoke or suite coverage for the component behavior.
- CI or local-equivalent workflow evidence for the same commands.
- One release-candidate cycle where Rust is the default and C rollback remains
  available.
- Rollback drill showing the exact build flag, artifact selection, or release
  package that restores the C implementation.
- Release notes naming the implementation-language change and rollback window.

## Current Component Status

The live status matrix is `STATUS.md`. It records C default, Rust opt-in, Rust
default, and retired status for every tracked migration component. At this
capture, host qrvfs tools, `test_msgpass`, `slogger`, `pipe`, `devb-virtio`, `tm_procfs`,
`tm_cpio`, `tm_cred`, `tm_script`, `tm_elf`, `tm_syscfg`, `tm_sysmap`,
`tm_sysfs`, `tm_pathmgr`, `tm_pseudodev`, `tm_rsrcdb`, and `tm_fdt` are the tracked components in `Retired` status.
Host qrvfs tools are retired host paths. `test_msgpass` is the first retired helper; `slogger`, `pipe`, and
`devb-virtio` are retired production paths. `tm_procfs` is the first retired
task-manager provider, followed by `tm_cpio`, `tm_cred`, `tm_script`,
`tm_elf`, `tm_syscfg`, `tm_sysmap`, `tm_sysfs`, `tm_pathmgr`,
`tm_pseudodev`, and `tm_rsrcdb`. Remaining production services and
task-manager providers still
require their own separate removal PRs after RC evidence and rollback drills.

## Retired Components

| Component | Retirement note | Prior RC evidence | Current rollback |
| --- | --- | --- | --- |
| Host qrvfs tools | `HOST_QRVFS_RETIREMENT.md` | `TREEQRVFS_RC.md`, `MKFS_QRV_RC.md`, `make treeqrvfs-rc-smoke`, `make mkfs-qrv-rc-live-smoke`, previous `make treeqrvfs-rc-rollback-smoke` and `make mkfs-qrv-rc-rollback-smoke` evidence | No C rollback target remains; Rust `qrvfs-tree` and `mkfs-qrv-rs` are mandatory for host qrvfs inspection and image creation. |
| `test_msgpass` | `TEST_MSGPASS_RETIREMENT.md` | `TEST_MSGPASS_RC.md`, `make test-msgpass-rc-smoke`, previous `make test-msgpass-rc-rollback-smoke` evidence | No C rollback target remains; the retired helper is Rust-only in test images. |
| `slogger` | `SLOGGER_RETIREMENT.md` | `SLOGGER_RC.md`, `make slogger-rc-readback-smoke`, previous `make slogger-rc-rollback-smoke` evidence | No C rollback target remains; Rust `slogger-rs` is staged as `/sbin/slogger` in NQ/LQ images. |
| `pipe` | `PIPE_RETIREMENT.md` | `PIPE_RC.md`, `make pipe-rc-data-smoke`, previous `make pipe-rc-rollback-smoke` evidence | No C rollback target remains; Rust `pipe-rs` is staged as `/sbin/pipe` in NQ/LQ images. |
| `devb-virtio` | `VIRTIO_RETIREMENT.md` | `VIRTIO_RC.md`, `make virtio-rc-file-smoke`, previous `make virtio-rc-rollback-smoke` evidence | No C rollback target remains; Rust `devb-virtio-rs` is staged as `/sbin/devb-virtio` in NQ/LQ images. |
| `tm_procfs` | `TASK_MANAGER_PROCFS_RETIREMENT.md` | `TASK_MANAGER_PROCFS_RC.md`, `make tm-procfs-rc-smoke`, previous `make tm-procfs-rc-rollback-smoke` evidence | No C rollback target remains; Rust `qsoe-tm-procfs` is mandatory in taskman through the shared provider archive. |
| `tm_cpio` | `TASK_MANAGER_CPIO_RETIREMENT.md` | `TASK_MANAGER_CPIO_RC.md`, `make tm-cpio-rc-smoke`, previous `make tm-cpio-rc-rollback-smoke` evidence | No C rollback target remains; Rust `qsoe-tm-cpio` is mandatory in taskman through the shared provider archive. |
| `tm_cred` | `TASK_MANAGER_CRED_RETIREMENT.md` | `TASK_MANAGER_CRED_RC.md`, `make tm-cred-rc-smoke`, previous `make tm-cred-rc-rollback-smoke` evidence | No C rollback target remains; Rust `qsoe-tm-cred` is mandatory in taskman through the shared provider archive. |
| `tm_script` | `TASK_MANAGER_SCRIPT_RETIREMENT.md` | `TASK_MANAGER_SCRIPT_RC.md`, `make tm-script-rc-smoke`, previous `make tm-script-rc-rollback-smoke` evidence | No C rollback target remains; Rust `qsoe-tm-script` is mandatory in taskman through the shared provider archive. |
| `tm_elf` | `TASK_MANAGER_ELF_RETIREMENT.md` | `TASK_MANAGER_ELF_RC.md`, `make tm-elf-rc-smoke`, previous `make tm-elf-rc-rollback-smoke` evidence | No C rollback target remains; Rust `qsoe-tm-elf` is mandatory in taskman through the shared provider archive. |
| `tm_fdt` | `TASK_MANAGER_FDT_RETIREMENT.md` | `TASK_MANAGER_FDT_RC.md`, `make tm-fdt-rc-smoke`, previous `make tm-fdt-rc-rollback-smoke` evidence | No C rollback target remains for the LQ FDT parser provider; Rust `qsoe-tm-fdt` is mandatory in taskman through the shared provider archive. |
| `tm_syscfg` | `TASK_MANAGER_SYSCFG_RETIREMENT.md` | `TASK_MANAGER_SYSCFG_RC.md`, `make tm-syscfg-rc-smoke`, previous `make tm-syscfg-rc-rollback-smoke` evidence | No C rollback target remains for the portable `libtaskman` provider; Rust `qsoe-tm-syscfg` is mandatory in taskman through the shared provider archive. |
| `tm_sysmap` | `TASK_MANAGER_SYSMAP_RETIREMENT.md` | `TASK_MANAGER_SYSMAP_RC.md`, `make tm-sysmap-rc-smoke`, previous `make tm-sysmap-rc-rollback-smoke` evidence | No C rollback target remains for the LQ sysmap page builder; Rust `qsoe-tm-sysmap` is mandatory in taskman through the shared provider archive. |
| `tm_sysfs` | `TASK_MANAGER_SYSFS_RETIREMENT.md` | `TASK_MANAGER_SYSFS_RC.md`, `make tm-sysfs-rc-smoke`, previous `make tm-sysfs-rc-rollback-smoke` evidence | No C rollback target remains for the portable `/sys` provider; Rust `qsoe-tm-sysfs` is mandatory in taskman through the shared provider archive. |
| `tm_pathmgr` | `TASK_MANAGER_PATHMGR_RETIREMENT.md` | `TASK_MANAGER_PATHMGR_RC.md`, `make tm-pathmgr-rc-smoke`, previous `make tm-pathmgr-rc-rollback-smoke` evidence | No C rollback target remains for the portable path registry provider; Rust `qsoe-tm-pathmgr` is mandatory in taskman through the shared provider archive. |
| `tm_pseudodev` | `TASK_MANAGER_PSEUDODEV_RETIREMENT.md` | `TASK_MANAGER_PSEUDODEV_RC.md`, `make tm-pseudodev-rc-smoke`, previous `make tm-pseudodev-rc-rollback-smoke` evidence | No C rollback target remains for the LQ pseudo-device providers; Rust `qsoe-tm-pseudodev` is mandatory in taskman through the shared provider archive. |
| `tm_rsrcdb` | `TASK_MANAGER_RSRCDB_RETIREMENT.md` | `TASK_MANAGER_RSRCDB_RC.md`, `make tm-rsrcdb-rc-smoke`, previous `make tm-rsrcdb-rc-rollback-smoke` evidence | No C rollback target remains for the LQ resource DB provider; Rust `qsoe-tm-rsrcdb` is mandatory in taskman through the shared provider archive. |

## Removal PR Checklist

Use this checklist when a future component is eligible for removal:

```text
- [ ] Component is in Rust-default RC state.
- [ ] RC tag/build identifier is recorded.
- [ ] C rollback flag, artifact, or package was available through the RC.
- [ ] Rollback drill command and output are linked.
- [ ] C behavior spec and Rust differences are linked.
- [ ] Rust host tests and in-guest smokes are linked.
- [ ] Strict ELF audit output is linked.
- [ ] Release notes use `RELEASE_NOTE_TEMPLATE.md` and describe the language
      change and rollback window.
- [ ] The PR removes only the C implementation and stale C-specific build paths.
```

If any checklist item is missing, the C implementation stays in tree.
