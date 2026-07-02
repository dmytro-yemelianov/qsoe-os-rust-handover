# Spawn/capability/relocation/loader boundary review

Issue: #154

Status: boundary-reviewed; bounded `tm_reloc` provider retired/default Rust,
broader spawn, capability, VSpace, loader, mmap, IRQ, and teardown ownership
still deferred.

## Decision

Do not start a Rust implementation for the spawn, capability, relocation, or
loader path as one component.

The current LQ path is not a single parser-like boundary. It is a critical
state machine that combines process creation, CSpace/VSpace construction,
untyped-object accounting, ELF loading, dynamic-linker preload, relocation
writes into a child address space, argument transfer, scheduling-context setup,
IRQ-capability minting, mmap/device-frame ownership, and teardown ordering.

The next safe milestone is evidence and seam extraction, not replacement.

## Reviewed files

- `lq/taskman/main.c`
- `lq/taskman/proc/spawn.c`
- `lq/taskman/proc/process.c`
- `lq/taskman/mem/mmap.c`
- `lq/taskman/sys/irq.c`
- `rust/crates/qsoe-tm-reloc`
- `libtaskman/include/tm_reloc.h`
- `libtaskman/include/tm_seams.h`

## Current boundary shape

### Dispatch and process creation

`lq/taskman/main.c` owns the taskman request dispatcher. It routes process,
memory, resource, IRQ, and path-manager requests from the seL4 IPC boundary to
the implementation modules.

`lq/taskman/proc/process.c` resolves names through cpiofs or mounted fs-qrv,
allocates a PID, brackets spawn-time retypes with per-process untyped staging,
calls `tm_spawn(...)`, and transfers staged untyped blocks into the registered
process record.

This path is load-bearing because a spawn failure must preserve PID, untyped,
slot, and filesystem-buffer ownership invariants.

### Spawn and loader

`lq/taskman/proc/spawn.c` is the high-risk center. It currently owns:

- shebang handling through the shared `tm_script_parse_shebang(...)` seam
- ELF header and program-header checks
- child CNode, VSpace, TCB, page-table, stack, TLS, sysmap, and auxv setup
- ET_EXEC main-image loading
- dynamic-linker and libc preload for PT_INTERP images
- relocation application through `tm_reloc_apply(...)`
- RELRO tracking for later `mprotect(...)`
- argument-page readback from the caller process
- final process registration and initial TCB configuration

This file is not a Rust-default candidate until these responsibilities are
split into smaller seams with independent evidence.

### Relocation

The retired/default Rust `qsoe-tm-reloc` provider is the completed clean seam in
this area:

- it is pure byte-level logic over `tm_elf_view_t`
- target-memory writes go through `tm_reloc_write_q_fn`
- unresolved-symbol logging goes through `tm_reloc_skip_log_fn`
- NQ and LQ can provide different write callbacks without changing the walker

This completed provider does not change the decision for the surrounding
spawn/loader system. Spawn still owns child VSpace mappings, scratch writes,
dynamic-loader ordering, RELRO tracking, process-table publication, and
capability ownership. Further work must not bundle relocation with spawn or
VSpace authority.

### Capability and process lifetime

`lq/taskman/proc/process.c` owns process records, PID allocation, taskman/root
slot allocation, child slot allocation, per-process untyped staging, scheduling
contexts, reply objects, wait/detach, credential/cwd state, and termination.

The termination order is part of the ABI:

- worker TCBs and notifications before owned channels
- client connections before main TCB/VSpace teardown
- child CSpace clearing before CNode teardown
- mmap, device-frame, RELRO, and per-process untyped reclamation after VSpace
  teardown
- zombie retention only when a live parent can reap status

Rust code must not own this ordering until there is a typed teardown model and
cap-leak evidence that covers every resource class.

### Mmap, physical memory, and device frames

`lq/taskman/mem/mmap.c` owns:

- anonymous Mega_Page allocation and recycling
- per-process mmap frame tracking
- MAP_PHYS device-untyped discovery and high-water accounting
- shared device-frame registry and per-process copied frame caps
- `munmap(...)`, `mprotect(...)`, and `alloc_phys(...)` service paths

This area is coupled to spawn because argument pages, RELRO pages, and image
frames are later resolved through process-owned tracking tables. It should stay
C-owned until the frame ownership model is explicitly typed and tested.

### IRQ capabilities

`lq/taskman/sys/irq.c` owns IRQ handler creation/binding and notification caps
returned into the caller CSpace.

This is capability-authority work. It can share validation policy later, but it
should not be part of an initial Rust spawn/loader milestone.

## Non-goals for the next implementation milestone

- Do not replace `tm_spawn(...)`.
- Do not move child CSpace or VSpace construction into Rust.
- Do not move process teardown ordering into Rust.
- Do not make Rust own seL4 untyped allocation, object retype, or slot reuse.
- Do not combine relocation, spawn, mmap, and IRQ migration in one PR.
- Do not expose raw seL4 capability authority to Rust before a typed seam exists.

## Required seams before any Rust ownership

Any future implementation must first create C-owned seams with narrow typed
inputs and explicit rollback/evidence:

- `tm_spawn_plan`: parsed, immutable load plan for main image, interpreter,
  libc, rtld, stack, TLS, sysmap, auxv, and RELRO ranges.
- `tm_spawn_argpack`: bounded argv/envp/auxv copy and validation result
  independent of child memory writes.  This is now a C-owned planning seam
  evidenced by `spawn-argpack-c-evidence`; the child stack writer remains C
  authority code.
- `tm_reloc_provider`: pure relocation walk result or callback-compatible
  relocation writer, isolated from spawn.
- `tm_cap_plan`: declarative list of object creates, cap mints/copies/moves,
  rights, badges, destination CSpaces, and cleanup edges.  The first C-owned
  seam now covers child CSpace publication for taskman endpoint, child untyped,
  CNode self, and stdio connection caps; `spawn-cap-plan-c-evidence` keeps
  authority-owned commit in C.
- `tm_vspace_plan`: declarative list of page-table and frame mappings with
  rights/attributes.
- `tm_teardown_plan`: explicit reverse-order resource graph for process exit.

These seams must keep C as the seL4 authority owner until the relevant plan is
validated and committed.

## Evidence gates for future work

Before moving any subcomponent from deferred to opt-in:

- Add host fixtures for the pure parser/planner surface.
- Add LQ boot smoke that spawns `/sbin/init`, at least one dynamic user binary,
  and at least one script path.
- Add cap-leak evidence before and after repeated spawn/exit cycles.
- Add failure-path evidence for bad ELF, missing interpreter, relocation skip,
  low-memory object allocation failure, and argument-page failure.
- Add `QSOE_RUST_* = 0` fallback proof for every opt-in Rust provider.
- Keep CodeQL and the full QSOE CI job green on PR and post-merge main.

## Recommended next submilestones

1. Keep `tm_spawn_argpack` source evidence running next to the current
   spawn/loader runtime evidence.
2. Keep `tm_cap_plan` source evidence running next to argpack and spawn/loader
   runtime evidence while follow-on cap/object relocation seams stay C-only.
3. Keep the now-retired/default `qsoe-tm-reloc` provider isolated behind the
   existing callback ABI.
4. Reassess spawn planning after the C plan seams are stable.

## Roadmap posture

#154 should remain open and `deferred` after this review. The completed
milestone is the boundary review itself, not implementation readiness.

### tm_vspace_plan and tm_teardown_plan C seams

The 2026-07-02 follow-up splits two more authority boundaries out of ad-hoc spawn and teardown control flow:

- `tm_vspace_plan` is a bounded C-owned plan for page-table and page mappings. Preparation records the intended operation kind, cap, virtual address, rights, attributes, and cap-recording policy; commit still performs `qsoe_riscv_pagetable_map`, `qsoe_riscv_page_map`, `spawn_record_pt`, and `spawn_record_frame` in C.
- `tm_teardown_plan` is a bounded C-owned plan for revoke/delete/free cleanup. Preparation records the cleanup kind and slot pointer; commit still performs `qsoe_cnode_revoke`, `qsoe_cnode_delete`, and `taskman_free_slot` in C while preserving the process teardown order.

Formal evidence targets now cover both seams with `make spawn-vspace-plan-c-evidence` and `make teardown-plan-c-evidence`. The next useful split is loader relocation and protocol-shape state, because the current page-table, cap-publication, argpack, and teardown authority boundaries are now separately replayable through component patches.
