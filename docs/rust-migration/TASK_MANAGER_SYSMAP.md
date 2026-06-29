# Task Manager Sysmap Rust Opt-in Provider

Captured: 2026-06-29 CEST.

## Scope

`qsoe-tm-sysmap` is a Rust opt-in provider for the LQ task-manager sysmap page
builder in:

```text
lq/taskman/sys/sysmap.c
lq/taskman/sys/sysmap.h
```

It exports the existing `tm_sysmap_*` ABI and preserves the C builder's
little-endian `PSYS` TLV page layout.

It covers:

- cached 4 KiB sysmap page construction and `tm_sysmap_get`;
- `QSOE_SYSMAP_MAGIC`, version, header length, and final `total_bytes`;
- `MTIME_FREQ` from `TM_SYSCFG_TAG_TIMEBASE_HZ`;
- PLIC `s_context_count` from `TM_SYSCFG_TAG_NUM_CPUS`;
- PCI ECAM base, size, bus range, DesignWare DBI/MSI fields, and the first
  non-prefetchable MEM PCI window;
- END sentinel emission and 8-byte TLV padding.

It does not replace:

- FDT parsing;
- syscfg construction;
- policy for which platform-data tags are emitted;
- process spawn, sysmap page mapping into child VSpaces, capability ownership,
  memory management, IRQ, or seL4 invocation code.

## Selector

Normal LQ builds keep C selected:

```sh
QSOE_RUST_TM_SYSMAP=0 make -C lq taskman
```

The Rust opt-in path is:

```sh
QSOE_RUST_TM_SYSMAP=1 make -C lq taskman
```

The top-level evidence target is:

```sh
make tm-sysmap-evidence
```

Multiple taskman Rust providers may be selected together. The shared
`qsoe-tm-providers` archive packages the selected provider crates behind one
no-std panic handler. Legacy targets such as `make rust-tm-sysmap-provider`
still produce the historical single-provider output path for focused evidence.

## Evidence

Local validation on 2026-06-29:

```sh
make check-tm-sysmap-model
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-sysmap --features host-tests --lib
cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-sysmap --features host-tests -- -D warnings
bash -n scripts/check-tm-sysmap-model.sh scripts/build-rust-tm-sysmap-provider.sh scripts/tm-sysmap-evidence.sh scripts/apply-component-overrides.sh scripts/rust-check.sh scripts/rust-workflow.sh
./scripts/apply-component-overrides.sh
make -n check-tm-sysmap-model rust-tm-sysmap-provider tm-sysmap-evidence container-rust-tm-sysmap-provider container-tm-sysmap-evidence
make rust-tm-sysmap-provider
make tm-sysmap-evidence
```

`make tm-sysmap-evidence` verified:

- C host fixture passes against `lq/taskman/sys/sysmap.c`;
- Rust host tests pass for get-before-build, minimal END-only syscfg, and a
  full timebase/PLIC/PCI/DesignWare syscfg page;
- Rust staticlib builds for `riscv64imac-unknown-none-elf`;
- Rust provider archive members report RVC soft-float ABI;
- Rust provider archive exports `tm_sysmap_build` and `tm_sysmap_get`;
- LQ C-default taskman links with C `sys/sysmap.o`;
- LQ Rust-selected taskman omits `sys/sysmap.o` and links
  the shared taskman Rust provider archive;
- linked taskman ELFs pass the evidence script's ELF flag and section audit.

This evidence proves ABI compatibility, archive selection, rollback, and linked
artifact shape. It does not yet prove full boot/runtime behavior for the mapped
child `PSYS` page under the Rust provider.

## C Rollback

C remains the default and rollback path:

- `QSOE_RUST_TM_SYSMAP=0` keeps `lq/taskman/sys/sysmap.c`;
- `QSOE_RUST_TM_SYSMAP=1` excludes `sys/sysmap.o` from LQ taskman and links
  the shared taskman Rust provider archive.

Do not promote this provider to a Rust-default RC until runtime boot coverage
proves the sysmap page consumed by user processes, and do not retire C until
#26 is satisfied in a separate removal PR.
