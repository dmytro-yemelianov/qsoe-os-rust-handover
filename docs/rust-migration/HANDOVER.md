# QSOE Migration Handover

Last updated: 2026-06-24 13:16 CEST.

This handover captures the current QSOE Rust migration and workflow work so it
can move from the macOS/container setup to a native Linux development machine.

## Repository Snapshot

Current Linux repository:

```text
/home/dmytro/github/qsoe-os-rust-handover
```

Current GitHub remote:

```text
origin git@github.com:dmytro-yemelianov/qsoe-os-rust-handover.git
```

Current main tip:

```text
338517613bd507db18bfe82da8c9d2818bc67dfe
```

The local tree adds:

- migration planning docs under `docs/rust-migration/`;
- Debian container toolchain under `toolchains/debian/`;
- repeatable validation scripts under `scripts/`;
- a pinned Rust workspace under `rust/`;
- C indexing/clangd plumbing via `.clangd` and `scripts/c-index.sh`;
- top-level Make targets for checks, Rust workflow tiers, container workflow,
  ELF audits, boot smoke, C indexes, fuzz smoke, coverage, artifact audit, and
  targeted component smokes.

Generated build output stays out of git:

```text
build/
rust/target/
sel4-bootstrap/
```

## GitHub State

The previous linear draft PR chain through #89 was merged bottom-up on
2026-06-24. PR #60 was retargeted into #42, and #42 was then merged into
`main` at `a3e75dbc47d1fadc99360f4476147a526f521d9b`.

PR #43 was closed as superseded by #80 because it was a side branch from
`main`; #80 carried the same `/dev/slog` readback smoke on top of the merged
stack.

The former stack blockers are no longer active merge blockers:

- #82 recorded the self-hosted `[self-hosted, X64]` runner queue state for #42
  and was closed after the stack merge decision.
- #83 recorded the CodeRabbit usage-credit status for #60 and was closed after
  the stack merge decision.
- #84 tracked bottom-up merge preparation and was closed after #60 and #42 were
  merged.

PR #93 added the first `slogger-rs` Rust-default release-candidate path with
the C rollback drill and was squash-merged into `main` at
`338517613bd507db18bfe82da8c9d2818bc67dfe`.

Current open follow-up:

- #26: keep C retirement blocked until the `slogger-rs` RC evidence window is
  accepted and the retirement checklist in `RETIREMENT.md` is satisfied.
- #95: accept the `slogger-rs` Rust-default RC evidence window.
- #96: capture trusted CI evidence for the Rust pipe data-path smoke.
- #97: capture trusted CI evidence for the Rust `test_msgpass` smoke.
- #98: add host tests for the portable `tm_procfs` model.

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

The following checks passed across the stacked work and are recorded in
`DEVLOG.md`:

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
make audit-artifacts
QSOE_RUST_FUZZ_RUNS=1 QSOE_RUST_FUZZ_SECONDS=2 make rust-fuzz-smoke
make rust-coverage
make procfs-smoke
make pipe-smoke
make rust-virtio-file-smoke
scripts/slog-readback-smoke.py -t 120 -o build/slog-readback-smoke-stacked.log
scripts/slog-readback-smoke.py --rust-slogger -t 180 -o build/slog-readback-smoke-lq-rust-slogger-final.log
scripts/slog-readback-smoke.py --slogger-rc -t 180 -o build/slogger-rc/slog-readback-rust-default.log
scripts/slog-readback-smoke.py --slogger-rc-rollback -t 180 -o build/slogger-rc/slog-readback-c-rollback.log
scripts/rust-test-msgpass-smoke.sh -t 240 -o build/rust-test-msgpass/boot-smoke-lq-rust-test-msgpass-env-override.log
make rust-pipe-link-smoke
QSOE_RUST_PIPE=1 make pipe-artifact
scripts/rust-pipe-smoke.sh -t 180 -o build/rust-pipe/boot-smoke-lq-rust-pipe.log
scripts/rust-pipe-data-smoke.sh -t 240 -o build/rust-pipe-data/boot-smoke-lq-rust-pipe-data.log
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
- `slogger` has C-selected and Rust-selected `/dev/slog` readback baselines.
  It also has a Rust-default RC path with `make slogger-rc-readback-smoke` and
  a C rollback drill with `make slogger-rc-rollback-smoke`. C retirement is
  still blocked until the RC evidence window is accepted.
- `test_msgpass` has an opt-in Rust helper and Rust-selected suite `[msgpass]`
  smoke. CI includes `container-rust-test-msgpass-smoke` for trusted PRs and
  pushes. The wider suite still reports the known unrelated QSOE/L sync
  failure, so the smoke gates targeted `[msgpass]` markers and boot-to-login.
- `pipe` has an opt-in Rust service, registration boot smoke, and data-path
  smoke. CI includes `container-rust-pipe-data-smoke` on the configured
  `[self-hosted, X64]` runner for trusted PRs and pushes, so a green run can be
  used as hosted-runner evidence before any Rust-default pipe release
  candidate. C remains rollback.

## Current Decisions

The active decision log is `DECISIONS.md`. Most relevant recent decisions:

- D-017: use tiered Rust workflow gates.
- D-018: separate Cargo target dirs by host/workflow.
- D-019: start Rust supply-chain policy with cargo-deny.
- D-020: use layered C indexing rather than clangd alone.
- D-021: reject near-term Rust implementation inside `nq` kernel code.

## Next Recommended Work

1. Run and accept the `slogger-rs` RC window from `SLOGGER_RC.md`; do not retire
   the C `slogger` until #26's retirement checklist is satisfied.
2. Use a green trusted CI run of `make container-rust-pipe-data-smoke` on the
   configured `[self-hosted, X64]` runner as hosted-runner evidence before
   considering Rust pipe for a default-selection release candidate.
3. Use a green trusted CI run of `make container-rust-test-msgpass-smoke` for
   #97 before any Rust-default test-image decision; keep C rollback paths
   available.
4. Continue with a Rust `tm_procfs` provider only after adding host tests for
   the portable procfs model.
5. Keep the hosted runner and CodeRabbit account healthy for new PRs, but the
   old #42/#60 external states no longer block `main`.
6. Do not start C retirement until the release-candidate gate in
   `RETIREMENT.md` is satisfied; see #26.
