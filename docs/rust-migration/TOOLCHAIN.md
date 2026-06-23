# QSOE Debian Container Toolchain

This is the reproducible Linux path for QSOE source builds and Rust link
smokes from a non-Linux host.

## Image

The toolchain image is defined by:

```text
toolchains/debian/Dockerfile
```

It is based on Debian trixie and installs:

- native build tools: `build-essential`, `make`, `cmake`, `ninja-build`,
  `cpio`, `device-tree-compiler`, `bc`, `bison`, `flex`, `file`, `rsync`.
- RISC-V cross tools: `gcc-riscv64-linux-gnu`,
  `binutils-riscv64-linux-gnu`.
- C indexing and analysis tools: `ripgrep`, `bear`, `clangd`, `clang-tidy`,
  `clang-tools`, `universal-ctags`, `cscope`, `global`, and `jq`.
- QEMU/OpenSBI packages: `qemu-system-misc`, `opensbi`.
- Python build support: `python3`, `python3-kconfiglib`, `python3-yaml`, and
  seL4's packaged Python generator dependencies such as `jinja2`, `ply`,
  `jsonschema`, and `pyelftools`.
- `pyfdt` from PyPI because Debian does not package the `pyfdt.pyfdt` module
  seL4 imports.
- Rust: pinned `1.95.0`, with `rustfmt`, `clippy`, `rust-analyzer`, and
  `riscv64gc-unknown-none-elf`.

The image does not copy source code. The wrapper mounts the checked-out
repository at:

```text
/work/qsoe/os
```

This path is stable even when the host checkout directory is not literally
named `os`, which keeps local clones and GitHub Actions checkouts equivalent.

## Runtime

The local host has Docker CLI and Colima installed. If Docker reports that the
Colima socket is missing, start Colima first:

```sh
colima start
```

Then build the image:

```sh
make container-toolchain-build
```

Open a shell:

```sh
make container-shell
```

The wrapper runs as the host uid/gid by default so generated files remain
editable on the host. To run as root inside the container:

```sh
QSOE_CONTAINER_ROOT=1 make container-shell
```

## Checks

Run host fixtures and Rust checks inside Debian:

```sh
make container-check
```

Run the full Rust-to-QSOE link smoke after the C tree has produced
`nq/build/libc/crt0.o` and `nq/build/libc/libc.so`:

```sh
make container-rust-qsoe-link-smoke
```

Build the C source tree inside the container:

```sh
make container-source-build
```

`container-source-build` runs `make prepare` only when release component
directories are missing. In an already-prepared tree it preserves detached
release tag checkouts and runs `make` directly.

## Direct Wrapper Use

The Make targets delegate to:

```sh
scripts/container-toolchain.sh
```

Useful direct commands:

```sh
scripts/container-toolchain.sh build
scripts/container-toolchain.sh check
scripts/container-toolchain.sh rust-link-smoke
scripts/container-toolchain.sh source-build
scripts/container-toolchain.sh run bash -c 'riscv64-linux-gnu-gcc --version'
```

Override the runtime or image tag:

```sh
CONTAINER_RUNTIME=podman scripts/container-toolchain.sh build
QSOE_TOOLCHAIN_IMAGE=qsoe-toolchain:dev make container-check
```

## Validated Baseline

This container path has been validated with:

```sh
make container-toolchain-build
make container-check
make container-source-build
make container-rust-qsoe-link-smoke
scripts/container-toolchain.sh run scripts/boot-smoke.sh -k lq -t 120
```

Observed tool versions:

- Rust `1.95.0`.
- RISC-V GCC `14.2.0`.
- GNU binutils `2.44`.
- QEMU `10.0.8`.
- Kconfiglib `14.1.0`.
- PyYAML `6.0.2`.
- Jinja2 `3.1.6`.

## Toolchain Notes

Debian bookworm's RISC-V GNU toolchain is too old for the current source tree:
it rejects the `zicntr` ISA extension used by the NQ build flags. Use the
checked-in trixie image or another toolchain new enough to accept
`-march=..._zicntr`.

Debian trixie's packaged QEMU may still be older than the QEMU `11.0.1` needed
for QSOE/N AIA MSI/MSI-X experiments. The container is sufficient for source
builds, artifact audit, and QSOE/L PLIC/virtio boot work. Use the host QEMU
`11.0.1` path or a newer custom QEMU package for QSOE/N AIA boot smokes.
