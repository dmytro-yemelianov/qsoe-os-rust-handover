# Task Manager ELF Rust Opt-in Provider

Captured: 2026-06-29 15:05 CEST.

## Scope

`qsoe-tm-elf` is a Rust opt-in provider for the portable task-manager ELF view
parser in:

```text
libtaskman/src/elf.c
libtaskman/include/tm_elf.h
```

It exports the existing `tm_elf_parse` ABI and preserves the C parser's view
shape for ELF64 little-endian RISC-V images.

It covers:

- ELF magic, class, byte-order, machine, and type checks;
- program-header-table bounds checks;
- `PT_LOAD` capture into the fixed 8-entry `tm_elf_view_t` array;
- `filesz <= memsz` validation;
- file-span validation for non-empty load segments;
- `PT_INTERP` bounds and NUL-termination validation;
- entry point, dynamic/executable flag, program-header metadata, and virtual
  address range reporting.

It intentionally preserves current C behavior where the loader depends on it,
including:

- allowing zero-file-size `PT_LOAD` entries without validating their file
  offset;
- storing interpreter pointers directly into the caller-owned ELF blob;
- wrapping virtual segment end arithmetic before the final empty-range check.

It does not replace:

- segment mapping or address-space construction;
- dynamic-linker admission;
- relocation parsing or relocation writes;
- CPIO lookup, script handling, process tables, capability ownership, or seL4
  object manipulation.

## Selector

Normal builds keep C selected:

```sh
QSOE_RUST_TM_ELF=0 make -C nq/taskman
QSOE_RUST_TM_ELF=0 make -C lq taskman
```

The Rust opt-in path is:

```sh
QSOE_RUST_TM_ELF=1 make -C nq/taskman
QSOE_RUST_TM_ELF=1 make -C lq taskman
```

The top-level evidence target is:

```sh
make tm-elf-evidence
make tm-elf-runtime-smoke
```

Multiple taskman Rust providers may be selected together. The shared
`qsoe-tm-providers` archive packages the selected provider crates behind one
no-std panic handler. Legacy targets such as `make rust-tm-elf-provider`
still produce the historical single-provider output path for focused evidence.

## Evidence

Local validation on 2026-06-29:

```sh
make check-tm-elf-model
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-elf --features host-tests --lib
cargo clippy --manifest-path rust/Cargo.toml -p qsoe-tm-elf --features host-tests -- -D warnings
bash -n scripts/check-tm-elf-model.sh scripts/build-rust-tm-elf-provider.sh scripts/tm-elf-evidence.sh scripts/apply-component-overrides.sh
make rust-tm-elf-provider
make tm-elf-evidence
make tm-elf-runtime-smoke
```

`make tm-elf-evidence` verified:

- C host fixture passes against `libtaskman/src/elf.c`;
- Rust host tests pass for layout, valid parses, malformed inputs, too many
  load segments, zero-file-size loads, and wrapped segment ends;
- Rust staticlib builds for `riscv64imac-unknown-none-elf`;
- Rust provider archive members report RVC soft-float ABI;
- Rust provider archive exports `tm_elf_parse`;
- NQ C-default `libtaskman.a` contains one `elf.o`;
- NQ Rust-selected `libtaskman.a` contains zero `elf.o`;
- LQ C-default `libtaskman.a` contains one `elf.o`;
- LQ Rust-selected `libtaskman.a` contains zero `elf.o`;
- NQ and LQ taskman links complete in both C-default and Rust-selected modes,
  and the linked taskman ELFs pass the evidence script's ELF flag and section
  audit.

`make tm-elf-runtime-smoke` verified the Rust-selected parser in a booted LQ
image. The smoke injects a sysinit fragment, verifies the staged
`/usr/bin/sysinfo` binary has a program interpreter, rebuilds QSOE/L with
`QSOE_RUST_TM_ELF=1`, and waits for:

```text
tm-elf-runtime-smoke: /usr/bin/sysinfo dynamic ELF spawn ok
```

`/usr/bin/sysinfo` is a dynamic ELF, so successful spawn exercises
`tm_elf_parse` for the main image plus the loader path for `rtld` and `libc`.
This evidence proves ABI compatibility, archive selection, rollback, linked
artifact shape, and focused dynamic ELF spawn behavior under the Rust ELF
parser.

## C Rollback

C remains the default and rollback path:

- `QSOE_RUST_TM_ELF=0` keeps `libtaskman/src/elf.c`;
- `QSOE_RUST_TM_ELF=1` excludes `elf.o` and links
  the shared taskman Rust provider archive.

Do not promote this provider to a Rust-default RC until a separate RC decision
accepts this loader/runtime coverage, and do not retire C until #26 is
satisfied in a separate removal PR.
