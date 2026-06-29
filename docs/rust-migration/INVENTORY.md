# OS-wide C Inventory

Captured: 2026-06-29 09:07 CEST.

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
| `libtaskman` | 23 | 3,013 | Best source of host-testable task-manager modules. `tm_procfs` is Rust-default RC; more candidates are tracked in #142-#153. |
| `lq` | 90 | 17,853 | seL4 task manager, LQ libc wrappers, process, capability, path, memory, syscall, and boot glue. Pure/diagnostic slices only are candidates. |
| `nq` | 125 | 25,053 | Kernel, NQ libc, and NQ taskman surface. Near-term linked Rust is deferred by policy; fixture-only candidates are tracked in #155. |
| `quser` | 127 | 41,355 | Userland services, drivers, resource-server support, shell, tests, and utilities. Several services have Rust pilots; many remain C. |
| **Total** | **816** | **131,494** | QSOE-owned C/asm/linker surface in this checkout, excluding generated build outputs and vendor seL4. |

By file type: `523` C files, `281` headers, `10` assembly files, and `2` linker
scripts.

## Issue-backed Migration Ledger

The canonical tracker is GitHub Issues filtered by `label:roadmap`. At this
capture, the tracker contains 33 roadmap issues:

| Kind | Count | Meaning |
| --- | ---: | --- |
| Phase issues | 11 | Migration phases and policy gates from baseline through possible kernel reassessment. |
| Component issues | 6 | Components with concrete Rust artifacts or RC evidence. |
| Backlog, retirement, and inventory issues | 16 | Remaining candidates, deferred areas, retirement gate, and this inventory. |

All roadmap issues carry parseable `qsoe-roadmap:v1` metadata for the dashboard.
Issue state, labels, and metadata are the source of truth for current progress.

## Tracked Component State

| Component | Issue | Current state |
| --- | --- | --- |
| Host qrvfs tools | #136 | Rust-default RC for `qrvfs-tree` and `mkfs-qrv-rs`; C remains rollback and no C implementation is retired. |
| `slogger` | #137 | Rust-default RC with C rollback. |
| `devb-virtio` | #138 | Rust-default RC with C rollback. |
| `pipe` | #139 | Rust-default RC with C rollback. |
| `test_msgpass` | #140 | Rust-default RC with C rollback. |
| `tm_procfs` | #141 | Rust-default RC with C rollback. |

No tracked C implementation is retired. Retirement is governed by #26 and must
be a separate removal PR after an RC window and rollback drill.

## Remaining Candidate Buckets

| Bucket | Issues | Posture |
| --- | --- | --- |
| Host qrvfs tools | #136 | Complete for current scope: `qrvfs-tree` and `mkfs-qrv-rs` have Rust-default RC paths. Keep C rollback until #26. |
| Task-manager pure or diagnostic modules | #142-#153 | Candidate backlog. Prefer host-tested modules that avoid direct seL4 invocations, spawn, capability ownership, relocation writes, and loader admission. |
| Spawn, capability, relocation, and loader paths | #154 | Deferred. These paths are load-bearing for process creation and teardown. |
| Kernel Rust | #155 | Deferred. Current policy allows documentation and fixtures only. |
| First C retirement | #26 | Needed, but blocked until a chosen component satisfies the retirement checklist and a separate removal PR is prepared. |
| OS-wide inventory | #156 | Satisfied by this document once merged. |

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

1. Use #142-#153 for small task-manager pilots. Prefer `tm_log`, `tm_cred`, or
   another low-risk pure module before touching path manager or ELF-adjacent
   loader inputs.
2. Keep #154, #155, and #26 policy-blocked until their stated gates change.
