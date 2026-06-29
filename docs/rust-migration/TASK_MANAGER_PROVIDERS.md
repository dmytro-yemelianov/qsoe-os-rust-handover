# Shared Task Manager Rust Provider Archive

Captured: 2026-06-29 CEST.

Task-manager Rust providers now link through one selected static archive:

```text
build/rust/tm-providers/libqsoe_tm_providers.a
```

The archive is produced by the `qsoe-tm-providers` crate. Individual provider
crates remain `rlib` crates and export the existing C ABI symbols. The wrapper
crate owns the `staticlib` artifact, the single no-std panic handler, and a
small anchor symbol that keeps selected provider crates present in the archive.

## Why This Exists

The original task-manager Rust pilots were linked as independent staticlibs.
That was acceptable while only one provider could be selected at a time, but it
did not scale: selecting two providers pulled in two panic handlers and made
the link plan depend on per-provider archives rather than one taskman Rust
unit.

The shared archive makes the model explicit:

- each provider crate keeps one C ABI surface and can still be host-tested on
  its own;
- taskman links one Rust archive when any `QSOE_RUST_TM_*` provider selector is
  enabled;
- there is exactly one panic handler in the linked taskman Rust code;
- multiple provider selectors can be enabled together without duplicate Rust
  runtime symbols;
- C remains default and rollback for every non-retired taskman provider.

## Selector Model

The existing provider selectors remain the public interface:

```text
QSOE_RUST_TM_CPIO=1
QSOE_RUST_TM_CRED=1
QSOE_RUST_TM_ELF=1
QSOE_RUST_TM_FDT=1
QSOE_RUST_TM_PATHMGR=1
QSOE_RUST_TM_PROCFS=1
QSOE_RUST_TM_PSEUDODEV=1
QSOE_RUST_TM_RSRCDB=1
QSOE_RUST_TM_SCRIPT=1
QSOE_RUST_TM_SYSCFG=1
QSOE_RUST_TM_SYSFS=1
QSOE_RUST_TM_SYSMAP=1
```

When one or more selectors are set, NQ/LQ taskman omit the matching C objects
and link `libqsoe_tm_providers.a`. The build script maps selectors to
`qsoe-tm-providers` Cargo features and fails if no provider was selected.

Legacy targets such as `make rust-tm-procfs-provider` still work for focused
evidence and compatibility. They delegate to the shared builder with one
feature enabled and copy the resulting archive to the historical path.

## Evidence

The focused multi-provider gate is:

```sh
make tm-providers-evidence
```

The current gate selects `tm_cpio` and `tm_procfs` together. It verifies:

- the shared archive builds for `riscv64imac-unknown-none-elf`;
- archive members report the expected RVC soft-float ABI;
- the archive exports symbols from both selected providers;
- the archive contains no duplicate `rust_begin_unwind` symbol;
- NQ and LQ taskman omit the selected C objects and link successfully;
- linked NQ/LQ taskman ELFs have no TLS, unwind, constructor, or dynamic
  sections;
- a dual-provider `/proc` smoke reaches the expected boot and `/proc` read
  milestones.

Use per-provider evidence targets for single-provider behavior and regression
coverage. Use `make tm-providers-evidence` when changing the shared archive,
provider selection plumbing, panic handler ownership, or component patches that
affect taskman link composition.
