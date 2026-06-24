# Kernel Rust Artifact Audit Needs

Captured: 2026-06-24 02:17 CEST.

This document defines what must be audited before any future Rust object is
linked into the Skimmer kernel. It does not approve kernel Rust implementation.
Decision `D-021` still keeps `nq` Rust work limited to documentation and
fixtures.

## Current Kernel Link Contract

The current NQ kernel is built by `nq/Makefile` as a freestanding static RISC-V
kernel:

- compile flags include `-ffreestanding`, `-fno-builtin`, `-nostdinc`,
  `-fno-stack-protector`, `-fno-pic`, `-mcmodel=medany`,
  `-march=rv64imac_zicsr_zifencei_zicntr`, and `-mabi=lp64`;
- link flags include `-nostdlib`, `-static`, `-no-pie`, and
  `-T kernel/arch/riscv/kernel.ld`;
- the linker script keeps the kernel load address at `0x80200000` while
  resolving symbols at the high-half virtual address;
- live sections are expected to be covered by `.text`, `.rodata`, `.data`, and
  `.bss`, with `.note`, `.comment`, `.eh_frame`, and `.riscv.attributes`
  discarded;
- the build emits both `kernel/arch/riscv/skimmer` and
  `kernel/arch/riscv/skimmer.bin`.

The existing `rust/targets/riscv64-qsoe-user.json` is a userland target and is
not suitable as-is for kernel Rust: it uses the QSOE userland link posture,
dynamic-linking assumptions, PIC relocation model, and `lp64d` ABI.

## Audit Inputs

A future kernel Rust audit must inspect both the Rust-produced object or
staticlib and the final linked kernel ELF. Inspecting only the final ELF is not
enough because the linker script may discard sections that still prove the Rust
artifact was built with the wrong runtime assumptions.

Required inputs:

- exact `rustc`, Cargo, linker, binutils, and target specification versions;
- Rust compile flags, target JSON, and any `RUSTFLAGS`;
- the Rust `.o` file or staticlib member list before final kernel linking;
- the final `nq/kernel/arch/riscv/skimmer` ELF;
- the generated `skimmer.bin`;
- a linker map file for the Rust-enabled build.

## Codegen Assumptions

The audit must prove the Rust codegen matches the current C kernel posture:

- RISC-V ISA and ABI match the kernel: `rv64imac_zicsr_zifencei_zicntr`,
  `lp64`, no floating-point ABI, and `medany`;
- no PIC, PIE, dynamic linking, PLT, GOT, interpreter, or dynamic section;
- `no_std`, no default allocator, no `std`, and no unreviewed `alloc`;
- `panic = "abort"` and no unwinding;
- no stack protector, sanitizer, coverage, profiling, global constructor, or
  thread-local storage assumptions;
- no red-zone assumption;
- atomics and CSR usage match the kernel's existing RISC-V feature set and
  interrupt discipline;
- compiler-emitted helper calls are either absent or explicitly resolved to
  reviewed kernel-local implementations.

## Section Audit

Allowed allocated sections in linked kernel Rust code are:

- `.text` and `.text.*`;
- `.rodata` and `.rodata.*`;
- `.srodata` and `.srodata.*`;
- `.data` and `.data.*`;
- `.sdata` and `.sdata.*`;
- `.bss` and `.bss.*`;
- `.sbss` and `.sbss.*`.

The audit must flag these sections in Rust inputs or the final ELF unless a
later design explicitly approves them:

- `.eh_frame`, `.eh_frame_hdr`, `.gcc_except_table`, `.debug_frame`;
- `.tdata`, `.tbss`, and any section with TLS flags;
- `.init_array`, `.fini_array`, `.preinit_array`, `.ctors`, `.dtors`;
- `.got`, `.got.*`, `.plt`, `.plt.*`;
- `.dynamic`, `.dynsym`, `.dynstr`, `.interp`;
- `.rela.*`, `.rel.*`, or any relocation section in the final static kernel;
- unexpected allocated orphan sections not named in `kernel.ld`.

The audit should be strictest on input Rust objects. A final ELF that silently
discards `.eh_frame` still fails the audit unless the input object was reviewed
and the section is proven inert.

## Linker Script Compatibility

A future Rust-enabled kernel link must preserve the current linker-script
contract:

- `ENTRY(_start)` remains owned by boot assembly;
- `_kernel_start`, `_text_start`, `_rodata_start`, `_data_start`, `_bss_start`,
  `_bss_end`, and `_kernel_end` keep their meanings;
- Rust sections do not change the load-memory-address and
  virtual-memory-address relationship documented in `kernel.ld`;
- no Rust symbol depends on relocations that survive into the final static ELF;
- no Rust object introduces unresolved weak runtime hooks that only work in a
  hosted environment;
- `.text.boot` stays assembly-owned and first in `.text`;
- `skimmer.bin` remains a valid raw binary for the existing QEMU/OpenSBI boot
  path.

The future audit command should fail on linker orphan warnings, unresolved
symbols, dynamic program headers, unexpected writable/executable segments, and
any final relocation records.

## Panic Behavior

Kernel Rust panic behavior requires a separate review before any link:

- Rust must not unwind across C or assembly frames;
- no `eh_personality`, unwind tables, or landing pads may be present;
- the panic handler must be explicit, reviewed, and bounded;
- panic output must not allocate, acquire scheduler locks, or rely on userland
  resource servers;
- panic paths reachable from trap, interrupt, or context-switching code remain
  forbidden under `KERNEL_CANDIDATES.md`;
- fallible helper logic should return C-compatible status values rather than
  panicking across the C ABI.

If the selected Rust candidate is expected never to panic in kernel context,
the audit must still verify that bounds checks, formatting, and option/result
unwrapping do not pull in unreviewed panic formatting paths.

## Forbidden Runtime References

The audit must reject unresolved or unexpected references to hosted Rust or C
runtime support, including:

- `std` and OS runtime entry points;
- allocator symbols such as `__rust_alloc`, `__rust_dealloc`,
  `__rust_realloc`, `__rust_alloc_zeroed`, and OOM hooks;
- unwind symbols such as `rust_eh_personality` and language-specific
  personality routines;
- dynamic loader symbols, PLT stubs, or interpreter metadata;
- libc calls outside the kernel's reviewed freestanding support surface;
- compiler helper routines for arithmetic, memory, atomics, or floating point
  unless each helper is deliberately provided by the kernel build.

`memcpy`, `memset`, `memmove`, and `memcmp` are not automatically safe just
because similarly named C functions exist. Any emitted reference must resolve
to the intended kernel-local implementation and match the freestanding calling
contract.

## Minimum Future Report

A future kernel Rust artifact audit report must include:

- target and flag summary;
- `readelf -h`, `readelf -l`, `readelf -S`, and `readelf -r` for Rust inputs
  and the final kernel ELF;
- `nm -u` or equivalent unresolved-symbol output;
- a sorted list of global Rust symbols exported into the kernel;
- linker map excerpts showing where Rust sections landed;
- the generated `skimmer.bin` size and hash;
- the boot command and result used to prove the C rollback path still works.

Until such a report exists and `D-021` is superseded, no Rust object should be
linked into `nq`.
