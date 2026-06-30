# Task Manager Syscfg Rust-Default RC Provider

Captured: 2026-06-30 CEST.

## Scope

`qsoe-tm-syscfg` is the Rust-default RC provider for the portable
`libtaskman/src/syscfg.c` TLV builder/walker behind the existing
`tm_syscfg.h` ABI. C `syscfg.o` remains available as rollback.

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

Normal builds select Rust:

```sh
make -C nq/taskman
make -C lq taskman
```

The C rollback path is:

```sh
QSOE_RUST_TM_SYSCFG=0 make -C nq/taskman
QSOE_RUST_TM_SYSCFG=0 make -C lq taskman
```

The explicit Rust-selected path is:

```sh
QSOE_RUST_TM_SYSCFG=1 make -C nq/taskman
QSOE_RUST_TM_SYSCFG=1 make -C lq taskman
```

The top-level evidence target is:

```sh
make tm-syscfg-evidence
make tm-syscfg-runtime-smoke
make tm-syscfg-rc-smoke
make tm-syscfg-rc-rollback-smoke
```

When Rust is selected for a taskman link, the selected provider is packaged in
the shared `build/rust/tm-providers/libqsoe_tm_providers.a` archive. Legacy
targets such as `make rust-tm-syscfg-provider` still produce the historical
single-provider output path for focused evidence.

## Evidence

Validation commands:

```sh
make check-tm-syscfg-model
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-syscfg --features host-tests
cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-syscfg --features host-tests -- -D warnings
make rust-tm-syscfg-provider
make tm-syscfg-evidence
make tm-syscfg-runtime-smoke
make tm-syscfg-rc-smoke
make tm-syscfg-rc-rollback-smoke
```

`make tm-syscfg-evidence` verified:

- C host fixture passes against `libtaskman/src/syscfg.c`;
- Rust host tests pass for the exported ABI behavior;
- Rust staticlib builds for `riscv64imac-unknown-none-elf`;
- Rust provider archive members report RVC soft-float ABI;
- Rust provider archive exports all `tm_syscfg_*` symbols;
- NQ C-rollback `libtaskman.a` contains one `syscfg.o`;
- NQ Rust-selected `libtaskman.a` contains zero `syscfg.o`;
- LQ C-rollback `libtaskman.a` contains one `syscfg.o`;
- LQ Rust-selected `libtaskman.a` contains zero `syscfg.o`;
- NQ and LQ taskman links complete in both C-rollback and Rust-selected modes.

`make tm-syscfg-runtime-smoke` verified the Rust-selected taskman build in a
booted LQ image. The smoke:

- rebuilds QSOE/L with `QSOE_RUST_TM_SYSCFG=1` and mandatory
  `QSOE_RUST_TM_PROCFS=1`;
- verifies `libtaskman.a` no longer contains C `syscfg.o`;
- verifies the selected Rust provider archive exports `tm_syscfg_init`;
- waits for taskman's `syscfg built from FDT` and `sysmap page built` boot
  markers;
- reads `/sys/board` and `/sys/cmdline`, checking that cmdline carries
  `mainfs=/dev/vblk0`;
- runs `/usr/bin/sysinfo`, which reads `/sys` identity data and syscfg-derived
  CPU/sysmap state.

This runtime smoke proves that a Rust-selected portable `tm_syscfg` taskman
build still boots and serves syscfg-backed consumers. It does not prove that
LQ's private global `lq/taskman/sys/syscfg.c` was replaced; that private
FDT-backed runtime builder remains C by design in this RC slice.

`make tm-syscfg-rc-smoke` verifies that the default selector omits C
`syscfg.o` in NQ and LQ taskman archives, then runs the same LQ runtime path.
`make tm-syscfg-rc-rollback-smoke` repeats the archive-membership and runtime
checks with `QSOE_RUST_TM_SYSCFG=0`.

## C Rollback

Rust is the RC default and C remains the rollback path:

- `QSOE_RUST_TM_SYSCFG=1` excludes `syscfg.o` and links
  the shared taskman Rust provider archive.
- `QSOE_RUST_TM_SYSCFG=0` keeps `libtaskman/src/syscfg.c`;

Do not retire C until #26 is satisfied in a separate removal PR.
