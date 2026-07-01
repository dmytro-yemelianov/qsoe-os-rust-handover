# QSOE Rust Migration Specification

## Purpose

This document defines the technical contract for introducing Rust into QSOE
without destabilizing the current boot path, userland ABI, loader behavior, or
source build. Rust is treated as an incremental implementation language behind
existing QSOE interfaces, not as a replacement architecture.

## Goals

- Improve maintainability in code with explicit ownership, parsing, resource
  lifetime, and protocol/state-machine complexity.
- Improve memory safety where Rust can eliminate unchecked pointer arithmetic,
  buffer indexing errors, use-after-free risks, and ad hoc lifetime conventions.
- Keep QSOE bootable after every migration step.
- Preserve existing C-facing ABI unless an ABI change is explicitly designed,
  documented, and migrated across all callers.
- Make every Rust artifact auditable at the ELF and relocation level before it
  is admitted into an image.
- Build a repeatable migration path that can start with low-risk host tools and
  userland servers, then graduate to deeper runtime pieces only after evidence.

## Non-goals

- No wholesale rewrite of QSOE.
- No early rewrite of the Skimmer kernel, seL4 boot integration, task manager
  process loader, dynamic linker, libc startup path, or shell.
- No dependency on the Rust standard library inside QSOE userland or kernel
  code.
- No assumption that Rust can use the host Linux target unchanged for QSOE
  binaries.
- No new syscall or IPC ABI solely to make a first Rust pilot easier.

## Current Boundaries

The initial source tree is organized around these implementation boundaries:

- `common`: shared boot and layout support.
- `libtaskman`: task-manager support and ELF relocation handling.
- `libc`: C runtime, syscall wrappers, dynamic loader support, and public
  headers.
- `lq`: seL4-facing low-level QSOE layer and task manager.
- `nq`: Skimmer kernel.
- `quser`: userland commands, services, resource servers, drivers, tests, and
  shell.

The public userland ABI is centered on `libc/include/sys/qsoe.h`. Resource
servers use `quser/ressrv/include/ressrv.h`. The userland build contract is in
`quser/common.mk`.

## Hard Constraints

### ABI

- Rust code must preserve exported symbol names, calling convention, integer
  widths, struct layout, alignment, and error behavior for any C-facing
  boundary.
- All cross-language structs must be `#[repr(C)]`.
- No Rust enum may cross a C ABI boundary unless represented by an explicit
  integer type and documented.
- Pointers received from C or kernel-facing APIs are unsafe inputs. Rust wrappers
  must validate nullability, length, ownership, and aliasing assumptions before
  exposing safe APIs.

### Runtime

- QSOE Rust userland must be `no_std` by default.
- Panic strategy must be `abort`.
- Unwinding is forbidden.
- Thread-local storage is forbidden until loader support is explicitly audited.
- Allocator use is forbidden in first pilots unless the selected component
  already has a documented heap contract and the allocator path is tested.
- Rust code must not assume POSIX behavior beyond what QSOE libc actually
  provides.

### Linking And Loader

The current userland link path uses:

- QSOE `crt0.o`.
- QSOE `libc.so`.
- `/lib/ld-qsoe.so.1`.
- `-nostdlib`.
- ET_EXEC output.
- No PIE.
- Eager binding.

Rust binaries and libraries must fit this contract unless a dedicated loader
upgrade project changes it.

`libtaskman/include/tm_reloc.h` currently documents support for:

- `R_RISCV_RELATIVE`.
- `R_RISCV_64`.
- `R_RISCV_JUMP_SLOT`.

Every Rust-generated ELF must be audited for relocation types, dynamic tags,
sections, TLS, unwind tables, and unsupported compiler runtime references.

### Build

- Rust integration must not require a working network during normal builds.
- Toolchain versions must be pinned.
- Build artifacts must remain reproducible enough for release packaging.
- The default C build must continue to work while Rust pilots are optional.
- Any required Rust target JSON, linker wrapper, or cargo config must live in
  the source tree.

### Testing

Every migrated component needs:

- A C implementation kept available until the Rust replacement has passed the
  same image-level checks.
- Unit or host-side tests for pure parsing and state transitions where feasible.
- In-guest smoke coverage through existing QSOE tests or new small commands.
- Boot verification through QEMU.
- Artifact inspection before image inclusion.

## Migration Model

Each Rust migration must follow this sequence:

1. Describe the C component behavior and external interfaces.
2. Add focused tests or fixtures around existing behavior.
3. Introduce Rust behind the same boundary.
4. Build the Rust artifact outside the default boot image first.
5. Audit the artifact.
6. Add opt-in image integration.
7. Compare C and Rust behavior.
8. Flip the default only after a release candidate period.
9. Remove the C implementation only after rollback is no longer needed.

## Preferred First Targets

### Host Tools

Host tools are the lowest-risk starting point because they do not run inside
QSOE and can be validated against generated images. The qrvfs inspector and
writer have completed this path and are now retired-C Rust host tools:

- Rust `mkfs-qrv-rs` and `qrvfs-tree` for qrvfs images.
- Remaining C/Python host tools such as `host_tools/mkgpt.py` and
  `boot/gptextract.py`.

Host-tool Rust ports should share parser and serializer crates that can later be
adapted to `no_std` where practical.

### Userland Service: slogger

`quser/sbin/slogger/main.c` is the preferred first in-guest Rust pilot because
it is small, IPC-oriented, and hardware-independent.

The Rust version must:

- Preserve `/dev/slog` behavior.
- Preserve message receive loop behavior.
- Preserve ring size and overflow semantics unless explicitly changed.
- Run without heap in the first version if feasible.
- Be swappable with the C implementation through a build flag.

### Resource Server Bindings

`quser/ressrv/include/ressrv.h` is a good early boundary for safe Rust wrappers.

The first Rust crate should expose:

- Raw FFI bindings.
- Safe wrappers for registration, message receive, reply, and resource lifetime.
- Explicit ownership rules for channels, handles, and buffers.
- Small C compatibility examples.

### Driver Pilot: devb-virtio

`devb-virtio-rs` completed the driver pilot and now replaces the retired C
`quser/dev/virtio` implementation in tracked NQ/LQ images. It exercises MMIO,
DMA-like memory sharing, queue state, interrupts, and resource-server behavior.

The Rust version must keep unsafe code localized around:

- MMIO register access.
- Queue descriptor memory.
- Device configuration structures.
- Interrupt entry points.
- FFI calls to QSOE libc and resource-server APIs.

## Components To Defer

These components should not be early Rust targets:

- `libc`: too central to process startup, loader behavior, and ABI stability.
- `ld-qsoe`: relocation and dynamic-linking behavior must be stable before Rust
  can safely depend on it.
- `qsh`: large, user-facing, and parser-heavy, but too broad for a first pilot.
- Spawn and process-loader paths in `libtaskman` and `lq`: high blast radius.
- Skimmer scheduler, traps, context switching, and seL4 capability management:
  require a separate proof plan after userland evidence.

## Preflight Requirements

Before implementing Rust userland, complete these preflights:

- Record exact boot commands and expected console milestones.
- Add a QEMU boot smoke script that detects login prompt readiness.
- Add an artifact inspection script for ELF class, machine, type, interpreter,
  dynamic tags, relocations, TLS, unwind metadata, and undefined symbols.
- Inventory QSOE libc functions used by each candidate component.
- Inventory unsafe C idioms in candidate components.
- Record current image layout and installed file paths.
- Document host dependencies for macOS and Debian/Ubuntu/container builds.
- Decide the first supported Rust compiler version.

## Rust Crate Layout

Recommended initial layout:

```text
rust/
  README.md
  rust-toolchain.toml
  .cargo/config.toml
  targets/
    riscv64-qsoe-user.json
  crates/
    qsoe-abi/
    qsoe-ffi/
    qsoe-ressrv/
    qsoe-slogger/
    qrvfs/
    qsoe-host-image/
  bins/
    slogger-rs/
```

Crate intent:

- `qsoe-abi`: shared constants and `#[repr(C)]` data structures.
- `qsoe-ffi`: raw extern bindings to QSOE libc and system calls.
- `qsoe-ressrv`: safe wrappers around resource-server APIs.
- `qsoe-slogger`: no-std ring-buffer logic for the Rust `slogger` pilot.
- `qrvfs`: parser and image metadata code, designed for host tests first.
- `qsoe-host-image`: host-side image construction/checking utilities.
- `slogger-rs`: first in-guest service pilot.

## Unsafe Code Policy

- Every `unsafe` block must have a short invariant comment.
- Unsafe operations must be concentrated in FFI, MMIO, and raw-buffer modules.
- Public safe APIs must not expose undefined behavior when called with safe Rust.
- No `static mut` unless there is no practical alternative and access is
  externally synchronized or single-threaded by construction.
- Volatile MMIO access must use typed wrappers, not scattered raw pointer reads
  and writes.
- Rust migration PRs must reference `UNSAFE_REVIEW.md` with either a completed
  checklist summary or an explicit "no new unsafe code" statement.

## Acceptance Standard

A Rust component is acceptable when:

- The C behavior it replaces is documented.
- The artifact passes the ELF audit.
- The image boots to the same expected milestone.
- Existing in-guest tests still pass.
- The component has at least one targeted smoke test or fixture.
- Rollback to the C implementation is one build flag away.
- Unsafe code is reviewed and isolated.
- Build instructions work on the supported host environment.
