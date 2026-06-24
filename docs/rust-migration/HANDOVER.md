# QSOE Migration Handover

Last updated: 2026-06-24 08:36 CEST.

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

Current stack tip:

```text
PR #89: codex/rust-pipe-opt-in
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

## GitHub Stack

The active handover stack is a linear draft PR chain:

```text
#42  main -> codex/handover-ci-slogger-prep
#44  -> codex/slogger-rs-entrypoint
#45  -> codex/slogger-build-flag
#46  -> codex/slogger-rs-boot-image
#47  -> codex/slogger-boot-log-compare
#48  -> codex/direct-service-bootstrap
#49  -> codex/resource-server-example
#50  -> codex/error-mapping
#51  -> codex/wrapper-level-tests
#52  -> codex/virtio-block-spec
#53  -> codex/virtio-mmio-wrapper
#54  -> codex/virtqueue-descriptor-model
#55  -> codex/host-side-queue-tests
#56  -> codex/virtio-rust-driver-opt-in
#57  -> codex/rust-virtio-boot-smoke
#58  -> codex/rust-virtio-file-smoke
#59  -> codex/cpio-parser-crate
#60  -> codex/syscfg-sysmap-view-crate
#61  -> codex/elf-inspection-crate
#62  -> codex/parser-host-guest-reuse
#63  -> codex/rank-userland-services
#64  -> codex/pick-pipe-second-service
#65  -> codex/pick-rust-test-helper
#66  -> codex/c-retirement-gate
#67  -> codex/taskman-module-inventory
#68  -> codex/select-taskman-procfs-pilot
#69  -> codex/taskman-procfs-boundary
#70  -> codex/procfs-boot-smoke
#71  -> codex/kernel-rust-decision
#72  -> codex/kernel-safe-candidates
#73  -> codex/kernel-artifact-audit
#74  -> codex/audit-artifacts-target
#75  -> codex/rust-parser-fuzz-targets
#76  -> codex/rust-coverage-reporting
#77  -> codex/unsafe-review-checklist
#78  -> codex/migration-status-table
#79  -> codex/release-note-template
#80  -> codex/slog-readback-smoke-stacked
#81  -> codex/handover-stack-status
#86  -> codex/rust-slog-readback-smoke
#88  -> codex/test-msgpass-rs-helper
#89  -> codex/rust-pipe-opt-in
```

PR #43 was closed as superseded by #80 because it was a side branch from
`main`; #80 carries the same `/dev/slog` readback smoke on top of the active
stack.

PR #88 adds the opt-in Rust `test_msgpass` helper and a root migration progress
`README.md`. It closes #87 and remains stacked on #86.

PR #89 adds the opt-in Rust `pipe` state machine and `/dev/pipe` service
wrapper, selector, link smoke, registration boot smoke, and docs updates. It
remains stacked on #88. The next pipe gate is the data-path smoke tracked by
#90.

Current external blockers:

- #42 CI uses `runs-on: [self-hosted, X64]`, matching the active Rapsody CI
  runner label, but run `28054197652` has been queued since
  `2026-06-23 20:16 UTC` with no steps started. This is runner
  availability/access, not a workflow-label mismatch. Tracked by #82.
- #60 has a red CodeRabbit status due to insufficient usage credits. The
  earlier actionable sysview findings have been fixed at the branch tip.
  Tracked by #83.
- The only unchecked backlog item is C retirement, which is intentionally
  blocked until a component completes a Rust-default release candidate with C
  rollback. Tracked by #26.

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
scripts/rust-test-msgpass-smoke.sh -t 240 -o build/rust-test-msgpass/boot-smoke-lq-rust-test-msgpass-env-override.log
make rust-pipe-link-smoke
QSOE_RUST_PIPE=1 make pipe-artifact
scripts/rust-pipe-smoke.sh -t 180 -o build/rust-pipe/boot-smoke-lq-rust-pipe.log
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
  A Rust-default release candidate with C rollback is still required before any
  C retirement decision.
- `test_msgpass` has an opt-in Rust helper and Rust-selected suite `[msgpass]`
  smoke. The wider suite still reports the known unrelated QSOE/L sync failure,
  so the smoke gates targeted `[msgpass]` markers and boot-to-login.
- `pipe` has an opt-in Rust service and registration boot smoke. It is not a
  Rust-default candidate until a data-path smoke proves real pipe creation and
  round-trip I/O through libc/taskman; see #90.

## Current Decisions

The active decision log is `DECISIONS.md`. Most relevant recent decisions:

- D-017: use tiered Rust workflow gates.
- D-018: separate Cargo target dirs by host/workflow.
- D-019: start Rust supply-chain policy with cargo-deny.
- D-020: use layered C indexing rather than clangd alone.
- D-021: reject near-term Rust implementation inside `nq` kernel code.

## Next Recommended Work

1. Restore runner availability for #42 or rerun the queued workflow once the
   `[self-hosted, X64]` runner is available; see #82.
2. Decide whether to mark the draft stack ready for review and merge it
   bottom-up from #42 through #89; see #84.
3. Resolve the #60 CodeRabbit usage-credit status or record it as an external
   billing blocker when merging; see #83.
4. Use the #86 Rust-selected readback evidence if planning a Rust-default
   `slogger` release candidate, use #88 if planning a Rust-default
   `test_msgpass` test-image decision, and use #89 only after the #90 pipe
   data-path smoke exists; keep C rollback paths available.
5. Continue with the #90 pipe data-path smoke or a Rust `tm_procfs` provider.
   Do not start C retirement until the release-candidate gate in
   `RETIREMENT.md` is satisfied; see #26.
