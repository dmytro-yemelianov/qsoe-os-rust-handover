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

The opt-in Rust virtio block driver can be linked and audited without changing
the boot default:

```sh
make rust-virtio-link-smoke
```

It builds `qsoe-devb-virtio-rs` as a no-std staticlib and links it with
`libressrv` through the same QSOE userland CRT/libc path. The selected artifact
target mirrors the slogger pattern:

```sh
make virtio-artifact
QSOE_RUST_VIRTIO=1 make virtio-artifact
```

With the default `QSOE_RUST_VIRTIO=0`, the target stages the existing C
`quser/build/dev/virtio/devb-virtio.elf`. With `QSOE_RUST_VIRTIO=1`, it first
links and audits `qsoe-devb-virtio-rs`. Both modes write the selected binary to
`build/rust/selected/sbin/devb-virtio.elf`; non-RC normal builds keep the C
driver selected unless the Rust flag is set explicitly.

The opt-in LQ boot smoke uses that selected artifact without changing the C
default:

```sh
make rust-virtio-boot-smoke
```

It builds a temporary `build/rust-virtio/modpkg-lq-rust-virtio.cpio`, rebuilds
the LQ QEMU image with `MODPKG_CPIO` pointing at that archive, and waits for
`[devb-virtio-rs] /dev/vblk0 ready`, the `/usr` qrvfs mount, and `login:`.
Set `QSOE_RUST_VIRTIO=0` to run the same selected-artifact boot path with the
C driver.

The file-access smoke adds an in-guest `/usr` read check on top of the same
Rust virtio boot path:

```sh
make rust-virtio-file-smoke
```

It temporarily stages a `/usr/conf/sysinit` fragment into the qrvfs image; that
fragment runs after `/usr` is mounted and prints
`rust-virtio-file-smoke: read /usr/conf/passwd ok` only after `/bin/cat` can
read the file through the Rust-backed `/dev/vblk0` mount.

The release-candidate path makes Rust the default for the targeted file-read
image while keeping an explicit C rollback drill:

```sh
make virtio-rc-file-smoke
make virtio-rc-rollback-smoke
```

`make virtio-rc-file-smoke` selects `devb-virtio-rs` by default and verifies
the `/usr` mount plus file-read marker. `make virtio-rc-rollback-smoke` sets
`QSOE_VIRTIO_RC_ROLLBACK=1` and verifies the same marker with the C driver
restored.

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

The opt-in Rust pipe manager can be linked and audited without changing the
boot default:

```sh
make rust-pipe-link-smoke
```

It builds `qsoe-pipe-rs` as a no-std staticlib and links it through the same
QSOE userland CRT/libc path. The selected artifact target mirrors the other
service opt-ins:

```sh
make pipe-artifact
QSOE_RUST_PIPE=1 make pipe-artifact
```

With the default `QSOE_RUST_PIPE=0`, the target stages the existing C
`quser/build/sbin/pipe/pipe.elf`. With `QSOE_RUST_PIPE=1`, it first links and
audits `qsoe-pipe-rs`. Both modes write the selected binary to
`build/rust/selected/sbin/pipe.elf`; the C service remains the boot default.

The opt-in LQ boot smoke replaces only `/sbin/pipe` in a temporary boot CPIO:

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

It keeps C as the default outside the smoke, replaces only `/sbin/pipe` in a
temporary boot CPIO, starts the Rust pipe service from sysinit, calls normal
libc `pipe(2)`, and verifies one write/read round trip plus EOF after closing
the writer.

## Task Manager `/proc` Selection

The Rust `tm_procfs` provider can be built as a soft-float taskman staticlib
without changing the normal taskman default:

```sh
make rust-tm-procfs-provider
make tm-procfs-evidence
QSOE_RUST_TM_PROCFS=1 make procfs-smoke
```

With the default `QSOE_RUST_TM_PROCFS=0`, NQ and LQ taskman link the existing
C `tm_procfs.o`. With `QSOE_RUST_TM_PROCFS=1`, the component Makefile selector
omits C `tm_procfs.o`, builds `qsoe-tm-procfs` for
`riscv64imac-unknown-none-elf`, and links `libqsoe_tm_procfs.a` into taskman.
Process lifecycle, spawn, loader, seL4 invocation code, and LQ `/proc` glue
remain C.

The release-candidate path makes Rust the default for the targeted `/proc`
smoke image while keeping an explicit C rollback drill:

```sh
make tm-procfs-rc-smoke
make tm-procfs-rc-rollback-smoke
```

`make tm-procfs-rc-smoke` selects `qsoe-tm-procfs` by default and verifies
`/bin/ls /proc` plus `/proc/1/info` through taskman's existing LQ procfs glue.
`make tm-procfs-rc-rollback-smoke` sets `TM_PROCFS_RC_ROLLBACK=1` and verifies
the same markers with the C provider restored.

## Task Manager CPIO Selection

The Rust `tm_cpio` provider can be built as a soft-float taskman staticlib
without changing the normal taskman default:

```sh
make check-tm-cpio-model
make rust-tm-cpio-provider
make tm-cpio-evidence
```

With the default `QSOE_RUST_TM_CPIO=0`, NQ and LQ taskman link the existing
C `cpio.o`. With `QSOE_RUST_TM_CPIO=1`, the component Makefile selector omits
C `cpio.o`, builds `qsoe-tm-cpio` for `riscv64imac-unknown-none-elf`, and
links `libqsoe_tm_cpio.a` into taskman. CPIO-backed file descriptor state,
path dispatch, spawn, ELF loading, relocation, process tables, and seL4
invocation code remain C.

## Task Manager Shebang Parser Selection

The Rust `tm_script` provider can be built as a soft-float taskman staticlib
without changing the normal taskman default:

```sh
make check-tm-script-model
make rust-tm-script-provider
make tm-script-evidence
```

With the default `QSOE_RUST_TM_SCRIPT=0`, NQ and LQ taskman link the existing
C `script.o`. With `QSOE_RUST_TM_SCRIPT=1`, the component Makefile selector
omits C `script.o`, builds `qsoe-tm-script` for
`riscv64imac-unknown-none-elf`, and links `libqsoe_tm_script.a` into taskman.
Interpreter loading, argv construction, CPIO lookup, ELF loading, relocation,
process tables, and seL4 invocation code remain C.

## Task Manager ELF View Parser Selection

The Rust `tm_elf` provider can be built as a soft-float taskman staticlib
without changing the normal taskman default:

```sh
make check-tm-elf-model
make rust-tm-elf-provider
make tm-elf-evidence
```

With the default `QSOE_RUST_TM_ELF=0`, NQ and LQ taskman link the existing
C `elf.o`. With `QSOE_RUST_TM_ELF=1`, the component Makefile selector omits
C `elf.o`, builds `qsoe-tm-elf` for `riscv64imac-unknown-none-elf`, and links
`libqsoe_tm_elf.a` into taskman. Segment mapping, dynamic-linker handling,
relocation, process tables, and seL4 invocation code remain C.

## Task Manager FDT Parser Selection

The Rust LQ `tm_fdt` provider can be built as a soft-float taskman staticlib
without changing the normal taskman default:

```sh
make check-tm-fdt-model
make rust-tm-fdt-provider
make tm-fdt-evidence
```

With the default `QSOE_RUST_TM_FDT=0`, LQ taskman links the existing C
`sys/fdt.o`. With `QSOE_RUST_TM_FDT=1`, the component Makefile selector omits
C `sys/fdt.o`, builds `qsoe-tm-fdt` for `riscv64imac-unknown-none-elf`, and
links `libqsoe_tm_fdt.a` into taskman. FDT discovery, syscfg/sysmap policy,
initrd handling, process tables, and seL4 invocation code remain C.

## Task Manager Syscfg Selection

The Rust `tm_syscfg` provider can be built as a soft-float taskman staticlib
without changing the normal taskman default:

```sh
make check-tm-syscfg-model
make rust-tm-syscfg-provider
make tm-syscfg-evidence
```

With the default `QSOE_RUST_TM_SYSCFG=0`, NQ and LQ taskman link the existing
C `syscfg.o` in `libtaskman.a`. With `QSOE_RUST_TM_SYSCFG=1`, the component
Makefile selector omits C `syscfg.o`, builds `qsoe-tm-syscfg` for
`riscv64imac-unknown-none-elf`, and links `libqsoe_tm_syscfg.a` into taskman.
LQ's private FDT-backed `lq/taskman/sys/syscfg.c`, sysmap construction, boot
platform-data policy, `/sys` serving, process tables, and seL4 invocation code
remain C.

## Task Manager Path Registry Selection

The Rust `tm_pathmgr` provider can be built as a soft-float taskman staticlib
without changing the normal taskman default:

```sh
make check-tm-pathmgr-model
make rust-tm-pathmgr-provider
make tm-pathmgr-evidence
```

With the default `QSOE_RUST_TM_PATHMGR=0`, NQ and LQ taskman link the existing
C `pathmgr.o` in `libtaskman.a`. With `QSOE_RUST_TM_PATHMGR=1`, the component
Makefile selector omits C `pathmgr.o`, builds `qsoe-tm-pathmgr` for
`riscv64imac-unknown-none-elf`, and links `libqsoe_tm_pathmgr.a` into taskman.
Path IO dispatch, FD ownership, CPIOFS/PROCFS/SYSFS serving, device-server
registration policy, process tables, and seL4 invocation code remain C.

## Task Manager Sysmap Selection

The Rust LQ `tm_sysmap` provider can be built as a soft-float taskman staticlib
without changing the normal taskman default:

```sh
make check-tm-sysmap-model
make rust-tm-sysmap-provider
make tm-sysmap-evidence
```

With the default `QSOE_RUST_TM_SYSMAP=0`, LQ taskman links the existing C
`sys/sysmap.o`. With `QSOE_RUST_TM_SYSMAP=1`, the component Makefile selector
omits C `sys/sysmap.o`, builds `qsoe-tm-sysmap` for
`riscv64imac-unknown-none-elf`, and links `libqsoe_tm_sysmap.a` into taskman.
FDT parsing, syscfg construction, process-table ownership, child VSpace
mapping, and seL4 invocation code remain C.

## Task Manager Credential Selection

The Rust `tm_cred` provider can be built as a soft-float taskman staticlib
without changing the normal taskman default:

```sh
make check-tm-cred-model
make rust-tm-cred-provider
make tm-cred-evidence
```

With the default `QSOE_RUST_TM_CRED=0`, NQ and LQ taskman link the existing
C `cred.o`. With `QSOE_RUST_TM_CRED=1`, the component Makefile selector omits
C `cred.o`, builds `qsoe-tm-cred` for `riscv64imac-unknown-none-elf`, and
links `libqsoe_tm_cred.a` into taskman. Process-table ownership, IPC decoding,
filesystem-backed path validation, and seL4 invocation code remain C.

## Task Manager Pseudo-device Selection

The Rust LQ taskman pseudo-device provider can be built as a soft-float
taskman staticlib without changing the normal taskman default:

```sh
make rust-tm-pseudodev-provider
make tm-pseudodev-evidence
```

With the default `QSOE_RUST_TM_PSEUDODEV=0`, LQ taskman links the existing C
`devnull.o` and `devzero.o`. With `QSOE_RUST_TM_PSEUDODEV=1`, the component
Makefile selector omits those two objects, builds `qsoe-tm-pseudodev` for
`riscv64imac-unknown-none-elf`, and links `libqsoe_tm_pseudodev.a` into
taskman. Path dispatch, fd ownership, request decoding, process tables, and
seL4 invocation code remain C.

## Task Manager Resource DB Selection

The Rust LQ taskman resource DB provider can be built as a soft-float taskman
staticlib without changing the normal taskman default:

```sh
make check-tm-rsrcdb-model
make rust-tm-rsrcdb-provider
make tm-rsrcdb-evidence
```

With the default `QSOE_RUST_TM_RSRCDB=0`, LQ taskman links the existing C
`sys/rsrcdb.o`. With `QSOE_RUST_TM_RSRCDB=1`, the component Makefile selector
omits C `sys/rsrcdb.o`, builds `qsoe-tm-rsrcdb` for
`riscv64imac-unknown-none-elf`, and links `libqsoe_tm_rsrcdb.a` into taskman.
The libc `rsrcdbmgr_*` wrappers, taskman IPC dispatcher, IRQ handling, FDT and
syscfg construction, process tables, and seL4 invocation code remain C.

## Task Manager `/sys` Selection

The Rust `tm_sysfs` provider can be built as a soft-float taskman staticlib
without changing the normal taskman default:

```sh
make check-tm-sysfs-model
make rust-tm-sysfs-provider
make tm-sysfs-evidence
```

With the default `QSOE_RUST_TM_SYSFS=0`, NQ and LQ taskman link the existing
C `tm_sysfs.o`. With `QSOE_RUST_TM_SYSFS=1`, the component Makefile selector
omits C `tm_sysfs.o`, builds `qsoe-tm-sysfs` for
`riscv64imac-unknown-none-elf`, and links `libqsoe_tm_sysfs.a` into taskman.
Sysmap/syscfg discovery, init path selection, open/read/readdir dispatch, IPC
decoding, process tables, and seL4 invocation code remain C.

Do not set more than one of `QSOE_RUST_TM_CPIO=1`,
`QSOE_RUST_TM_CRED=1`, `QSOE_RUST_TM_ELF=1`,
`QSOE_RUST_TM_FDT=1`, `QSOE_RUST_TM_PATHMGR=1`,
`QSOE_RUST_TM_PROCFS=1`,
`QSOE_RUST_TM_PSEUDODEV=1`,
`QSOE_RUST_TM_RSRCDB=1`, `QSOE_RUST_TM_SCRIPT=1`,
`QSOE_RUST_TM_SYSCFG=1`, `QSOE_RUST_TM_SYSMAP=1`, and
`QSOE_RUST_TM_SYSFS=1` together yet.
Current taskman providers are separate no-std Rust staticlibs; selecting more
than one requires a later shared taskman Rust archive.

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
volatile register wrapper for the future `devb-virtio-rs` pilot. Host tests
exercise the wrapper against an in-memory register array. The crate also models
the C virtqueue descriptor, available-ring, used-ring, and block-request
layouts, with explicit descriptor ownership, device mutability metadata, and
host-side descriptor free-list tests. The C driver remains the boot default.

The opt-in driver binary is:

```text
bins/devb-virtio-rs
```

It discovers the same QEMU virtio-mmio slots, initializes one legacy block
queue, publishes `/dev/vblk0` through `libressrv`, and keeps writes disabled on
the resource-server surface.
