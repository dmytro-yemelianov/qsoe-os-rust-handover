# `tm_reloc` C Provider Retirement

Captured: 2026-07-01 CEST.

The bounded RV64 relocation walker is now a retired task-manager provider.
Normal NQ/LQ taskman links use Rust `qsoe-tm-reloc` through the shared
`qsoe-tm-providers` archive, and the C implementation is removed from the
tracked portable taskman source.

## Scope

- Removed C provider: `libtaskman/src/reloc.c`
- Preserved C ABI: `libtaskman/include/tm_reloc.h`
- Rust provider: `rust/crates/qsoe-tm-reloc`
- Shared archive: `build/rust/tm-providers/libqsoe_tm_providers.a`
- Focused evidence: `make tm-reloc-provider-evidence`

This retirement covers only the callback-driven relocation resolver and walker
behind `tm_reloc_init_resolver(...)` and `tm_reloc_apply(...)`. It does not move
spawn orchestration, ELF segment mapping, dynamic-loader admission, child VSpace
mapping, capability publication, process-table mutation, mmap, IRQ ownership, or
teardown ordering out of C.

## Selector Posture

```text
QSOE_RUST_TM_RELOC=1  -> required; links Rust qsoe-tm-reloc
QSOE_RUST_TM_RELOC=0  -> rejected after C tm_reloc retirement
```

The top-level and `libtaskman` Makefiles fail fast when the stale C selector is
requested. `libtaskman.a` must not contain `reloc.o` in retired/default links.

## Evidence

Retirement validation is captured by `scripts/tm-reloc-provider-evidence.sh`.
The script:

- runs Rust host parity tests for `qsoe-tm-reloc`;
- audits the Rust static provider archive for soft-float RVC members and the
  exported `tm_reloc_apply` / `tm_reloc_init_resolver` ABI;
- rejects `QSOE_RUST_TM_RELOC=0` for portable `libtaskman` and LQ taskman;
- builds LQ with default Rust `tm_reloc`;
- verifies LQ `libtaskman.a` has zero C `reloc.o` members;
- verifies LQ `taskman.elf` links the Rust relocation ABI symbols;
- boots QSOE/L and requires libc.so, rtld, and main relocation logs on the
  dynamic ELF spawn path;
- rejects current relocation and spawn failure diagnostics in the boot log.

Recorded trusted evidence:

- PR #238 introduced the Rust provider and opt-in/runtime evidence.
- PR #239 retired the C provider and made `QSOE_RUST_TM_RELOC=1`
  default/required.
- PR #239 QSOE CI passed: run `28548356058`.
- PR #239 CodeQL passed: run `28548355915`.
- Main CI after #239 passed: run `28548857438`.
- Main CodeQL after #239 passed: run `28548857474`.
- Roadmap Pages after #239 passed: run `28548857450`.

## Current Rollback

There is no C `tm_reloc` rollback target after retirement. If a future issue is
found, the rollback is a normal source revert of the retirement PR, not a build
selector. Broader spawn, capability, loader, and VSpace authority remain C-owned
and continue to provide the containment boundary around the Rust relocation
provider.
