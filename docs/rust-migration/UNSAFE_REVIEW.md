# Unsafe Code Review Checklist

Captured: 2026-06-24 02:34 CEST.

Use this checklist for any Rust migration PR that adds or changes unsafe Rust,
FFI declarations, raw pointer handling, MMIO, DMA, global mutable state, or
C/Rust ABI boundaries. If a PR has no new unsafe surface, say that explicitly
in the PR body.

## PR Body Requirement

Every Rust migration PR should include one of these statements:

```text
Unsafe review: no new unsafe code or FFI boundary changes.
```

or:

```text
Unsafe review: see docs/rust-migration/UNSAFE_REVIEW.md checklist summary.
- Unsafe sites changed:
- Invariants:
- Tests/audits:
- Residual risk:
```

## Inventory

Before review, list every changed site matching these categories:

- `unsafe` blocks and expressions;
- `unsafe fn`;
- `unsafe impl`;
- `unsafe extern "C"` declarations or callbacks;
- `UnsafeCell`, mutable statics, or global interior mutability;
- raw pointer creation, arithmetic, dereference, or cast;
- `from_raw_parts`, `from_raw_parts_mut`, `from_bytes_with_nul_unchecked`, or
  similar unchecked constructors;
- volatile MMIO reads or writes;
- DMA buffers or physical-address handoff;
- `repr(C)` structs, unions, function pointers, or layout-sensitive enums;
- panic handlers or code that can panic across a C-facing boundary.

Useful inventory command:

```sh
rg -n 'unsafe|extern "C"|UnsafeCell|from_raw|read_volatile|write_volatile|repr\(C\)' rust -g '*.rs'
```

## Required Checks

For each unsafe site, record the invariant in a nearby `SAFETY:` comment and
verify the relevant items below.

| Area | Checklist |
| --- | --- |
| Ownership | The code states which side owns each pointer, handle, buffer, descriptor, or callback and when ownership transfers. |
| Lifetime | Borrowed memory cannot outlive the C call, resource-server callback, DMA window, or MMIO mapping that created it. |
| Nullability | Null pointers are either rejected before use or documented as unsafe caller preconditions matching the C ABI. |
| Bounds | Every raw buffer has a length/capacity proof before reads or writes. Integer offset arithmetic is checked or bounded by construction. |
| Alignment | Pointer casts and `repr(C)` views prove alignment, size, and field layout. Layout tests cover cross-language structs. |
| Aliasing | Mutable aliases are ruled out, or the single-owner/single-thread condition is stated and tested where practical. |
| Initialization | Memory is initialized before it is read, including C output structs, DMA rings, descriptor tables, and reply buffers. |
| Volatile/MMIO | MMIO access goes through a reviewed wrapper. Rust references are not created to device registers. Required ordering is explicit. |
| DMA | Physical and virtual addresses, cache/coherency assumptions, descriptor ownership, and device-readable/writable direction are documented. |
| Concurrency | `unsafe impl Sync` and global mutable state have a concrete single-thread, interrupt, or locking proof. Reentrancy is considered. |
| FFI ABI | Symbol names, calling convention, integer widths, struct layout, and error mapping match the existing C boundary. |
| Panic behavior | Unsafe paths do not unwind across C. Panics are either impossible by construction or mapped to the component's reviewed panic/abort policy. |
| Runtime assumptions | The code does not introduce heap, TLS, unwinding, hosted `std`, or unsupported compiler-runtime references unless separately approved. |
| Rollback | The C implementation or previous safe path remains available until the relevant retirement gate is satisfied. |

## Evidence Required

Unsafe review is incomplete without evidence. Use the smallest set that proves
the changed boundary:

- host tests for pure parsers, layout, state machines, descriptor ownership, or
  error mapping;
- `cargo fmt`, `cargo clippy`, and package tests through the normal Rust gate;
- Miri when the code is host-executable and Miri supports the relevant unsafe
  pattern;
- fuzz smoke for parser changes;
- strict ELF artifact audit for any QSOE-linked Rust binary;
- QEMU boot or targeted smoke for any image-visible change.

If a tool cannot run locally, note why and state which remaining check should
run before default selection or release.

## Review Result

At the end of review, classify the unsafe change:

| Result | Meaning |
| --- | --- |
| Accepted | Invariants are documented, evidence passed, and rollback remains available. |
| Accepted with follow-up | The change is safe for the current opt-in scope, but a listed follow-up is required before default selection. |
| Deferred | The unsafe boundary is too broad, lacks evidence, or touches excluded paths. Keep the C implementation/default. |

No unsafe review can approve work that is explicitly out of scope in
`RETIREMENT.md`, `TASK_MANAGER.md`, `TASK_MANAGER_PROCFS_BOUNDARY.md`,
`KERNEL_CANDIDATES.md`, or `KERNEL_ARTIFACT_AUDIT.md`.
