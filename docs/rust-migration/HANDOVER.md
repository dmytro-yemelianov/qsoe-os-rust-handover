# QSOE Migration Handover

Last updated: 2026-06-29 CEST.

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
1a6b196afc2ff02705f51fe66ec44343e5e3ed8a
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

PR #94 added the Rust pipe data-path smoke to CI, PR #99 added the Rust
`test_msgpass` smoke to CI, PR #100 added both `slogger-rs` RC readback smokes
to CI, PR #101 added host-model coverage for `tm_procfs`, PR #104 added the
Rust `tm_procfs` opt-in provider, PR #105 added the `tm_procfs` evidence gate,
PR #107 applied tracked component overrides for CI, PR #108 fixed line-split
serial marker checks in the Rust smokes, PR #109 recorded trusted CI evidence
for #96, #97, and #103, PR #162 added the Rust opt-in `tm_cred` provider, and
PR #163 added the Rust opt-in `tm_pseudodev` provider, PR #164 added the Rust
opt-in `tm_sysfs` provider, PR #165 fixed the issue-backed roadmap dashboard's
opt-in status display, PR #166 added the Rust opt-in `tm_cpio` provider, and
PR #167 added the Rust opt-in `tm_script` provider, PR #168 added the Rust
opt-in `tm_syscfg` provider, and PR #169 added the Rust opt-in `tm_rsrcdb`
provider. The current `main` tip is
`51b40459a75c6bcefcf3cfd578a2fe983d4356c1`.

Current open follow-ups:

- #26: keep C retirement blocked until the retirement checklist in
  `RETIREMENT.md` is satisfied and a separate removal PR is reviewed.

The #96 Rust pipe data-path gate, #97 Rust `test_msgpass` gate, and #103
`tm_procfs` opt-in gate are satisfied by trusted `main` CI run `28102250069` at
`1d7b706403b54e8a798d3b1f560f5473d33e020b`.

The #98 host-test gate for the portable `tm_procfs` model is satisfied by
`make check-tm-procfs-model`. The #102 Rust provider gate is satisfied by
`QSOE_RUST_TM_PROCFS=1`; C remains default and rollback.

The current branch adds a Rust opt-in `tm_pathmgr` provider behind
`QSOE_RUST_TM_PATHMGR=1`. Focused local evidence has passed through the C host
model, Rust host tests, clippy, override assertions, and Rust staticlib build;
C remains default and rollback.

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
make check-tm-procfs-model
make rust-tm-procfs-provider
make rust-tm-cred-provider
make tm-cred-evidence
make rust-tm-pseudodev-provider
make tm-pseudodev-evidence
make check-tm-sysfs-model
make rust-tm-sysfs-provider
make tm-sysfs-evidence
QSOE_RUST_TM_PROCFS=1 make procfs-smoke
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
  a C rollback drill with `make slogger-rc-rollback-smoke`. CI includes both
  container RC readback smokes for trusted PRs and pushes. #95's
  local-equivalent RC evidence window is accepted; C retirement is still
  blocked by #26.
- `test_msgpass` has an opt-in Rust helper and Rust-selected suite `[msgpass]`
  smoke. CI includes `container-rust-test-msgpass-smoke` for trusted PRs and
  pushes. Trusted `main` run `28102250069` passed the smoke and uploaded the
  targeted `[msgpass]` markers plus boot-to-login evidence. The wider suite
  still reports the known unrelated QSOE/L sync failure, so the smoke gates
  only the targeted `[msgpass]` markers and boot-to-login.
- `pipe` has an opt-in Rust service, registration boot smoke, data-path smoke,
  and a Rust-default RC path with C rollback. CI includes
  `container-rust-pipe-data-smoke`, `container-pipe-rc-data-smoke`, and
  `container-pipe-rc-rollback-smoke` on the configured `[self-hosted, X64]`
  runner for trusted PRs and pushes. Trusted `main` run `28102250069` passed
  the hosted-runner opt-in data-path smoke and uploaded the required pipe
  registration, round-trip, EOF, and helper-exit markers. C remains rollback.
- `tm_procfs` now has a Rust opt-in provider behind `QSOE_RUST_TM_PROCFS=1`.
  The selector removes C `tm_procfs.o` from `libtaskman.a`, links the
  soft-float `qsoe-tm-procfs` archive into NQ/LQ taskman. `make
  tm-procfs-evidence` audits the selected artifacts and runs both C-default and
  Rust-selected `/proc` smokes; CI includes `container-tm-procfs-evidence` on
  the configured `[self-hosted, X64]` runner for trusted PRs and pushes.
  Trusted `main` run `28102250069` passed the evidence step and uploaded both
  C-default/Rust-selected procfs logs plus archive membership and readelf
  summaries. C remains default and rollback.
- `tm_cred` has a Rust opt-in provider behind `QSOE_RUST_TM_CRED=1`. It is
  merged on `main` through PR #162 with `make tm-cred-evidence` and
  `make container-source-build` evidence. C remains default and rollback until
  a credential-specific runtime smoke and separate RC decision exist.
- `tm_pseudodev` has a Rust opt-in provider behind
  `QSOE_RUST_TM_PSEUDODEV=1`. The selector replaces only LQ `sys/devnull.o`
  and `sys/devzero.o` with the Rust staticlib. C remains default and rollback
  until a focused `/dev/null` and `/dev/zero` runtime smoke and separate RC
  decision exist.
- `tm_cpio` has a Rust opt-in provider behind `QSOE_RUST_TM_CPIO=1`. The
  selector removes C `cpio.o` from `libtaskman.a` and links the soft-float
  `qsoe-tm-cpio` archive into NQ/LQ taskman. C remains default and rollback
  until CPIO-backed spawn/file-access runtime coverage and a separate RC
  decision exist.
- `tm_script` has a Rust opt-in provider behind `QSOE_RUST_TM_SCRIPT=1`. The
  selector removes C `script.o` from `libtaskman.a` and links the soft-float
  `qsoe-tm-script` archive into NQ/LQ taskman. C remains default and rollback
  until script-spawn runtime coverage and a separate RC decision exist.
- `tm_syscfg` has a Rust opt-in provider behind `QSOE_RUST_TM_SYSCFG=1`. The
  selector removes C `syscfg.o` from `libtaskman.a` and links the soft-float
  `qsoe-tm-syscfg` archive into NQ/LQ taskman. C remains default and rollback
  until syscfg-backed platform-data runtime coverage and a separate RC decision
  exist.
- `tm_sysmap` has a Rust opt-in provider behind `QSOE_RUST_TM_SYSMAP=1`. The
  selector removes LQ C `sys/sysmap.o` and links the soft-float
  `qsoe-tm-sysmap` archive into LQ taskman. C remains default and rollback
  until mapped `PSYS` page runtime coverage and a separate RC decision exist.
- `tm_pathmgr` has a Rust opt-in provider behind `QSOE_RUST_TM_PATHMGR=1`. The
  selector removes C `pathmgr.o` from `libtaskman.a` and links the soft-float
  `qsoe-tm-pathmgr` archive into NQ/LQ taskman. C remains default and rollback
  until open/device-registration runtime coverage and a separate RC decision
  exist.
- `tm_sysfs` has a Rust opt-in provider behind `QSOE_RUST_TM_SYSFS=1`. The
  selector removes C `tm_sysfs.o` from `libtaskman.a` and links the soft-float
  `qsoe-tm-sysfs` archive into NQ/LQ taskman. C remains default and rollback
  until a focused `/sys` runtime smoke and separate RC decision exist.
- `tm_rsrcdb` has a Rust opt-in provider behind `QSOE_RUST_TM_RSRCDB=1`. The
  selector removes LQ C `sys/rsrcdb.o` and links the soft-float
  `qsoe-tm-rsrcdb` archive into LQ taskman. C remains default and rollback
  until resource attach/query/detach runtime coverage and a separate RC
  decision exist.
- `tm_elf` has a Rust opt-in provider behind `QSOE_RUST_TM_ELF=1`. The selector
  removes C `elf.o` from `libtaskman.a` and links the soft-float
  `qsoe-tm-elf` archive into NQ/LQ taskman. C remains default and rollback
  until ELF-backed spawn runtime coverage and a separate RC decision exist.
- `tm_fdt` has a Rust opt-in provider behind `QSOE_RUST_TM_FDT=1`. The
  selector removes LQ C `sys/fdt.o` and links the soft-float `qsoe-tm-fdt`
  archive into LQ taskman. C remains default and rollback until boot/syscfg
  runtime coverage and a separate RC decision exist.

## Current Decisions

The active decision log is `DECISIONS.md`. Most relevant recent decisions:

- D-017: use tiered Rust workflow gates.
- D-018: separate Cargo target dirs by host/workflow.
- D-019: start Rust supply-chain policy with cargo-deny.
- D-020: use layered C indexing rather than clangd alone.
- D-021: reject near-term Rust implementation inside `nq` kernel code.

## Next Recommended Work

1. Keep C `slogger` retirement blocked until #26's retirement checklist is
   satisfied and a separate removal PR is reviewed.
2. Keep the new pipe Rust-default RC path and C rollback data-path smoke green
   before considering any #26 retirement work.
3. If desired, open a separate Rust-default `test_msgpass` test-image decision
   PR with C rollback. #97's hosted-runner evidence is complete.
4. If desired, open a separate Rust-default `tm_procfs` selection design/PR
   with C rollback. #103's opt-in evidence is complete.
5. Keep the hosted runner and CodeRabbit account healthy for new PRs, but the
   old #42/#60 external states no longer block `main`.
6. Do not start C retirement until the release-candidate gate in
   `RETIREMENT.md` is satisfied; see #26.
