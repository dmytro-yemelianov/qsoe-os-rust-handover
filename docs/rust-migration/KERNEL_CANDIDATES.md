# Kernel Rust Candidate Inventory

Captured: 2026-06-24 02:13 CEST.

This inventory identifies kernel-adjacent Rust candidates after decision
`D-021`. It is not approval to implement Rust in `nq`. The current C kernel
remains the only implementation and the rollback path is to keep it that way.

## Exclusion Gate

Any near-term candidate must exclude these paths:

| Exclusion | Kernel files or areas | Reason |
| --- | --- | --- |
| Traps | `nq/kernel/arch/riscv/trap.S`, `nq/kernel/arch/riscv/trap.c`, `nq/include/skimmer/trap*.h` | Trap entry, register save/restore, exception decoding, and panic recovery are early debug lifelines. |
| Context switching | `nq/kernel/arch/riscv/ctxswitch.S`, switching paths in `nq/kernel/lwkt/thread.c` | The switch path controls stack, register, and hart-local execution state. |
| Scheduler core | `nq/kernel/lwkt/thread.c`, `nq/kernel/kthread.c`, `nq/kernel/timer.c`, `nq/kernel/lwkt/ipiq.c`, scheduler-facing parts of `nq/kernel/sync.c` | Scheduler regressions are system-wide and hard to separate from Rust ABI issues. |
| Boot assembly and early mapping | `nq/kernel/arch/riscv/head.S`, `nq/kernel/main.c`, `nq/kernel/arch/riscv/pmap.c`, `nq/kernel/physmem.c`, integrated `nq/kernel/sysmap.c` wiring | Early boot code runs before normal diagnostics and before the memory model is fully established. |
| Low-level interrupt routing | `nq/kernel/intc.c`, `nq/kernel/intr.c`, `nq/kernel/intr_user.c`, `nq/kernel/arch/riscv/aia.c`, `aplic.c`, `imsic.c`, `plic.c` | Interrupt-controller setup is boot- and platform-critical. |
| User memory and syscall boundary | `nq/kernel/syscall.c`, `nq/kernel/arch/riscv/copyuser.S`, `nq/include/skimmer/copyuser.h` | User pointer validation and syscall dispatch are ABI-critical. |
| seL4 capability assumptions | QSOE/L task-manager and seL4 invocation paths, not `nq` kernel code | Kernel candidate work must not import QSOE/L capability or rootserver assumptions into `nq`. |

## Candidate Classes

These are safe only as documentation, host fixtures, or narrow helper
prototypes. None should be wired into the kernel image until `D-021` is
revisited and superseded.

| Candidate | Files | Allowed scope | Explicitly excluded | Initial posture |
| --- | --- | --- | --- | --- |
| Trace-ring formatting | `nq/kernel/trace_ring.c`, `nq/include/skimmer/trace_ring.h` | Render fixed trace entries into bounded text lines; map trace IDs to names in host tests. | `TRACE_FN`, per-hart ring writes, interrupt masking, SBI console writes, panic-time dump integration. | Best first prototype because the extractable logic is diagnostic formatting. |
| Queue invariant model | `nq/include/skimmer/queue.h` | Model intrusive tail-queue invariants in Rust tests or docs. | Replacing the C macros in kernel call sites. | Low-risk model, but not a linked replacement because the macros compile into many C sites. |
| Sysmap TLV encoder | `nq/kernel/sysmap.c`, `nq/include/skimmer/sysmap.h` | Bounded TLV size accounting and synthetic-record encoding tests. | Primary-hart boot call, FDT getters, `satp` or pmap mapping, panic-on-overflow behavior in live boot. | Useful later, but boot-adjacent and therefore not an early linked candidate. |
| Read-only FDT walker fixture | `nq/kernel/arch/riscv/fdt.c`, `nq/include/skimmer/fdt.h` | Standalone byte-slice walker over synthetic FDT blobs, including endian and property bounds checks. | Cached global topology, PLIC/IMSIC/APLIC selection, physmem/initrd side effects, mandatory boot-platform decisions. | Parser-like, but high leverage in early boot, so host fixture only. |
| Sysinfo record formatting | `nq/kernel/sysinfo.c` | Public record layout, windowing, and fixed-size name-copy behavior over synthetic records. | Walking live thread, interrupt, timer, physical-page, or CPU tables; `copy_to_user`; `TM_PRIV_SYSINFO` dispatch. | Diagnostic surface, but direct kernel integration touches scheduler and user-copy state. |

## Ranked Next Step

If Phase 10 later needs a concrete prototype, use this order:

1. Trace-ring formatting fixture.
2. Queue invariant model.
3. Sysmap TLV encoder fixture.
4. Sysinfo record-format fixture.
5. Read-only FDT walker fixture.

The first two are preferred because they can stay entirely outside the boot
path. `sysmap`, `sysinfo`, and FDT work should remain fixtures until the project
has stronger task-manager and default-Rust evidence.

## Non-Candidates

These areas are not candidates under the current decision:

| Area | Files | Reason |
| --- | --- | --- |
| Boot entry | `nq/kernel/arch/riscv/head.S`, early `nq/kernel/main.c` | Runs before normal diagnostics and establishes hart startup state. |
| Context switch and scheduler | `nq/kernel/arch/riscv/ctxswitch.S`, `nq/kernel/lwkt/thread.c`, `nq/kernel/kthread.c` | Controls runnable state, stack switching, and priority behavior. |
| Trap handling | `nq/kernel/arch/riscv/trap.S`, `nq/kernel/arch/riscv/trap.c` | Trap correctness is required for faults, syscalls, interrupts, and panic diagnosis. |
| Syscall dispatch and user copy | `nq/kernel/syscall.c`, `nq/kernel/arch/riscv/copyuser.S` | Defines the user/kernel ABI and memory safety boundary. |
| Memory management | `nq/kernel/arch/riscv/pmap.c`, `nq/kernel/vspace.c`, `nq/kernel/physmem.c` | Mapping, address-space, and physical-memory regressions are boot- and data-corrupting. |
| Interrupt controllers | `nq/kernel/intc.c`, `nq/kernel/intr.c`, `nq/kernel/intr_user.c`, `nq/kernel/arch/riscv/aia.c`, `aplic.c`, `imsic.c`, `plic.c` | Platform interrupt routing is hardware-sensitive and tightly coupled to boot topology. |
| Process, sync, and message core | `nq/kernel/proc.c`, `nq/kernel/sync.c`, `nq/kernel/lwkt/msgport.c` | These are central process and IPC semantics, not bounded helper logic. |
| Timer and clock core | `nq/kernel/timer.c`, `nq/kernel/clock.c`, `nq/kernel/arch/riscv/timer.c` | Timer behavior feeds scheduling, sleeps, and user-visible clock state. |

## Review Result

The only acceptable Phase 10 kernel work is documentation and fixture design.
All listed candidates preserve the current C implementation and explicitly
exclude traps, context switching, scheduler core, boot assembly, live interrupt
routing, user-copy/syscall paths, and QSOE/L seL4 capability assumptions.
