# Task Manager FDT Parser Rust Provider

Captured: 2026-06-29 CEST.

## Scope

`qsoe-tm-fdt` is a Rust-default RC provider for the LQ task-manager device-tree
blob parser in:

```text
lq/taskman/sys/fdt.c
lq/taskman/sys/fdt.h
```

It exports the existing `tm_fdt_*` ABI and preserves the C parser's minimal
big-endian FDT walker behavior.

It covers:

- header magic and last-compatible-version validation;
- total-size reporting;
- absolute path lookup with root handling, NOP skipping, and `name@unit`
  matching;
- raw property lookup through the strings block;
- u32, u64, and NUL-terminated string property helpers;
- first compatible-node search;
- indexed `reg` tuple decoding with caller-supplied address/size cell counts.

It does not replace:

- FDT discovery from bootinfo;
- syscfg construction policy;
- sysmap construction;
- initrd loading;
- path, process, memory, capability, IRQ, or seL4 invocation code.

## Selector

Normal LQ builds select Rust:

```sh
make -C lq taskman
```

The explicit C rollback path is:

```sh
QSOE_RUST_TM_FDT=0 make -C lq taskman
```

The top-level evidence target is:

```sh
make tm-fdt-evidence
make tm-fdt-runtime-smoke
make tm-fdt-rc-smoke
make tm-fdt-rc-rollback-smoke
```

Multiple taskman Rust providers may be selected together. The shared
`qsoe-tm-providers` archive packages the selected provider crates behind one
no-std panic handler. Legacy targets such as `make rust-tm-fdt-provider`
still produce the historical single-provider output path for focused evidence.

## Evidence

Local validation on 2026-06-29:

```sh
make check-tm-fdt-model
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-fdt --features host-tests --lib
cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-fdt --features host-tests -- -D warnings
bash -n scripts/check-tm-fdt-model.sh scripts/build-rust-tm-fdt-provider.sh scripts/tm-fdt-evidence.sh scripts/apply-component-overrides.sh
./scripts/apply-component-overrides.sh
make -n check-tm-fdt-model rust-tm-fdt-provider tm-fdt-evidence tm-fdt-runtime-smoke container-rust-tm-fdt-provider container-tm-fdt-evidence container-tm-fdt-runtime-smoke
make rust-tm-fdt-provider
make tm-fdt-evidence
make tm-fdt-runtime-smoke
make container-tm-fdt-evidence
```

`make tm-fdt-evidence` verified:

- C host fixture passes against `lq/taskman/sys/fdt.c`;
- Rust host tests pass for header validation, size reporting, path lookup,
  raw/string/u32 property reads, compatible-node search, malformed string
  rejection, and `reg` tuple decoding;
- Rust staticlib builds for `riscv64imac-unknown-none-elf`;
- Rust provider archive members report RVC soft-float ABI;
- Rust provider archive exports all nine `tm_fdt_*` ABI symbols;
- LQ Rust-default taskman omits `sys/fdt.o` and links
  the shared taskman Rust provider archive;
- LQ C rollback taskman links with C `sys/fdt.o`;
- linked taskman ELFs pass the evidence script's ELF flag and section audit.
- the container-equivalent `tm_fdt` evidence target passes with the same
  Rust-default/C-rollback link checks.

This evidence proves ABI compatibility, archive selection, rollback, and linked
artifact shape.

## Formal evidence run on 2026-06-30

Local rerun:

- `bash scripts/tm-fdt-evidence.sh` completed successfully.
- C host fixture: `check-tm-fdt-model.sh: ok` (`tm_fdt_model_test` binary built).
- Rust host tests: 3 passed.
- Rust provider archive built for shared-link composition and RISC-V soft-float.
- LQ Rust-default and C-rollback link plans both built and passed.
- Evidence artifacts captured in `build/tm-fdt-evidence/`, including:
  - `rust-provider-summary.txt`
  - `lq-rust-default-taskman-dry-run.txt`
  - `lq-rust-selected-taskman-dry-run.txt`
  - `lq-c-default-taskman-readelf-*`
  - `lq-c-rollback-taskman-readelf-*`

`make tm-fdt-runtime-smoke` verified the Rust-default parser in a booted LQ
image. The smoke:

- captures a Rust-default LQ taskman dry-run plan and rejects any remaining
  `sys/fdt.o` link;
- verifies the selected Rust provider archive exports all nine `tm_fdt_*`
  ABI symbols;
- boots with default `QSOE_RUST_TM_FDT=1` and mandatory `QSOE_RUST_TM_PROCFS=1`;
- waits for taskman's `/chosen` command-line marker plus `syscfg built from FDT`
  and `sysmap page built`;
- checks `/sys/board`, `/sys/cmdline`, and `/usr/bin/sysinfo` from sysinit.

Expected runtime markers:

```text
Boot command line: mainfs=/dev/vblk0
syscfg built from FDT
sysmap page built
tm-fdt-runtime-smoke: /sys/board FDT compatible ok
tm-fdt-runtime-smoke: /chosen bootargs ok
tm-fdt-runtime-smoke: /usr/bin/sysinfo FDT sysinfo ok
```

This is QEMU/LQ boot-consumer compatibility coverage. It does not replace the
need for broader hardware PCI and memory-topology coverage before C removal.

## C Rollback

C remains the rollback path during the RC window:

- default `QSOE_RUST_TM_FDT=1` excludes `sys/fdt.o` from LQ taskman and links
  the shared taskman Rust provider archive.
- `QSOE_RUST_TM_FDT=0` keeps `lq/taskman/sys/fdt.c`;
- `make tm-fdt-rc-rollback-smoke` boots the C rollback path.

Do not retire C `sys/fdt.c` during this RC. C removal still requires broader
PCI and memory-topology confidence, the global retirement checklist, and a
separate removal PR.
