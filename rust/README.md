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
```

It builds a temporary `build/rust-slogger/modpkg-lq-rust-slogger.cpio`,
rebuilds the LQ QEMU image with `MODPKG_CPIO` pointing at that archive, and
waits for both `[slogger-rs] alive` and `login:`.

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
