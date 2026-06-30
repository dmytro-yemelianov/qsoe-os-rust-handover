# Task Manager Sysmap Retired Rust Provider

Captured: 2026-06-30 CEST.

## Scope

`qsoe-tm-sysmap` is the mandatory Rust provider for the LQ task-manager sysmap
page builder behind the existing `tm_sysmap_*` ABI declared by
`lq/taskman/sys/sysmap.h`. The retired C provider was
`lq/taskman/sys/sysmap.c`.

This covers:

- cached 4 KiB sysmap page construction and `tm_sysmap_get`;
- `QSOE_SYSMAP_MAGIC`, version, header length, and final `total_bytes`;
- `MTIME_FREQ` from `TM_SYSCFG_TAG_TIMEBASE_HZ`;
- PLIC `s_context_count` from `TM_SYSCFG_TAG_NUM_CPUS`;
- PCI ECAM base, size, bus range, DesignWare DBI/MSI fields, and the first
  non-prefetchable MEM PCI window;
- END sentinel emission and 8-byte TLV padding.

This does not replace:

- FDT parsing;
- syscfg construction or platform-data tag policy;
- process spawn;
- sysmap page mapping into child VSpaces;
- capability ownership, memory management, IRQ, or seL4 invocation code.

## Selector State

`QSOE_RUST_TM_SYSMAP=1` is mandatory in umbrella and LQ taskman builds.
`QSOE_RUST_TM_SYSMAP=0` now fails fast.

The rollback smoke target was removed:

```sh
make tm-sysmap-rc-rollback-smoke
make container-tm-sysmap-rc-rollback-smoke
```

The retained checks are:

```sh
make check-tm-sysmap-model
make rust-tm-sysmap-provider
make tm-sysmap-evidence
make tm-sysmap-runtime-smoke
make tm-sysmap-rc-smoke
```

When a taskman link needs Rust providers, `qsoe-tm-sysmap` is packaged in the
shared `build/rust/tm-providers/libqsoe_tm_providers.a` archive. The legacy
`make rust-tm-sysmap-provider` target still produces the historical
single-provider output path for focused evidence.

## Evidence

Validation commands:

```sh
make check-tm-sysmap-model
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-sysmap --features host-tests --lib
make rust-tm-sysmap-provider
make tm-sysmap-evidence
make tm-sysmap-runtime-smoke
make tm-sysmap-rc-smoke
```

`make tm-sysmap-evidence` verifies:

- Rust host tests pass for get-before-build, minimal END-only syscfg, and a
  full timebase/PLIC/PCI/DesignWare syscfg page;
- Rust staticlib builds for `riscv64imac-unknown-none-elf`;
- Rust provider archive members report RVC soft-float ABI;
- Rust provider archive exports `tm_sysmap_build` and `tm_sysmap_get`;
- LQ taskman omits C `sys/sysmap.o`;
- LQ taskman links the shared taskman Rust provider archive;
- LQ top-level and LQ taskman reject `QSOE_RUST_TM_SYSMAP=0`;
- linked taskman ELFs pass the evidence script's ELF flag and section audit.

`make tm-sysmap-runtime-smoke` verifies the Rust-only taskman build in a
booted LQ image. The smoke:

- captures a Rust-only LQ taskman dry-run plan and rejects any remaining
  `sys/sysmap.o` link;
- verifies the selected Rust provider archive exports `tm_sysmap_build` and
  `tm_sysmap_get`;
- boots with mandatory `QSOE_RUST_TM_SYSMAP=1` and
  `QSOE_RUST_TM_PROCFS=1`;
- waits for taskman's `syscfg built from FDT` and `sysmap page built` markers;
- waits for pci-server's scan-complete marker, proving its `hwi_init` path
  could derive ECAM data from the mapped sysmap page;
- runs `/usr/bin/sysinfo` from sysinit and checks the QEMU timebase, PLIC, and
  PCI output from the spawned child's `QSOE_SYSMAP_VA` page.

Expected runtime markers:

```text
syscfg built from FDT
sysmap page built
[pci-server] scan complete
tm-sysmap-runtime-smoke: /usr/bin/sysinfo completed
timebase 10000000 Hz
interrupts: PLIC at
PCI:       buses 0..
```

## Reintroduction Rule

Do not reintroduce C `tm_sysmap` rollback without a new issue, explicit
rollback justification, and fresh PR evidence.
