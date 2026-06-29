# Task Manager Syscfg Rust Opt-in Provider

Captured: 2026-06-29 13:25 CEST.

## Scope

`qsoe-tm-syscfg` is a Rust opt-in provider for the portable
`libtaskman/src/syscfg.c` TLV builder/walker behind the existing
`tm_syscfg.h` ABI.

It covers:

- caller-owned `tm_syscfg_state_t` initialization;
- raw TLV emit;
- little-endian `u32` and `u64` emit;
- ASCIZ emit, including the existing empty-string skip behavior;
- END sentinel finalization;
- finalized blob get;
- raw find plus typed `u32` and `u64` find helpers.

It does not replace:

- LQ's private global `lq/taskman/sys/syscfg.c` FDT-backed builder;
- FDT parsing;
- sysmap page construction;
- boot platform-data policy;
- `/sys` file serving;
- process creation, capability ownership, relocation, loader admission, or
  seL4 object manipulation.

## Selector

Normal builds keep C selected:

```sh
QSOE_RUST_TM_SYSCFG=0 make -C nq/taskman
QSOE_RUST_TM_SYSCFG=0 make -C lq taskman
```

The Rust opt-in path is:

```sh
QSOE_RUST_TM_SYSCFG=1 make -C nq/taskman
QSOE_RUST_TM_SYSCFG=1 make -C lq taskman
```

The top-level evidence target is:

```sh
make tm-syscfg-evidence
```

When Rust is selected for a taskman link, the selected provider is packaged in
the shared `build/rust/tm-providers/libqsoe_tm_providers.a` archive. Legacy
targets such as `make rust-tm-syscfg-provider` still produce the historical
single-provider output path for focused evidence.

## Evidence

Local validation on 2026-06-29:

```sh
make check-tm-syscfg-model
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-syscfg --features host-tests
cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-syscfg --features host-tests -- -D warnings
make rust-tm-syscfg-provider
make tm-syscfg-evidence
```

`make tm-syscfg-evidence` verified:

- C host fixture passes against `libtaskman/src/syscfg.c`;
- Rust host tests pass for the exported ABI behavior;
- Rust staticlib builds for `riscv64imac-unknown-none-elf`;
- Rust provider archive members report RVC soft-float ABI;
- Rust provider archive exports all `tm_syscfg_*` symbols;
- NQ C-default `libtaskman.a` contains one `syscfg.o`;
- NQ Rust-selected `libtaskman.a` contains zero `syscfg.o`;
- LQ C-default `libtaskman.a` contains one `syscfg.o`;
- LQ Rust-selected `libtaskman.a` contains zero `syscfg.o`;
- NQ and LQ taskman links complete in both C-default and Rust-selected modes.

The final taskman ELFs do not currently prove runtime use of the portable
syscfg provider: NQ does not call this portable helper today, and LQ serves
runtime syscfg through its private global `lq/taskman/sys/syscfg.c`. That is
intentional for this opt-in slice; the evidence proves ABI/link selection and
archive rollback, not a Rust-default boot policy change.

## C Rollback

C remains the default and rollback path:

- `QSOE_RUST_TM_SYSCFG=0` keeps `libtaskman/src/syscfg.c`;
- `QSOE_RUST_TM_SYSCFG=1` excludes `syscfg.o` and links
  the shared taskman Rust provider archive.

Do not promote this provider to a Rust-default RC until boot/runtime coverage
proves syscfg-backed platform-data behavior, and do not retire C until #26 is
satisfied in a separate removal PR.
