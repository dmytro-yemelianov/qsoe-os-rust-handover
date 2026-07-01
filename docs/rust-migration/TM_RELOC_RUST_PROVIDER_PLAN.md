# `tm_reloc` Rust-provider completion note

Status: retired/default Rust provider; broader spawn, capability, and loader
ownership remains deferred.

This note records the first completed Rust-provider subcandidate inside the
spawn, capability, relocation, and loader roadmap item. It is intentionally
limited to the relocation walker ABI in `libtaskman`; it does not move spawn
planning, capability publication, VSpace work, process-table state, IRQ state,
mmap, or loader mapping logic.

## Scope

The retired/default provider surface is now implemented by:

- `rust/crates/qsoe-tm-reloc`
- `libtaskman/include/tm_reloc.h`

The Rust provider implements the relocation resolver and relocation walker
behind the existing C ABI. The C implementation `libtaskman/src/reloc.c` has
been removed from tracked source.

Out of scope for this candidate:

- `tm_spawn` process construction, CSpace publication, and resume paths.
- Dynamic loader object mapping, PT_INTERP lookup, libc/rtld selection, and auxv
  construction.
- seL4 capability ownership, cnode allocation, IRQ handling, process-table
  mutation, and VSpace authority.
- Spawn, capability, VSpace, process-table, IRQ, mmap, or loader ownership.

## Required ABI surface

The Rust provider must preserve the existing C ABI exactly:

```c
int tm_reloc_init_resolver(const tm_elf_view_t *view,
                           unsigned long bias,
                           tm_reloc_resolver_t *out);

int tm_reloc_apply(const tm_elf_view_t *view,
                   unsigned long bias,
                   const tm_reloc_resolver_t *ext,
                   tm_reloc_write_q_fn write_cb,
                   tm_reloc_skip_log_fn skip_log,
                   void *user,
                   unsigned long *out_applied,
                   unsigned long *out_total,
                   unsigned long *out_skipped);
```

The `tm_reloc_resolver_t` layout remains part of the ABI:

```c
typedef struct tm_reloc_resolver {
    unsigned long base;
    Elf64_Sym *symtab;
    const char *strtab;
    unsigned long nsyms;
} tm_reloc_resolver_t;
```

The callback ABI is also fixed:

- `tm_reloc_write_q_fn` is the only permitted write path.
- `tm_reloc_skip_log_fn` is the only permitted unresolved-symbol logging path.
- The `user` pointer is opaque provider state and must not be interpreted by
  Rust.

## Behavioral parity requirements

The Rust provider must match the current C behavior before it can be enabled in
CI or LQ runtime evidence.

Required semantics:

- Missing dynamic relocation data succeeds with zero totals.
- `R_RISCV_RELATIVE`, `R_RISCV_64`, and `R_RISCV_JUMP_SLOT` remain covered by
  host parity fixtures.
- Local symbols resolve against the current ELF view and relocation bias.
- External symbols resolve through `tm_reloc_resolver_t` when available.
- Unresolved external symbols call `skip_log` when provided, write an eager NULL
  value through `write_cb`, and count as applied.
- Unsupported relocation types increment `out_skipped`, do not write through
  `write_cb`, and do not count as applied.
- `out_applied`, `out_total`, and `out_skipped` remain optional output pointers.
- The provider returns failure only for malformed input or callback write
  failures that the C implementation treats as fatal.

## Provider guardrails

The Rust implementation must remain a leaf provider:

- No seL4 syscalls.
- No capability allocation, mutation, or transfer.
- No heap allocation unless separately justified and covered by host and runtime
  evidence.
- No unwinding across the C ABI.
- No Rust panics in provider paths.
- No TLS, constructors, destructors, runtime initialization, or dynamic linking
  requirements.
- No direct memory writes to target images except by calling
  `tm_reloc_write_q_fn`.
- No logging except by calling `tm_reloc_skip_log_fn` for the existing skip-log
  case.

## Retired/default wiring

The provider selector is now required:

```make
QSOE_RUST_TM_RELOC=1
```

Required wiring posture:

- `QSOE_RUST_TM_RELOC=1` links the Rust provider through the same public C ABI.
- `QSOE_RUST_TM_RELOC=0` is rejected after C `tm_reloc` retirement.
- CI runs `make container-tm-reloc-provider-evidence`.
- Provider evidence runs Rust host parity tests, audits the target archive,
  rejects stale C selectors, verifies no C `reloc.o` remains in LQ
  `libtaskman.a`, and boots LQ through libc.so, rtld, and main relocation logs.

## Evidence captured

The implementation and retirement PRs added formal evidence before and after the
runtime default switch.

Required host evidence:

- Historical C fixture expectations were captured before the switch.
- Rust-provider host tests exercise the same relocation cases and expect the
  same counters, writes, skip logs, and resolver behavior.
- ABI/link evidence confirms the Rust static object/archive exports
  `tm_reloc_apply` and `tm_reloc_init_resolver`.
- Provider archive audit rejects TLS, constructors, destructors,
  unwinding, or dynamic runtime initialization.

Required runtime evidence:

- Boot LQ with default/required `QSOE_RUST_TM_RELOC=1`.
- Preserve the existing dynamic ELF spawn evidence.
- Require relocation log coverage for `libc.so`, `rtld`, and `main`.
- Reject relocation failure logs and spawn/loader fatal diagnostics already
  covered by the C evidence.
- Run the existing spawn/loader C boundary and stress evidence with the Rust
  relocation provider selected.

## Acceptance gates

The candidate advanced through these gates:

1. Provider plan lands with normal CI, CodeQL, main CI, main CodeQL, and Pages.
2. Opt-in Rust provider lands behind `QSOE_RUST_TM_RELOC=1` with host parity and
   ABI/link evidence.
3. Default/retirement PR rejects `QSOE_RUST_TM_RELOC=0`, removes C `reloc.o`
   from normal links, and passes full PR/main CI with LQ runtime relocation
   logs.

## Rollback posture

No C rollback selector remains after retirement:

- `QSOE_RUST_TM_RELOC=0` fails fast.
- `libtaskman/src/reloc.c` is removed.
- A rollback would be a normal source revert of the retirement PR.
- Broader spawn, capability, VSpace, loader, and process-table ownership remains
  C-owned and deferred.

## Next implementation step

Do not treat `tm_reloc` retirement as approval to move `tm_spawn`, capability
publication, VSpace construction, mmap, IRQ handling, or teardown ordering into
Rust. The next issue #154 work should split and evidence another narrow seam
before any authority-owning code changes language.
