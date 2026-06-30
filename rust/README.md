# QSOE Rust Workspace

This workspace is the Rust migration spike area. It is intentionally opt-in and
does not participate in the normal C build unless a Rust-specific make target
or script is invoked.

## Local Checks

Run the fast edit-loop check:

```sh
make rust-fast
```

Run the normal host-side Rust quality gate:

```sh
make rust-check
```

`make rust-check` is equivalent to `make rust-quality`. It runs formatting,
`cargo check`, clippy, and host tests. It does not build a boot image and does
not require the RISC-V GNU linker.

The workflow scripts set `CARGO_TARGET_DIR` by default so macOS host checks and
Linux container checks do not invalidate each other's Cargo outputs. Override it
explicitly if you want a custom cache location.

## Compile-Only RISC-V Spike

The first compile-only target uses Rust's built-in bare-metal RISC-V target:

```sh
rustup target add riscv64gc-unknown-none-elf
QSOE_RUST_COMPILE=1 scripts/rust-check.sh
```

That proves the minimal `no_std` crate can compile for RISC-V and emit a Rust
artifact. It is not yet a QSOE executable.

## QSOE Link Smoke

Once the normal QSOE C tree has been built in a Linux/container environment
with `riscv64-linux-gnu-gcc`, run:

```sh
make rust-qsoe-link-smoke
```

The workflow alias is:

```sh
make rust-abi
```

This links the minimal Rust staticlib behind the existing QSOE startup object:

```text
crt0.o -> main(argc, argv, envp) -> _exit(status)
```

The smoke target preserves the current QSOE userland contract:

- QSOE `crt0.o`.
- QSOE `libc.so`.
- `/lib/ld-qsoe.so.1`.
- ET_EXEC / non-PIE.
- `-nostdlib`.
- eager binding with `-z now`.

The script audits the linked ELF when a compatible `readelf` tool is available.

The first Rust service pilot can be linked and audited directly:

```sh
make rust-slogger-link-smoke
```

It builds `qsoe-slogger-rs` as a no-std staticlib and links it through the same
QSOE userland CRT/libc path. The C `slogger` service is retired; normal image
packaging now stages this Rust artifact as `/sbin/slogger`.

The shared direct-service bootstrap example can be linked with:

```sh
make rust-service-example-link-smoke
```

It builds `qsoe-service-example-rs`, a tiny `/dev/rust-example` service that
uses the same `DirectServer` wrapper path as `slogger-rs`. The package README
documents its minimal connect, write, read, close, and unsupported-request
replies.

The minimal Rust link-smoke binary also carries the first shared parser reuse
check: it parses a static `newc` archive through `qsoe-cpio` before returning
success from `main`. The same path runs as a host test:

```sh
cargo test --manifest-path rust/Cargo.toml -p qsoe-minimal-rs --features host-tests
```

## Slogger Selection

The tracked handover tree uses component override patches to retire the C
`quser/sbin/slogger` source and make NQ/LQ CPIO packaging consume a stable
Rust artifact:

```sh
make slogger-artifact
```

The target links `qsoe-slogger-rs` through the QSOE userland path and writes
the selected binary to `build/rust/selected/sbin/slogger.elf`. Setting
`QSOE_RUST_SLOGGER=0` is rejected because the C service has been removed from
the tracked `quser` component override.

The LQ boot and readback smokes use that selected artifact:

```sh
make rust-slogger-boot-smoke
make rust-slog-readback-smoke
```

It builds a temporary `build/rust-slogger/modpkg-lq-rust-slogger.cpio`,
rebuilds the LQ QEMU image with `MODPKG_CPIO` pointing at that archive, and
waits for both `[slogger-rs] alive` and `login:`.

The readback smoke uses the same Rust-selected image path, boots without the
virtio disk so QSOE/L enters the rescue shell, runs `/bin/sloginfo`, and
verifies that boot-time `pci-server` messages are readable through `/dev/slog`.

The compatibility RC target now exercises the same Rust-only image path:

```sh
make slogger-rc-readback-smoke
```

`make slogger-rc-readback-smoke` prepares an image with `slogger-rs` staged as
`/sbin/slogger`. `QSOE_SLOGGER_RC_ROLLBACK=1` is rejected after retirement; the
historical rollback drill is documented in
`docs/rust-migration/SLOGGER_RC.md`.

## Virtio Driver Selection

The C `devb-virtio` driver is retired. The Rust virtio block driver can still
be linked and audited directly:

```sh
make rust-virtio-link-smoke
```

It builds `qsoe-devb-virtio-rs` as a no-std staticlib and links it with
`libressrv` through the same QSOE userland CRT/libc path. The selected artifact
target always stages Rust:

```sh
make virtio-artifact
```

The target links and audits `qsoe-devb-virtio-rs`, then writes the selected
binary to `build/rust/selected/sbin/devb-virtio.elf`. Setting
`QSOE_RUST_VIRTIO=0` is rejected because the C driver has been removed from the
tracked `quser` component override.

The LQ boot smoke uses that selected artifact:

```sh
make rust-virtio-boot-smoke
```

It builds a temporary `build/rust-virtio/modpkg-lq-base.cpio`, rebuilds the LQ
QEMU image with `MODPKG_CPIO` pointing at that archive, and waits for
`[devb-virtio-rs] /dev/vblk0 ready`, the `/usr` qrvfs mount, and `login:`.

The file-access smoke adds an in-guest `/usr` read check on top of the same
Rust virtio boot path:

```sh
make rust-virtio-file-smoke
```

It temporarily stages a `/usr/conf/sysinit` fragment into the qrvfs image; that
fragment runs after `/usr` is mounted and prints
`rust-virtio-file-smoke: read /usr/conf/passwd ok` only after `/bin/cat` can
read the file through the Rust-backed `/dev/vblk0` mount.

The historical release-candidate command remains as a Rust-only compatibility
smoke:

```sh
make virtio-rc-file-smoke
```

`make virtio-rc-file-smoke` stages `devb-virtio-rs` and verifies the `/usr`
mount plus file-read marker. Setting `QSOE_VIRTIO_RC_ROLLBACK=1` is rejected
because the rollback target was removed by the C retirement.

## Test Msgpass Selection

The C `test_msgpass` helper is retired. The Rust `test_msgpass-rs` helper can
still be linked and audited directly:

```sh
make rust-test-msgpass-link-smoke
```

The selected artifact target always stages the Rust helper at the stable image
path:

```sh
make test-msgpass-artifact
```

The target links and audits `qsoe-test-msgpass-rs`, then writes the selected
binary to `build/rust/selected/usr/bin/test_msgpass.elf`. Setting
`QSOE_RUST_TEST_MSGPASS=0` is rejected because the C helper has been removed
from the tracked `quser` component override.

The smoke stages the Rust helper into a temporary qrvfs image and runs the
existing suite `[msgpass]` path:

```sh
make rust-test-msgpass-smoke
```

The compatibility RC target now exercises the same Rust-only path:

```sh
make test-msgpass-rc-smoke
```

Both smokes verify the suite `[msgpass]` PASS/SKIP markers and the Rust helper
startup marker. `QSOE_TEST_MSGPASS_RC_ROLLBACK=1` is rejected after retirement;
the historical rollback drill is documented in
`docs/rust-migration/TEST_MSGPASS_RC.md`.

## Pipe Selection

The retired Rust pipe manager can be linked and audited as the current
`/sbin/pipe` implementation:

```sh
make rust-pipe-link-smoke
```

It builds `qsoe-pipe-rs` as a no-std staticlib and links it through the same
QSOE userland CRT/libc path. The selected artifact target always stages Rust:

```sh
make pipe-artifact
```

`make pipe-artifact` links and audits `qsoe-pipe-rs`, then writes the selected
binary to `build/rust/selected/sbin/pipe.elf`. `QSOE_RUST_PIPE=0` is rejected
after C retirement.

The LQ boot smoke validates Rust `/sbin/pipe` registration:

```sh
make rust-pipe-smoke
```

It injects a temporary `/usr/conf/sysinit` fragment that starts `/sbin/pipe`,
then verifies `[pipe-rs] /dev/pipe registered`, the fragment marker, and the
normal login boot milestones.

The data-path smoke also stages a focused guest helper into the temporary
qrvfs image:

```sh
make rust-pipe-data-smoke
```

It starts the Rust pipe service from sysinit, calls normal libc `pipe(2)`, and
verifies one write/read round trip plus EOF after closing the writer. The
compatibility RC target `make pipe-rc-data-smoke` now exercises the same
Rust-only path; `QSOE_PIPE_RC_ROLLBACK=1` is rejected.

## Task Manager `/proc` Selection

The C `tm_procfs` provider is retired. The Rust provider remains buildable as a
focused soft-float taskman staticlib, and normal NQ/LQ taskman links now carry
it through the shared provider archive:

```sh
make rust-tm-procfs-provider
make tm-procfs-evidence
make procfs-smoke
```

`QSOE_RUST_TM_PROCFS` must be `1`; setting it to `0` fails fast because
`libtaskman/src/tm_procfs.c` has been removed. The taskman link omits
`tm_procfs.o`, builds `qsoe-tm-procfs` for `riscv64imac-unknown-none-elf`, and
links it through `libqsoe_tm_providers.a`. Process lifecycle, spawn, loader,
seL4 invocation code, and LQ `/proc` glue remain C.

The historical release-candidate command remains as a Rust-only compatibility
smoke:

```sh
make tm-procfs-rc-smoke
```

`make tm-procfs-rc-smoke` verifies `/bin/ls /proc` plus `/proc/1/info` through
taskman's existing LQ procfs glue. `TM_PROCFS_RC_ROLLBACK=1` is rejected after
C retirement; the prior rollback drill is documented in
`docs/rust-migration/TASK_MANAGER_PROCFS_RC.md`.

## Task Manager CPIO Selection

The Rust `tm_cpio` provider is retired as the mandatory taskman CPIO archive
model provider:

```sh
make check-tm-cpio-model
make rust-tm-cpio-provider
make tm-cpio-evidence
make tm-cpio-runtime-smoke
make tm-cpio-rc-smoke
```

With the default `QSOE_RUST_TM_CPIO=1`, NQ and LQ taskman omit C `cpio.o`,
build `qsoe-tm-cpio` for `riscv64imac-unknown-none-elf`, and link the shared
`qsoe-tm-providers` archive into taskman. `QSOE_RUST_TM_CPIO=0` now fails fast
because the C `cpio.o` rollback provider is retired. CPIO-backed file
descriptor state, path dispatch, spawn, ELF loading, relocation, process tables,
and seL4 invocation code remain C.

`make tm-cpio-runtime-smoke` boots QSOE/L with Rust `tm_cpio` selected and
checks CPIO-root symlink readlink output, `/etc/passwd` through the `/etc`
symlink, direct boot-CPIO `/sbin/init` reads, and `/bin/sh` symlink spawn.
`make tm-cpio-rc-smoke` first audits default Rust archive selection, then runs
the same live path.

## Task Manager Shebang Parser Selection

The Rust `tm_script` provider is retired as the mandatory taskman shebang
parser provider:

```sh
make check-tm-script-model
make rust-tm-script-provider
make tm-script-evidence
make tm-script-runtime-smoke
make tm-script-rc-smoke
```

With the default `QSOE_RUST_TM_SCRIPT=1`, NQ and LQ taskman omit C `script.o`,
build `qsoe-tm-script` for `riscv64imac-unknown-none-elf`, and link the shared
`qsoe-tm-providers` archive into taskman. `QSOE_RUST_TM_SCRIPT=0` now fails
fast because the C `script.o` rollback provider is retired. Interpreter loading,
argv construction, CPIO lookup, ELF loading, relocation, process tables, and
seL4 invocation code remain C.

`make tm-script-runtime-smoke` boots QSOE/L with Rust `tm_script` selected,
stages `/usr/bin/tm_script_probe` as a temporary shell script, and runs it
directly so taskman must parse the shebang before loading `/bin/sh`.
`make tm-script-rc-smoke` first audits default Rust archive selection, then
runs the same live path. `TM_SCRIPT_RC_ROLLBACK=1 scripts/tm-script-rc-smoke.sh`
fails fast after retirement.

## Task Manager ELF View Parser Selection

The C `tm_elf` provider is retired. The Rust provider remains buildable as the
mandatory portable taskman ELF view parser:

```sh
make check-tm-elf-model
make rust-tm-elf-provider
make tm-elf-evidence
make tm-elf-runtime-smoke
make tm-elf-rc-smoke
```

With the default `QSOE_RUST_TM_ELF=1`, NQ and LQ taskman omit C `elf.o`, build
`qsoe-tm-elf` for `riscv64imac-unknown-none-elf`, and link it through the
shared `libqsoe_tm_providers.a` taskman provider archive. `QSOE_RUST_TM_ELF=0`
now fails fast because the C `elf.o` rollback provider is retired. Segment
mapping, dynamic-linker handling, relocation, process tables, and seL4
invocation code remain C.

`make tm-elf-rc-smoke` first audits default Rust archive selection, then boots
QSOE/L, verifies the staged `/usr/bin/sysinfo` has a program interpreter, and
runs it from sysinit. Because `sysinfo` is a dynamic ELF, the smoke covers
Rust `tm_elf_parse` in the dynamic spawn path while the loader and relocation
logic remain C.

## Task Manager FDT Parser Selection

The Rust LQ `tm_fdt` provider is the Rust-default RC path for the FDT parser:

```sh
make check-tm-fdt-model
make rust-tm-fdt-provider
make tm-fdt-evidence
make tm-fdt-runtime-smoke
make tm-fdt-rc-smoke
make tm-fdt-rc-rollback-smoke
```

With the default `QSOE_RUST_TM_FDT=1`, the component Makefile selector omits C
`sys/fdt.o`, builds `qsoe-tm-fdt` for `riscv64imac-unknown-none-elf`, and links
the shared `qsoe-tm-providers` archive into taskman. With
`QSOE_RUST_TM_FDT=0`, LQ taskman links the existing C `sys/fdt.o` rollback.
FDT discovery, syscfg/sysmap policy, initrd handling, process tables, and seL4
invocation code remain C.

`make tm-fdt-rc-smoke` boots QSOE/L with Rust `tm_fdt` selected by default,
verifies the Rust-default LQ taskman link plan omits C `sys/fdt.o`, and checks the
booted FDT consumers through `/chosen` bootargs, syscfg/sysmap construction,
`/sys/board`, `/sys/cmdline`, and `/usr/bin/sysinfo`.

## Task Manager Syscfg Selection

The Rust `tm_syscfg` provider is the retired Rust-only implementation for the
portable taskman syscfg TLV helpers:

```sh
make check-tm-syscfg-model
make rust-tm-syscfg-provider
make tm-syscfg-evidence
make tm-syscfg-runtime-smoke
make tm-syscfg-rc-smoke
```

With mandatory `QSOE_RUST_TM_SYSCFG=1`, NQ and LQ taskman omit C
`syscfg.o`, build `qsoe-tm-syscfg` for `riscv64imac-unknown-none-elf`, and
link it through the shared `qsoe-tm-providers` archive.
`QSOE_RUST_TM_SYSCFG=0` now fails fast because the C provider is retired.
LQ's private FDT-backed `lq/taskman/sys/syscfg.c`, sysmap construction, boot
platform-data policy, `/sys` serving, process tables, and seL4 invocation code
remain C.

`make tm-syscfg-runtime-smoke` boots QSOE/L with Rust `tm_syscfg` selected,
verifies the C `syscfg.o` is absent from the selected `libtaskman.a`, and
checks syscfg-backed runtime consumers through `/sys/board`, `/sys/cmdline`,
and `/usr/bin/sysinfo`. `make tm-syscfg-rc-smoke` verifies the default Rust
archive membership plus the same runtime path. This is a boot-consumer
compatibility smoke; the LQ private runtime syscfg builder remains C.

## Task Manager Path Registry Selection

The Rust `tm_pathmgr` provider is the retired Rust-only implementation for the
portable taskman path registry:

```sh
make check-tm-pathmgr-model
make rust-tm-pathmgr-provider
make tm-pathmgr-evidence
make tm-pathmgr-runtime-smoke
make tm-pathmgr-rc-smoke
```

With mandatory `QSOE_RUST_TM_PATHMGR=1`, NQ and LQ taskman omit C
`pathmgr.o`, build `qsoe-tm-pathmgr` for `riscv64imac-unknown-none-elf`, and
link the shared `libqsoe_tm_providers.a` archive into taskman.
`QSOE_RUST_TM_PATHMGR=0` and `TM_PATHMGR_RC_ROLLBACK=1` now fail fast because
the C `pathmgr.o` rollback provider is retired.
Path IO dispatch, FD ownership, CPIOFS/PROCFS/SYSFS serving, device-server
registration policy, process tables, and seL4 invocation code remain C.

`make tm-pathmgr-rc-smoke` boots QSOE/L with Rust `tm_pathmgr` selected,
verifies C `pathmgr.o` is absent from the selected `libtaskman.a`, and checks
runtime consumers through `/dev` readdir, `/etc` symlink file access,
`/dev/console` repath, dynamic helper registration, duplicate registration
rejection, MsgSend through the resolved external binding, and
unregister-on-exit cleanup.

## Task Manager Sysmap Selection

The Rust LQ `tm_sysmap` provider is the retired Rust-only implementation for
the LQ taskman sysmap page builder:

```sh
make check-tm-sysmap-model
make rust-tm-sysmap-provider
make tm-sysmap-evidence
make tm-sysmap-runtime-smoke
make tm-sysmap-rc-smoke
```

With mandatory `QSOE_RUST_TM_SYSMAP=1`, LQ taskman omits C `sys/sysmap.o`,
builds `qsoe-tm-sysmap` for `riscv64imac-unknown-none-elf`, and links the
shared `libqsoe_tm_providers.a` archive into taskman.
`QSOE_RUST_TM_SYSMAP=0` now fails fast because the C `sys/sysmap.o` rollback
provider is retired. FDT parsing, syscfg construction, process-table
ownership, child VSpace mapping, and seL4 invocation code remain C.

`make tm-sysmap-rc-smoke` verifies the retired/default LQ taskman link plan omits C
`sys/sysmap.o`, boots QSOE/L, and checks a spawned `/usr/bin/sysinfo` child for
the QEMU timebase, PLIC, and PCI output emitted from the mapped `PSYS` page.
`TM_SYSMAP_RC_ROLLBACK=1 scripts/tm-sysmap-rc-smoke.sh` and
`QSOE_RUST_TM_SYSMAP=0` now fail fast after retirement.

## Task Manager Credential Selection

The Rust `tm_cred` provider is a retired/Rust-only taskman provider:

```sh
make check-tm-cred-model
make rust-tm-cred-provider
make tm-cred-evidence
make tm-cred-runtime-smoke
make tm-cred-rc-smoke
```

With mandatory `QSOE_RUST_TM_CRED=1`, NQ and LQ taskman omit C `cred.o`, build
`qsoe-tm-cred` for `riscv64imac-unknown-none-elf`, and link the shared
`libqsoe_tm_providers.a` archive into taskman. `QSOE_RUST_TM_CRED=0` now fails
fast because the C `cred.o` rollback provider is retired. Process-table
ownership, IPC decoding, filesystem-backed path validation, and seL4 invocation
code remain C.

`make tm-cred-rc-smoke` boots QSOE/L with Rust `tm_cred` selected, verifies the
selected `libtaskman.a` omits C `cred.o`, and runs `/usr/bin/cred_probe` from
sysinit. The helper exercises live uid/gid mutation, held-id transitions,
non-root `EPERM` rejection, cwd and umask state, and child spawn inheritance.
`TM_CRED_RC_ROLLBACK=1 scripts/tm-cred-rc-smoke.sh` now fails fast after
retirement.

## Task Manager Pseudo-device Selection

The Rust LQ taskman pseudo-device provider is the retired Rust-only
implementation for `/dev/null` and `/dev/zero`:

```sh
make rust-tm-pseudodev-provider
make tm-pseudodev-evidence
make tm-pseudodev-runtime-smoke
make tm-pseudodev-rc-smoke
```

With mandatory `QSOE_RUST_TM_PSEUDODEV=1`, LQ taskman omits C `devnull.o` and
`devzero.o`, builds `qsoe-tm-pseudodev` for `riscv64imac-unknown-none-elf`,
and links the shared `libqsoe_tm_providers.a` archive into taskman.
`QSOE_RUST_TM_PSEUDODEV=0` and `TM_PSEUDODEV_RC_ROLLBACK=1` now fail fast
because the C pseudo-device rollback providers are retired. Path dispatch, fd
ownership, request decoding, process tables, and seL4 invocation code remain
C. The runtime smoke boots LQ with Rust `tm_pseudodev` selected and runs a
staged `/usr/bin/pseudodev_probe` helper through live `/dev/null` and
`/dev/zero` open, write, read, and fstat calls.

## Task Manager Resource DB Selection

The Rust LQ taskman resource DB provider is the retired Rust-only
implementation for LQ resource accounting:

```sh
make check-tm-rsrcdb-model
make rust-tm-rsrcdb-provider
make tm-rsrcdb-evidence
make tm-rsrcdb-runtime-smoke
make tm-rsrcdb-rc-smoke
```

With mandatory `QSOE_RUST_TM_RSRCDB=1`, LQ taskman omits C `sys/rsrcdb.o`,
builds `qsoe-tm-rsrcdb` for `riscv64imac-unknown-none-elf`, and links the
shared `libqsoe_tm_providers.a` archive into taskman.
`QSOE_RUST_TM_RSRCDB=0` and `TM_RSRCDB_RC_ROLLBACK=1` now fail fast because
the C `sys/rsrcdb.o` rollback provider is retired.
The libc `rsrcdbmgr_*` wrappers, taskman IPC dispatcher, IRQ handling, FDT and
syscfg construction, process tables, and seL4 invocation code remain C.
The runtime smoke boots LQ with Rust `tm_rsrcdb` selected and runs a staged
`/usr/bin/rsrcdb_probe` helper through live `rsrcdbmgr_*` create, attach,
query, detach, and destroy calls.

## Task Manager `/sys` Selection

The Rust `tm_sysfs` provider is mandatory after C provider retirement:

```sh
make check-tm-sysfs-model
make rust-tm-sysfs-provider
make tm-sysfs-evidence
make tm-sysfs-runtime-smoke
make tm-sysfs-rc-smoke
```

With mandatory `QSOE_RUST_TM_SYSFS=1`, NQ and LQ taskman omit C `tm_sysfs.o`,
build `qsoe-tm-sysfs` for `riscv64imac-unknown-none-elf`, and link the shared
`qsoe-tm-providers` archive into taskman. `QSOE_RUST_TM_SYSFS=0` now fails
fast. Sysmap/syscfg discovery, init path selection, open/read/readdir
dispatch, IPC decoding, process tables, and seL4 invocation code remain C.

`make tm-sysfs-runtime-smoke` boots QSOE/L with Rust `tm_sysfs` selected,
verifies the Rust-selected `libtaskman.a` omits C `tm_sysfs.o`, and checks a
sysinit child can enumerate `/sys` plus read `board`, `builddate`, `cmdline`,
`osname`, and `version`.
`make tm-sysfs-rc-smoke` first audits default Rust archive selection, then
runs the same live path.

## Parser Fuzzing

Parser fuzz targets live under `rust/fuzz` and are intentionally outside the
main workspace so default builds do not fetch fuzz-only dependencies.

Run the bounded local smoke with:

```sh
make rust-fuzz-smoke
```

The smoke runs cargo-fuzz against `qrvfs`, `cpio`, `elf`, `syscfg`, and
`sysmap`. The wrapper prefers `cargo +nightly fuzz` because cargo-fuzz needs
sanitizer flags that are not available on the pinned stable toolchain. Install
the optional tools with `rustup toolchain install nightly` and
`cargo install cargo-fuzz`. GPT should be added to the same fuzz package once a
Rust GPT parser crate exists.

## Coverage

Host-side parser and ABI coverage reports are optional and generated under the
ignored `build/` directory:

```sh
make rust-coverage
```

When `cargo-llvm-cov` is installed, the target writes
`build/rust-coverage/summary.txt` and `build/rust-coverage/lcov.info`.
Set `QSOE_RUST_COVERAGE_HTML=1` to also write an HTML report.

## Host qrvfs Parser

The first host-side Rust parser is:

```text
crates/qsoe-qrvfs
```

It reads qrvfs images and includes `qrvfs-tree`, a tree-format inspector that is
diffed against the current C `treeqrvfs` output:

```sh
make check-qrvfs-rust-fixture
```

The read-only inspector has a Rust-default release-candidate selector:

```sh
make treeqrvfs-rc-smoke
make treeqrvfs-rc-rollback-smoke
```

`make tree` builds `build/treeqrvfs` from Rust `qrvfs-tree` by default. Set
`QSOE_RUST_TREEQRVFS=0` to select the C `host_tools/treeqrvfs.c` rollback
artifact instead. The inspector path is read-only; the C `mkfs-qrv` tool
remains the default writer and source of truth for production image
construction.

The first opt-in Rust writer fixture is:

```sh
make check-qrvfs-rust-writer-fixture
make check-qrvfs-rust-writer-production-root
make rust-mkfs-qrv-live-smoke
```

The fixture smoke builds a small image with `mkfs-qrv-rs`, then inspects that
image with the C `treeqrvfs` oracle. The fixture includes a large file that
crosses into the double-indirect allocation path. The production-root smoke
rebuilds the normal staged qrvfs root, writes a Rust image from that root, and
checks the C and Rust-written images with the C oracle. `mkfs-qrv-rs` also uses
sparse regular-file target initialization and the C writer's block-device
metadata zeroing strategy. The live smoke selects Rust `mkfs-qrv-rs`, boots
QSOE/L from the resulting virtio disk, and reads `/usr/conf/passwd`.
Production image generation still uses C `mkfs-qrv`.

## Host CPIO Parser

The first shared archive parser is:

```text
crates/qsoe-cpio
```

It parses `newc` CPIO archives, exposes borrowed entries by iterator, index, or
path lookup, and reports archive info such as file count and maximum path
length. The crate is dependency-free and `no_std`; host tests cover a valid
archive plus malformed headers, names, UTF-8, and truncated data so parser
errors stay explicit instead of panicking.

## Host Sysview Parser

The first read-only system-configuration view crate is:

```text
crates/qsoe-sysview
```

It covers both legacy `syscfg` TLV blobs and the page-based `sysmap` TLV stream.
The crate is dependency-free and `no_std`; it exposes borrowed TLVs plus
bounds-checked helpers for u32/u64 fields, C strings, common sysmap ranges, the
mtime frequency, and the command line. Tests cover valid views and malformed
inputs so fields are only exposed after their containing record and requested
body range have been validated.

## Host ELF Inspector

The first read-only ELF inspection crate is:

```text
crates/qsoe-elf
```

It parses ELF64 little-endian section tables and REL/RELA relocation entries
without dependencies and remains `no_std` compatible. Host tests cover a
synthetic ELF plus the current representative QSOE userland binaries when they
are available. The required fixture gate is:

```sh
make check-elf-reloc-fixture
```

That target runs the existing-binary relocation test with
`QSOE_ELF_FIXTURES_REQUIRED=1`, so CI/container checks fail if the built QSOE
ELFs are missing or their relocation type counts drift from
`docs/rust-migration/ELF_BASELINE.md`.

## Virtio MMIO Wrapper

The first Rust driver-support crate is:

```text
crates/qsoe-virtio
```

It contains legacy virtio-mmio register constants and `VirtioMmio`, a no-std
volatile register wrapper for the `devb-virtio-rs` driver. Host tests
exercise the wrapper against an in-memory register array. The crate also models
the C virtqueue descriptor, available-ring, used-ring, and block-request
layouts, with explicit descriptor ownership, device mutability metadata, and
host-side descriptor free-list tests. The C driver is retired; normal image
packaging now stages Rust `devb-virtio-rs` at `/sbin/devb-virtio`.

The driver binary is:

```text
bins/devb-virtio-rs
```

It discovers the same QEMU virtio-mmio slots, initializes one legacy block
queue, publishes `/dev/vblk0` through `libressrv`, and keeps writes disabled on
the resource-server surface.
