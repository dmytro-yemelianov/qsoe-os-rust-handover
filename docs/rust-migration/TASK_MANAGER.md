# Task Manager Module Inventory

Captured: 2026-06-29 CEST.

This inventory starts Phase 9 by separating task-manager code that is plausibly
isolated from code that is directly tied to process creation, capability setup,
relocation, or loader behavior. It is not approval to rewrite taskman in Rust.
The current C taskman remains the only implementation.

## Build Boundaries

| Boundary | Files | Role | Rust posture |
| --- | --- | --- | --- |
| Portable taskman body | `libtaskman/include/*.h`, `libtaskman/src/*.c` | Freestanding archive linked into concrete taskmen. Contains parsers, path models, logging, credential policy, and relocation helpers. | Best place for host-tested pure logic, except relocation. |
| LQ rootserver | `lq/taskman/**` | seL4 initial user task, process/path/memory manager, syscall dispatcher, embedded boot CPIO owner. | Keep C while isolating smaller internal modules. |
| Embedded archive glue | `lq/taskman/Makefile`, generated `userland_archive.S`, `common/cpio.c` | Stages `modpkg.cpio` into `taskman.elf` and provides early `/sbin/init`. | Loader-adjacent; avoid early Rust changes. |

## Pure Logic And Diagnostic Candidates

These modules have bounded state or byte-level parsing that can be host-tested
before any image wiring. Some are still boot-observable, so "pure" here means
no direct seL4 object manipulation, not automatically low risk.

| Module | Files | Notes | Initial risk |
| --- | --- | --- | --- |
| CPIO archive model | `rust/crates/qsoe-tm-cpio`, `libtaskman/include/tm_cpio.h` | Pure `newc` walking, symlink resolution, directory iteration, and existence checks over caller-owned bytes. The C provider is retired; Rust `qsoe-tm-cpio` is mandatory and `QSOE_RUST_TM_CPIO=0` fails fast. See `TASK_MANAGER_CPIO.md`. | Medium: boot archive lookup is spawn-adjacent. |
| Shebang parser | `rust/crates/qsoe-tm-script`, `libtaskman/include/tm_script.h` | Single bounded parser used by `tm_spawn` when scripts are executed. The C provider is retired; Rust `qsoe-tm-script` is mandatory and `QSOE_RUST_TM_SCRIPT=0` fails fast. See `TASK_MANAGER_SCRIPT.md`. | Medium: pure parser but affects spawn fallback. |
| ELF view parser | `rust/crates/qsoe-tm-elf`, `libtaskman/include/tm_elf.h` | Read-only ELF64 program-header and interpreter parser. The C provider is retired; Rust `qsoe-tm-elf` is mandatory and `QSOE_RUST_TM_ELF=0` fails fast. See `TASK_MANAGER_ELF.md`. | High: pure parser, but used by relocation and loader flow. |
| Relocation walker | `rust/crates/qsoe-tm-reloc`, `libtaskman/include/tm_reloc.h` | Callback-driven RV64 relocation resolver and walker. The C provider is retired; Rust `qsoe-tm-reloc` is mandatory and `QSOE_RUST_TM_RELOC=0` fails fast. See `TM_RELOC_RUST_PROVIDER_PLAN.md` and `TASK_MANAGER_RELOC_RETIREMENT.md`. | High: pure walker, but it writes through spawn-owned callbacks into child images. |
| Syscfg TLV helpers | `rust/crates/qsoe-tm-syscfg`, `libtaskman/include/tm_syscfg.h` | Caller-owned TLV builder and walker. The C provider is retired; Rust `qsoe-tm-syscfg` is mandatory and `QSOE_RUST_TM_SYSCFG=0` fails fast. See `TASK_MANAGER_SYSCFG.md`. | Medium: platform data reaches early boot decisions. |
| FDT parser | `rust/crates/qsoe-tm-fdt`, `lq/taskman/sys/fdt.h` | Minimal big-endian device-tree scanner for `/chosen`, compatible strings, and properties. The C provider is retired; Rust `qsoe-tm-fdt` is mandatory in LQ taskman and `QSOE_RUST_TM_FDT=0` fails fast. See `TASK_MANAGER_FDT.md`. | Medium: boot config source. |
| Sysmap builder | `rust/crates/qsoe-tm-sysmap`, `lq/taskman/sys/sysmap.h` | Builds the read-only `PSYS` page mapped into children. The C provider is retired; Rust `qsoe-tm-sysmap` is mandatory in LQ taskman and `QSOE_RUST_TM_SYSMAP=0` fails fast. See `TASK_MANAGER_SYSMAP.md`. | Medium: child runtime metadata. |
| `/proc` model | `rust/crates/qsoe-tm-procfs`, `libtaskman/include/tm_procfs.h` | Formats `/proc/<pid>/info`, resolves paths, and walks pid directories through callbacks. | Low: retired Rust provider; diagnostic surface, no initial process creation. |
| `/proc` LQ glue | `lq/taskman/path/procfs.c`, `lq/taskman/path/procfs.h` | Connects the portable `/proc` model to LQ process-table accessors and connection context. | Low-medium: reads live process table but does not create caps. |
| `/sys` model | `rust/crates/qsoe-tm-sysfs`, `libtaskman/include/tm_sysfs.h` | Read-only file model for board, cmdline, osname, version, and builddate. The C provider is retired; Rust `qsoe-tm-sysfs` is mandatory and `QSOE_RUST_TM_SYSFS=0` fails fast. See `TASK_MANAGER_SYSFS.md`. | Medium: `/sys/cmdline` can influence init's mainfs path. |
| Path registry | `rust/crates/qsoe-tm-pathmgr`, `libtaskman/include/tm_pathmgr.h` | Fixed-pool namespace tree, path resolve, repath, symlink expansion, and child iteration. The C provider is retired; Rust `qsoe-tm-pathmgr` is mandatory and `QSOE_RUST_TM_PATHMGR=0` fails fast. See `TASK_MANAGER_PATHMGR.md`. | Medium-high: every open and device registration depends on it. |
| Credentials policy | `rust/crates/qsoe-tm-cred`, `libtaskman/include/tm_cred.h` | Pure cwd, umask, uid/gid mutation, and permission checks. The C provider is retired; Rust `qsoe-tm-cred` is mandatory and `QSOE_RUST_TM_CRED=0` fails fast. See `TASK_MANAGER_CRED.md`. | Low-medium: process semantics, not boot spawn. |
| Resource DB accounting | `rust/crates/qsoe-tm-rsrcdb`, `lq/taskman/sys/rsrcdb.h` | Fixed-pool resource-range allocation, split/merge, rollback on partial attach. The C provider is retired; Rust `qsoe-tm-rsrcdb` is mandatory and `QSOE_RUST_TM_RSRCDB=0` fails fast. See `TASK_MANAGER_RSRCDB.md`. | Low-medium: accounting table, but service-facing. |
| Simple pseudo-devices | `rust/crates/qsoe-tm-pseudodev`, `lq/taskman/sys/devnull.h`, `lq/taskman/sys/devzero.h` | Small read/write/stat handlers. The C providers are retired; Rust `qsoe-tm-pseudodev` is mandatory and `QSOE_RUST_TM_PSEUDODEV=0` fails fast. See `TASK_MANAGER_PSEUDODEV.md`. | Low-medium: simple, but served through taskman's IO path. |
| Logging formatter | `libtaskman/src/log.c`, `lq/taskman/tm_log.c` | Freestanding format subset and seL4 debug-console sink. | Low: diagnostic path, but useful during failures. |

The selected Phase 9 pilot candidate is the portable `/proc` model
(`tm_procfs`). See `TASK_MANAGER_PROCFS.md` for the scope exclusions and
evidence required before implementation.

Subsequent bounded providers now exist for `tm_cpio`, `tm_cred`, `tm_elf`,
`tm_fdt`, `tm_pathmgr`, LQ pseudo-devices, `tm_reloc`, `tm_rsrcdb`, `tm_script`,
`tm_syscfg`, `tm_sysmap`, and `tm_sysfs`. `tm_cpio`, `tm_script`, `tm_elf`,
`tm_fdt`, `tm_reloc`, `tm_syscfg`, `tm_sysmap`, `tm_sysfs`, `tm_cred`,
`tm_pathmgr`, `tm_pseudodev`, and `tm_rsrcdb` are retired to Rust. Keep broader
loader and authority-owning spawn changes separate from the retired `tm_elf`
and `tm_reloc` providers because their outputs still feed spawn, relocation,
and loader admission.

Multiple task-manager Rust providers can now be selected together. NQ/LQ
taskman links one shared `qsoe-tm-providers` static archive when any
`QSOE_RUST_TM_*` selector is enabled; the individual provider crates remain
`rlib` crates, and the shared archive owns the single no-std panic handler.
See `TASK_MANAGER_PROVIDERS.md` for the selector and evidence model.

## Spawn-Critical Paths

These paths are not early Rust candidates. They launch `/sbin/init`, load
additional images, or control process lifetime:

- `lq/taskman/main.c`: boot setup, primary endpoint creation, built-in path
  registrations, `/sbin/init` lookup, first `tm_spawn`, and the dispatch loop.
- `lq/taskman/proc/spawn.c`: script handling, filesystem image load, ELF
  segment mapping, dynamic-linker handling, initial stack, IPC buffer, TCB page,
  sysmap page, stdio caps, fault endpoint, scheduler context, and resume.
- `lq/taskman/proc/process.c`: `tm_process_create_by_name`,
  `tm_process_register`, pid allocation, wait/detach/terminate, process table,
  per-process untyped ownership, and teardown.
- `lq/taskman/path/cpiofs.c`: embedded archive lookup and read-only filesystem
  state used by spawn and early root paths.
- `lq/taskman/qsoe/process.c`: in-taskman `ProcessCreate`, `_exit`, detach,
  and wait wrappers.

## Capability-Critical Paths

These paths allocate, mint, copy, delete, move, map, or revoke seL4 objects and
must remain C until a dedicated boundary review exists:

- `lq/taskman/proc/process.c`: root CSpace slot allocator, per-process untyped
  pool, scheduling-context creation, reply objects, object CNode movement,
  process teardown, `dup` cap copy, and fault cleanup.
- `lq/taskman/proc/channel.c`, `connect.c`, `thread.c`, and `pulse.c`:
  endpoint/notification/TCB objects, badged send caps, direct-pulse
  notifications, worker threads, and channel queues.
- `lq/taskman/mem/mmap.c`: anonymous megapage allocation, physical-device
  mapping, munmap recycling, and mprotect/RELRO remapping.
- `lq/taskman/sys/irq.c`: IRQ handler and notification cap transfer.
- `lq/taskman/qsoe/state.c`, `msg.c`, `channel.c`, `connect.c`, `thread.c`,
  `time.c`, and `qsoe_invoke.h`: taskman-private syscall and invocation layer.
- `lq/taskman/sel4_syscalls.h` and `lq/taskman/sel4_types.h`: generated ABI
  and low-level seL4 call shapes.

## Relocation-Critical Paths

The bounded relocation walker is retired/default Rust, but the relocation
machinery remains load-bearing for dynamic userland startup because spawn still
owns target mappings, callbacks, ordering, and RELRO state:

- `rust/crates/qsoe-tm-reloc` and `libtaskman/include/tm_reloc.h`: RV64
  dynamic relocation walker, resolver setup, and callback-driven write path.
- `rust/crates/qsoe-tm-elf` and `libtaskman/include/tm_elf.h`: parser consumed
  by relocation setup in `tm_spawn`.
- `lq/taskman/proc/spawn.c`: `reloc_write_cb`, scratch mapping, libc/rtld/main
  relocation ordering, skipped-symbol logging, and RELRO tracking.

## Loader-Critical Paths

These pieces define how taskman itself starts and how each process image is
admitted into a child address space:

- `lq/taskman/start.S`: initial taskman entry.
- `lq/taskman/Makefile`: embedded `modpkg.cpio` archive generation and
  taskman link script posture.
- `lq/taskman/main.c`: bootinfo/FDT discovery, syscfg/sysmap build, CPIO setup,
  and initial `/sbin/init` spawn.
- `lq/taskman/sys/initrd.c`: parked FDT-driven initrd loader.
- `lq/taskman/proc/spawn.c`: PT_LOAD mapping, `PT_INTERP` handling,
  libc/rtld mapping, initial stack and auxv, thread register setup, and final
  `TCB_Resume`.

## Phase 9 Rule

For now, a task-manager Rust pilot must:

- be opt-in and leave the C taskman default intact;
- start from a pure or diagnostic module, preferably `tm_procfs`;
- have host fixtures before any guest image wiring;
- avoid new direct seL4 invocation code;
- avoid spawn, capability, loader, and authority-owning relocation paths;
- keep selected Rust providers packaged through one taskman Rust archive;
- keep boot smoke as the minimum image-level regression gate.
