# QSOE Migration Handover

Last updated: 2026-06-23 21:20 EEST.

This handover captures the current QSOE Rust migration and workflow work so it
can move from the macOS/container setup to a native Linux development machine.

## Repository Snapshot

Current local repository:

```text
/Users/dmytro/Documents/github/qsoe/os
```

Current upstream remote:

```text
origin https://gitlab.com/qsoe/os.git
```

Private GitHub handover remote:

```text
github-handover https://github.com/dmytro-yemelianov/qsoe-os-rust-handover.git
```

The local tree adds:

- migration planning docs under `docs/rust-migration/`;
- Debian container toolchain under `toolchains/debian/`;
- repeatable validation scripts under `scripts/`;
- a pinned Rust workspace under `rust/`;
- C indexing/clangd plumbing via `.clangd` and `scripts/c-index.sh`;
- top-level Make targets for checks, Rust workflow tiers, container workflow,
  ELF audits, boot smoke, and C indexes.

Generated build output stays out of git:

```text
build/
rust/target/
sel4-bootstrap/
```

## Linux Machine Setup

Recommended base:

- Debian Trixie or Ubuntu 24.04+ with a recent RISC-V GNU toolchain.
- Native Linux filesystem for the checkout.
- Optional Docker/Podman only for reproducing the checked-in container path.

Install the equivalent package set:

```sh
sudo apt update
sudo apt install -y \
  bash ripgrep bear bc binutils-riscv64-linux-gnu bison build-essential \
  ca-certificates clangd clang-tidy clang-tools cmake cpio curl \
  device-tree-compiler file flex gcc-riscv64-linux-gnu git global jq \
  libxml2-utils make ninja-build opensbi patch pkg-config python3 \
  python3-autopep8 python3-bs4 python3-dev python3-jinja2 \
  python3-jsonschema python3-kconfiglib python3-libarchive-c python3-lxml \
  python3-pexpect python3-ply python3-psutil python3-pyelftools \
  python3-setuptools python3-sh python3-six python3-yaml qemu-system-misc \
  rsync universal-ctags cscope xz-utils
```

Install `pyfdt` until the distro provides the `pyfdt.pyfdt` module:

```sh
curl --proto '=https' --tlsv1.2 -fsSL \
  https://files.pythonhosted.org/packages/source/p/pyfdt/pyfdt-0.3.tar.gz \
  | tar -xz -C /tmp
cd /tmp/pyfdt-0.3
sudo python3 setup.py install --prefix=/usr/local
```

Install Rust:

```sh
curl --proto '=https' --tlsv1.2 -fsSLo /tmp/rustup-init https://sh.rustup.rs
chmod +x /tmp/rustup-init
/tmp/rustup-init -y \
  --profile minimal \
  --default-toolchain 1.95.0 \
  --component clippy \
  --component rust-analyzer \
  --component rustfmt \
  --target riscv64gc-unknown-none-elf
```

## Restore Workflow On Linux

Clone the private handover repository created from this snapshot:

```sh
git clone https://github.com/dmytro-yemelianov/qsoe-os-rust-handover.git qsoe-os
cd qsoe-os
```

Prepare release components:

```sh
make prepare
```

Build from source:

```sh
make
```

Run fast local checks:

```sh
make check-host-tools
make rust-fast
make rust-quality
make check-qrvfs-rust-fixture
```

Run Rust ABI/link smoke after the C tree has produced `nq/build/libc/crt0.o`
and `nq/build/libc/libc.so`:

```sh
make rust-abi
```

Run the QSOE/L boot smoke:

```sh
scripts/boot-smoke.sh -k lq -t 120
```

Generate C source indexes:

```sh
make index-c-static
```

Capture a compile database for clangd after or during a rebuild:

```sh
QSOE_INDEX_CLEAN=1 make index-c-compile-db
```

If using a devcontainer/container-local clangd instead of host clangd:

```sh
QSOE_INDEX_DB_FLAVOR=container make index-c-compile-db
```

## Verified State Before Handover

The following checks passed in the macOS plus Debian-container environment:

```sh
bash -n scripts/*.sh
python3 -m py_compile scripts/check-gpt-fixture.py
git diff --check
make rust-fast
make rust-quality
make rust-deep
make check-qrvfs-rust-fixture
make check-elf-reloc-fixture
cargo deny --manifest-path rust/Cargo.toml check -c rust/deny.toml
make container-toolchain-build
make container-check
make container-rust-abi
make container-index-c-static
```

`make container-index-c-static` generated static C indexes for 816 QSOE-owned
C/ASM files.

`make container-rust-abi` linked:

```text
build/rust/qsoe-minimal-rs.elf
```

The strict ELF audit showed:

- `ET_EXEC` RISC-V executable;
- interpreter `/lib/ld-qsoe.so.1`;
- dynamic dependency `libc.so`;
- no TLS sections;
- no unwind sections;
- relocations within the current QSOE userland baseline.

## Important Caveats

- The known QSOE/L seL4 untyped allocation messages and missing RTC message are
  recorded as baseline noise, not automatic regressions.
- Debian Trixie QEMU `10.0.8` is acceptable for QSOE/L PLIC/virtio boot smoke.
- QSOE/N AIA MSI/MSI-X experiments still need QEMU `11.0.1+`.
- The first Rust userland pilots remain `no_std`, `panic=abort`, no TLS, no
  unwind, and out of the default image.
- C implementations remain the rollback path until a Rust service has host
  tests, fixture parity, ELF audit, boot evidence, and documented differences.

## Current Decisions

The active decision log is `DECISIONS.md`. Most relevant recent decisions:

- D-017: use tiered Rust workflow gates.
- D-018: separate Cargo target dirs by host/workflow.
- D-019: start Rust supply-chain policy with cargo-deny.
- D-020: use layered C indexing rather than clangd alone.

## Next Recommended Work

1. On Linux, run `make prepare`, `make`, `make rust-quality`, `make rust-abi`,
   and `scripts/boot-smoke.sh -k lq -t 120`.
2. Capture a focused compile database before doing a full clean Bear capture.
3. Add a bounded clang-tidy wrapper over `build/index/c/compile_commands.json`.
4. Add `/dev/slog` readback smoke coverage.
5. Add a safe `slogger` resource-server wrapper surface.
6. Implement the Rust slogger ring buffer with host tests.
7. Only then start an opt-in `slogger-rs` QSOE userland binary.
