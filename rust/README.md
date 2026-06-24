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

The first Rust service pilot can be linked without selecting it for the boot
image:

```sh
make rust-slogger-link-smoke
```

It builds `qsoe-slogger-rs` as a no-std staticlib and links it through the same
QSOE userland CRT/libc path. The C `slogger` remains the default service until
the explicit build flag and boot smoke steps land.

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

The tracked handover tree does not edit the ignored `quser/` component
Makefiles directly. Instead, it exposes a stable selected artifact for later
CPIO/image packaging:

```sh
make slogger-artifact
QSOE_RUST_SLOGGER=1 make slogger-artifact
```

With the default `QSOE_RUST_SLOGGER=0`, the target stages the existing C
`quser/build/sbin/slogger/slogger.elf`. With `QSOE_RUST_SLOGGER=1`, it first
links `qsoe-slogger-rs` through the QSOE userland path. Both modes write the
selected binary to `build/rust/selected/sbin/slogger.elf`.

The opt-in LQ boot smoke uses that selected artifact without changing the C
default:

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
`build/rust/selected/sbin/devb-virtio.elf`; the C driver remains the boot
default until the explicit Rust boot-smoke step lands.

The opt-in LQ boot smoke uses that selected artifact without changing the C
default:

```sh
make rust-virtio-boot-smoke
```

It builds a temporary `build/rust-virtio/modpkg-lq-rust-virtio.cpio`, rebuilds
the LQ QEMU image with `MODPKG_CPIO` pointing at that archive, and waits for
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
normal login boot milestones. This is a registration smoke; a pipe data-path
smoke still depends on the libc/taskman pipe-creation path being fully wired.

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

This crate is read-only. The C `mkfs-qrv` tool remains the writer and source of
truth for image construction.

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
