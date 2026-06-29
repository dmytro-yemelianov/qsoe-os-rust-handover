# Task Manager Shebang Parser Provider

Captured: 2026-06-29 CEST.

`tm_script` is a bounded task-manager Rust provider for the portable POSIX
shebang parser:

```text
libtaskman/src/script.c
libtaskman/include/tm_script.h
```

## Scope

The Rust provider exports the existing `tm_script.h` C ABI:

```text
int tm_script_parse_shebang(const uint8_t *data, unsigned size,
                            char *interp, unsigned interp_cap,
                            char *arg, unsigned arg_cap);
```

It owns only byte-level parsing of the first script line: `#!`, leading blanks,
the interpreter path, and the optional single POSIX argument. It does not
replace taskman spawn, interpreter loading, argv construction, CPIO lookup, ELF
loading, relocation, process creation, or any seL4 object manipulation.

The provider intentionally preserves the current C implementation behavior,
including truncating into too-small output buffers instead of returning a hard
error once parsing has started.

## Selector

Normal taskman builds remain C-default:

```text
QSOE_RUST_TM_SCRIPT=0  -> C `libtaskman/src/script.c` remains selected
QSOE_RUST_TM_SCRIPT=1  -> Rust `qsoe-tm-script` staticlib is linked instead
```

When Rust is selected, `libtaskman/Makefile` excludes `script.o` from
`libtaskman.a`, and the NQ/LQ taskman links add:

```text
build/rust/tm-providers/libqsoe_tm_providers.a
```

The archive is built for `riscv64imac-unknown-none-elf` so it matches
taskman's soft-float ABI.

Multiple taskman Rust providers may be selected together. The shared
`qsoe-tm-providers` archive packages the selected provider crates behind one
no-std panic handler. Legacy targets such as `make rust-tm-script-provider`
still produce the historical single-provider output path for focused evidence.

## Evidence

The C behavior baseline is covered by:

```sh
make check-tm-script-model
```

That fixture verifies interpreter and single-argument parsing, CR/LF line
termination, malformed-line rejection, output clearing, zero-capacity behavior,
and current truncation behavior.

The Rust provider has equivalent host coverage:

```sh
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-script --features host-tests
```

The full opt-in evidence gate is:

```sh
make tm-script-evidence
```

It runs the C fixture, Rust host tests, builds and audits the Rust staticlib,
checks exported archive and linked taskman symbols, verifies all archive members
are RVC soft-float, and links both NQ and LQ taskman in C rollback and
Rust-selected modes. The gate also verifies `script.o` is present for
`QSOE_RUST_TM_SCRIPT=0` and absent for `QSOE_RUST_TM_SCRIPT=1`.

## Current State

`tm_script` is Rust opt-in only. It is not a Rust-default release candidate and
has no C retirement approval. Keep `libtaskman/src/script.c` as the rollback
implementation until boot/runtime smokes cover script spawn fallback, the global
retirement checklist is satisfied, and a separate removal PR is reviewed.
