# OS-wide C Inventory

Captured: 2026-06-30 CEST.

This inventory gives the migration tracker an OS-wide baseline. It is not a
claim that every C file is an independently translatable component. It separates
the current C surface into roots, tracked Rust migration targets, deferred
high-risk areas, and areas that still need later issue splitting.

## Source Count

Generated with:

```sh
scripts/c-index.sh files
```

The default index roots are `common`, `host_tools`, `libc`, `libtaskman`, `lq`,
`nq`, and `quser`. Build outputs, Rust targets, and seL4 vendor trees are
excluded unless `QSOE_INDEX_SEL4=1` is set.

| Root | Indexed files | Approx LOC | Current migration posture |
| --- | ---: | ---: | --- |
| `common` | 2 | 359 | Shared CPIO helper code. Rust CPIO parsing exists, but C remains for existing callers. |
| `host_tools` | 2 | 781 | `qrvfs-tree` and `mkfs-qrv-rs` have Rust-default RC paths with C rollback. Tracked by #136. |
| `libc` | 447 | 43,080 | Broad runtime, syscall, stdio, allocator, string, rtld, and QSOE wrapper surface. Not a wholesale Rust target. |
| `libtaskman` | 21 | 2,818 | Best source of host-testable task-manager modules. `tm_procfs` and `tm_script` are retired to Rust through the shared provider archive; `tm_cpio`, `tm_elf`, `tm_syscfg`, and `tm_sysfs` are Rust-default RCs with C rollback; `tm_cred` and `tm_pathmgr` are Rust opt-in; remaining candidates are tracked in #153. |
| `lq` | 90 | 17,853 | seL4 task manager, LQ libc wrappers, process, capability, path, memory, syscall, and boot glue. Pure/diagnostic slices only are candidates; LQ sysmap is Rust-default RC, while FDT, pseudo-devices, and resource DB accounting remain Rust opt-in. |
| `nq` | 125 | 25,053 | Kernel, NQ libc, and NQ taskman surface. Near-term linked Rust is deferred by policy; fixture-only candidates are tracked in #155. |
| `quser` | 125 | 40,818 | Userland services, drivers, resource-server support, shell, tests, and utilities. `test_msgpass` is the first retired C helper; `slogger`, `pipe`, and `devb-virtio` are retired C production paths; several services have Rust pilots; many remain C. |
| **Total** | **812** | **130,762** | QSOE-owned C/asm/linker surface in this checkout, excluding generated build outputs and vendor seL4. |

By file type: `520` C files, `280` headers, `10` assembly files, and `2` linker
scripts.

## Issue-backed Migration Ledger

The canonical tracker is GitHub Issues filtered by `label:roadmap`. At this
capture, the tracker contains 38 roadmap issues:

| Kind | Count | Meaning |
| --- | ---: | --- |
| Phase issues | 11 | Migration phases and policy gates from baseline through possible kernel reassessment. |
| Component issues | 17 | Components with concrete Rust artifacts or RC evidence. |
| Tooling issues | 4 | Workflow, memory, CI cache, and static-analysis gates that support the migration process. |
| Backlog, retirement, and inventory issues | 6 | Remaining candidates, deferred areas, retirement gate, shared task-manager Rust archive work, and this inventory. |

All roadmap issues carry parseable `qsoe-roadmap:v1` metadata for the dashboard.
Issue state, labels, and metadata are the source of truth for current progress.

## Tracked Component State

| Component | Issue | Current state |
| --- | --- | --- |
| Host qrvfs tools | #136 | Rust-default RC for `qrvfs-tree` and `mkfs-qrv-rs`; C remains rollback and no C implementation is retired. |
| `slogger` | #137 | Retired C service; Rust `slogger-rs` is always staged as `/sbin/slogger` in NQ/LQ images. |
| `devb-virtio` | #138 | Retired C block driver; Rust `devb-virtio-rs` is always staged as `/sbin/devb-virtio` in NQ/LQ images. |
| `pipe` | #139 | Retired C service; Rust `pipe-rs` is always staged as `/sbin/pipe` in NQ/LQ images. |
| `test_msgpass` | #140 | Retired C helper; Rust `test_msgpass-rs` is always staged as `/usr/bin/test_msgpass` in test images. |
| `tm_procfs` | #141 | Retired C provider; Rust `qsoe-tm-procfs` is mandatory in taskman. |
| `tm_cpio` | #142 | Rust-default RC provider with C rollback, focused runtime smoke, and explicit RC rollback smoke. |
| `tm_script` | #143 | Retired C provider; Rust `qsoe-tm-script` is mandatory in taskman. |
| `tm_elf` | #144 | Rust-default RC provider with C rollback, focused dynamic ELF spawn smoke, and explicit RC rollback smoke. |
| `tm_fdt` | #146 | Rust opt-in LQ FDT parser provider with C rollback and focused `/chosen`/syscfg runtime smoke; not a Rust-default RC. |
| `tm_syscfg` | #145 | Rust-default RC provider with C rollback, focused `/sys`/`sysinfo` runtime smoke, and explicit RC rollback smoke. |
| `tm_sysmap` | #147 | Rust-default RC LQ sysmap page builder provider with C rollback, focused spawned-child `PSYS` runtime smoke, and explicit RC rollback smoke. |
| `tm_pathmgr` | #149 | Rust opt-in path registry provider with C rollback and focused runtime smoke; not a Rust-default RC. |
| `tm_rsrcdb` | #151 | Rust opt-in LQ resource DB provider with C rollback and focused `rsrcdbmgr_*` runtime smoke; not a Rust-default RC. |
| `tm_cred` | #150 | Rust opt-in provider with C rollback and focused credential runtime smoke; not a Rust-default RC. |
| `tm_pseudodev` | #152 | Rust opt-in LQ pseudo-device provider with C rollback and focused `/dev/null` plus `/dev/zero` runtime smoke; not a Rust-default RC. |
| `tm_sysfs` | #148 | Rust-default RC provider with C rollback, focused `/sys` runtime smoke, and explicit RC rollback smoke. |

`test_msgpass` is the first tracked C implementation retired after an RC window
and rollback drill. `slogger` is the first retired production service, followed
by `pipe` and `devb-virtio`. `tm_procfs` is the first retired task-manager
provider; `tm_script` is the second retired task-manager provider. Future retirements remain governed by #26 and must be separate
removal PRs after their own RC evidence.

## Remaining Candidate Buckets

| Bucket | Issues | Posture |
| --- | --- | --- |
| Host qrvfs tools | #136 | Complete for current scope: `qrvfs-tree` and `mkfs-qrv-rs` have Rust-default RC paths. Keep C rollback until #26. |
| Task-manager pure or diagnostic modules | #153 | Candidate backlog. Prefer host-tested modules that avoid direct seL4 invocations, spawn, capability ownership, relocation writes, and loader admission. |
| Spawn, capability, relocation, and loader paths | #154 | Deferred. These paths are load-bearing for process creation and teardown. |
| Kernel Rust | #155 | Deferred. Current policy allows documentation and fixtures only. |
| C retirement gate | #26 | Exercised by retiring the C `test_msgpass` helper plus C `slogger`, `pipe`, and `devb-virtio` production paths after their Rust-default RC evidence. Future removals must repeat the same checklist. |
| OS-wide inventory | #156 | Satisfied by this document once merged. |
| Shared task-manager Rust archive | #179 | Complete: selected taskman Rust providers link through one `qsoe-tm-providers` archive with one panic handler. |

## Areas Not Yet Split Into Per-component Issues

These areas remain C and should not be treated as untracked approval for Rust
rewrites. Split them into explicit roadmap issues only when the next phase needs
a scoped candidate and acceptance criteria.

| Area | Current reason to keep coarse-grained |
| --- | --- |
| `libc` runtime and `rtld` | Broad ABI and startup surface. Individual QSOE wrappers can be reviewed later, but the C runtime itself is not a near-term migration component. |
| `qsh` | Large shell grammar, job-control, IO, and interactive behavior surface. Keep C until several smaller services are retired or have long-running RC evidence. |
| Login path services | `getty` and `login` are small but user-visible. They need prompt, auth failure, auth success, and shell handoff smokes before issue splitting. |
| Storage and platform services | `fs-qrv`, `pci-server`, `devb-nvme`, and console drivers have hardware, boot, or mount dependencies. Keep them behind service-ranking review. |
| NQ kernel and NQ taskman | Kernel-adjacent Rust remains fixture-only under the current decision. No linked Rust kernel path is approved. |
| LQ taskman core | Process creation, CSpace ownership, seL4 object lifetime, IRQ, memory mapping, and loader admission stay C until dedicated boundary reviews exist. |

## Next Recommended Issue Work

1. Use #153 for the remaining small task-manager pilot.
   Prefer low-risk pure modules before touching path manager or loader-critical
   inputs.
2. Keep #154, #155, and #26 policy-blocked until their stated gates change.
