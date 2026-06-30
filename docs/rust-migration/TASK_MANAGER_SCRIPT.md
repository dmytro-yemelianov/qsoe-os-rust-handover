# Task Manager Shebang Parser Provider

Captured: 2026-06-30 CEST.

`tm_script` is the retired Rust task-manager provider for the portable POSIX
shebang parser. Taskman C code keeps consuming the public `tm_script.h` ABI:

```text
int tm_script_parse_shebang(const uint8_t *data, unsigned size,
                            char *interp, unsigned interp_cap,
                            char *arg, unsigned arg_cap);
```

The provider owns only byte-level parsing of the first script line: `#!`,
leading blanks, the interpreter path, and the optional single POSIX argument.
It does not replace taskman spawn orchestration, interpreter loading, argv
construction, CPIO lookup, ELF loading, relocation, process creation, or seL4
object manipulation.

## Selector

`tm_script` is Rust-only after C provider retirement:

```text
QSOE_RUST_TM_SCRIPT=1  -> Rust `qsoe-tm-script` provider is selected
QSOE_RUST_TM_SCRIPT=0  -> rejected; C `libtaskman/src/script.c` is retired
```

The C source `libtaskman/src/script.c` is removed. Normal NQ/LQ taskman links
pull `tm_script_parse_shebang` from:

```text
build/rust/tm-providers/libqsoe_tm_providers.a
```

The archive is built for `riscv64imac-unknown-none-elf` so it matches
taskman's soft-float ABI. Multiple taskman Rust providers may be selected
together through the same shared no-std provider archive.

## Evidence

```sh
make check-tm-script-model
make rust-tm-script-provider
make tm-script-evidence
make tm-script-runtime-smoke
make tm-script-rc-smoke
```

`make check-tm-script-model` runs the Rust host parser tests for interpreter and
single-argument parsing, CR/LF line termination, malformed-line rejection,
output clearing, zero-capacity behavior, and current truncation behavior.

`make tm-script-evidence` builds and audits the Rust provider archive, verifies
that NQ and LQ `libtaskman.a` contain no C `script.o`, checks that final
taskman ELFs still export `tm_script_parse_shebang`, and verifies that
`QSOE_RUST_TM_SCRIPT=0` fails fast in NQ and LQ taskman builds.

`make tm-script-runtime-smoke` boots QSOE/L with Rust `tm_script`, stages a
temporary executable `/usr/bin/tm_script_probe` shell script in the virtio qrvfs
image, injects a sysinit fragment that runs the probe directly, and verifies
that the probe prints its marker and exits successfully. Running the script by
path forces taskman spawn to parse the shebang before loading `/bin/sh`.

`make tm-script-rc-smoke` remains as the compatibility smoke for the retired
Rust path. `TM_SCRIPT_RC_ROLLBACK=1 scripts/tm-script-rc-smoke.sh` now fails
fast because the C rollback path is retired.

Historical Rust-default RC evidence and rollback drill details live in
`TASK_MANAGER_SCRIPT_RC.md`. The retirement note is
`TASK_MANAGER_SCRIPT_RETIREMENT.md`.
