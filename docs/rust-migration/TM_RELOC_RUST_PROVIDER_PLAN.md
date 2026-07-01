# `tm_reloc` Rust-provider candidate plan

Status: planned, C default retained.

This plan defines the first eligible Rust-provider candidate inside the spawn,
capability, relocation, and loader roadmap item. It is intentionally limited to
the relocation walker ABI in `libtaskman`; it does not move spawn planning,
capability publication, VSpace work, process-table state, IRQ state, mmap, or
loader mapping logic.

## Scope

The candidate is the `tm_reloc` provider surface currently implemented by:

- `libtaskman/src/reloc.c`
- `libtaskman/include/tm_reloc.h`

The Rust provider may implement the relocation resolver and relocation walker
behind the existing C ABI. The C implementation remains the default until an
explicit later default-switch milestone.

Out of scope for this candidate:

- `tm_spawn` process construction, CSpace publication, and resume paths.
- Dynamic loader object mapping, PT_INTERP lookup, libc/rtld selection, and auxv
  construction.
- seL4 capability ownership, cnode allocation, IRQ handling, process-table
  mutation, and VSpace authority.
- Default provider switch, C implementation removal, or C evidence retirement.

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

## Opt-in wiring

The provider selector must be opt-in at first:

```make
QSOE_RUST_TM_RELOC=0
```

Required wiring posture:

- `QSOE_RUST_TM_RELOC=0` builds and runs the existing C implementation.
- `QSOE_RUST_TM_RELOC=1` links the Rust provider through the same public C ABI.
- CI must continue running the existing C relocation evidence.
- Provider evidence must run the C and Rust paths against the same host fixture
  expectations.
- Default posture cannot change until the opt-in evidence is stable and recorded
  in the roadmap issue.

## Evidence requirements

The first implementation PR must add formal evidence before any runtime default
switch.

Required host evidence:

- Reuse or extend `scripts/reloc-c-evidence.sh` so the C fixture expectations
  remain the baseline.
- Add a Rust-provider fixture path that exercises the same relocation cases and
  expects the same counters, writes, skip logs, and resolver behavior.
- Add an ABI/link check that confirms the Rust static object/archive exports
  `tm_reloc_apply` and `tm_reloc_init_resolver`.
- Reject provider artifacts that require TLS, constructors, destructors,
  unwinding, or dynamic runtime initialization.

Required runtime evidence:

- Boot LQ with `QSOE_RUST_TM_RELOC=1`.
- Preserve the existing dynamic ELF spawn evidence.
- Require relocation log coverage for `libc.so`, `rtld`, and `main`.
- Reject relocation failure logs and spawn/loader fatal diagnostics already
  covered by the C evidence.
- Run the existing spawn/loader C boundary and stress evidence with the Rust
  relocation provider selected.

Required external-ref evidence:

- Run GitHub Actions external LQ ref evidence against an LQ branch containing
  only the opt-in provider wiring and provider candidate.
- Record the external repository, ref, commit, and run ID in issue #154.
- Keep C default in the handover repository until this evidence is complete.

## Acceptance gates

The candidate advances only through these gates:

1. Provider plan lands with normal CI, CodeQL, main CI, main CodeQL, and Pages.
2. Opt-in Rust provider lands behind `QSOE_RUST_TM_RELOC=1` with host parity and
   ABI/link evidence.
3. External LQ ref evidence passes with the opt-in provider and dynamic spawn
   relocation logs.
4. RC/default posture is proposed only after repeated evidence shows no
   regression in C default, opt-in provider parity, spawn/loader stress, and
   external LQ runtime behavior.

## Rollback posture

Rollback remains simple until the explicit default-switch milestone:

- Leave `QSOE_RUST_TM_RELOC=0` as the default.
- Keep `libtaskman/src/reloc.c` buildable and covered by CI.
- Do not remove C relocation evidence.
- If provider evidence fails, disable only the opt-in selector and keep the C
  roadmap state unchanged.

## Next implementation step

After this plan lands, the next PR should introduce the opt-in Rust provider
candidate and the provider evidence target. That PR should not switch defaults.
