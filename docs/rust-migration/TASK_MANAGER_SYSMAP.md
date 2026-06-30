# Task Manager Sysmap Rust-Default RC Provider

Captured: 2026-06-30 CEST.

## Scope

`qsoe-tm-sysmap` is the Rust-default release-candidate provider for the LQ
task-manager sysmap page builder in:

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

Normal LQ builds select Rust by default:

```sh
make -C lq taskman
```

C rollback remains available during the RC window:

```sh
QSOE_RUST_TM_SYSMAP=0 make -C lq taskman
```

The top-level evidence and smoke targets are:

```sh
make tm-sysmap-evidence
make tm-sysmap-runtime-smoke
make tm-sysmap-rc-smoke
make tm-sysmap-rc-rollback-smoke
```

Multiple taskman Rust providers may be selected together. The shared
`qsoe-tm-providers` archive packages the selected provider crates behind one
no-std panic handler. Legacy targets such as `make rust-tm-sysmap-provider`
still produce the historical single-provider output path for focused evidence.

## Evidence

Local validation on 2026-06-30:

```sh
make check-tm-sysmap-model
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-sysmap --features host-tests --lib
cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-sysmap --features host-tests -- -D warnings
bash -n scripts/check-tm-sysmap-model.sh scripts/build-rust-tm-sysmap-provider.sh scripts/tm-sysmap-evidence.sh scripts/tm-sysmap-runtime-smoke.sh scripts/tm-sysmap-rc-smoke.sh scripts/apply-component-overrides.sh scripts/rust-check.sh scripts/rust-workflow.sh
./scripts/apply-component-overrides.sh
make -n check-tm-sysmap-model rust-tm-sysmap-provider tm-sysmap-evidence tm-sysmap-runtime-smoke tm-sysmap-rc-smoke tm-sysmap-rc-rollback-smoke container-rust-tm-sysmap-provider container-tm-sysmap-evidence container-tm-sysmap-runtime-smoke container-tm-sysmap-rc-smoke container-tm-sysmap-rc-rollback-smoke
make rust-tm-sysmap-provider
make tm-sysmap-evidence
make tm-sysmap-runtime-smoke
make tm-sysmap-rc-smoke
make tm-sysmap-rc-rollback-smoke
```

`make tm-sysmap-evidence` verified:

- C host fixture passes against `lq/taskman/sys/sysmap.c`;
- Rust host tests pass for get-before-build, minimal END-only syscfg, and a
  full timebase/PLIC/PCI/DesignWare syscfg page;
- Rust staticlib builds for `riscv64imac-unknown-none-elf`;
- Rust provider archive members report RVC soft-float ABI;
- Rust provider archive exports `tm_sysmap_build` and `tm_sysmap_get`;
- LQ C-rollback taskman links with C `sys/sysmap.o`;
- LQ Rust-default taskman omits `sys/sysmap.o` and links
  the shared taskman Rust provider archive;
- linked taskman ELFs pass the evidence script's ELF flag and section audit.

This evidence proves ABI compatibility, archive selection, rollback, and linked
artifact shape.

`make tm-sysmap-runtime-smoke` verified the Rust-default builder in a booted
LQ image. The smoke:

- captures a Rust-default LQ taskman dry-run plan and rejects any remaining
  `sys/sysmap.o` link;
- verifies the selected Rust provider archive exports `tm_sysmap_build` and
  `tm_sysmap_get`;
- boots with default `QSOE_RUST_TM_SYSMAP=1` and mandatory
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

## C Rollback

C remains the rollback path:

- `QSOE_RUST_TM_SYSMAP=1` is the normal LQ taskman default and links through
  the shared taskman Rust provider archive.
- `QSOE_RUST_TM_SYSMAP=0` keeps `lq/taskman/sys/sysmap.c` and links
  `sys/sysmap.o`.

Do not retire C until #26 is satisfied in a separate removal PR.
