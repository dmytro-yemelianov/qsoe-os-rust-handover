# QSOE Rust Migration Decision Log

Last updated: 2026-06-24 02:09 CEST.

This file records project decisions made during the Rust migration planning and
toolchain setup. It is intended to be append-only except for status changes,
corrections, or superseding links.

Status values:

- `Accepted`: active decision.
- `Superseded`: replaced by a later decision.
- `Open`: still under investigation.

## D-001: Use Incremental Rust Adoption, Not A Wholesale Rewrite

Status: Accepted.

Decision:

Rust will be introduced behind existing QSOE boundaries. The current C system
remains the default boot path until each Rust component has tests, ELF audit,
boot evidence, and a rollback path.

Rationale:

The system has boot-critical code in the kernel, task manager, libc startup,
dynamic loader, and service launch paths. Rewriting those first would increase
debug surface before the Rust toolchain and ABI constraints are proven.

Consequences:

- Rust work starts with host tools, bindings, and opt-in userland services.
- C implementations remain available during pilot work.
- Default images should not change because a Rust crate was added.

Verification:

- Migration plan and task backlog are in `PLAN.md` and `TASKS.md`.
- Rust spike is outside the default image.

## D-002: Preserve The Existing Boot And ABI Contract

Status: Accepted.

Decision:

Rust userland must preserve the current QSOE user ABI, resource-server ABI,
dynamic interpreter path, relocation model, and boot milestones unless a
separate ABI migration is designed and approved.

Rationale:

The loader, task manager, libc, and user services already share a narrow
contract. Rust should reduce implementation risk, not create a second ABI.

Consequences:

- Cross-language structs use `#[repr(C)]`.
- Extern functions live in raw FFI crates before safe wrappers expose them.
- Rust-generated ELF files must be audited before image inclusion.

Verification:

- `qsoe-abi`, `qsoe-ffi`, and `qsoe-ressrv` exist in the Rust workspace.
- Layout tests pass in `make container-check`.

## D-003: Require `no_std`, `panic=abort`, No Unwind, No TLS For First Pilots

Status: Accepted.

Decision:

Initial QSOE Rust userland must be `no_std`, use `panic=abort`, and avoid TLS,
unwind tables, and allocator assumptions.

Rationale:

The current QSOE loader/runtime contract is small and does not yet prove support
for Rust runtime features such as unwinding, thread-local storage, or allocator
setup.

Consequences:

- Rust crates are written for freestanding use.
- Unsupported sections or relocations fail artifact audit.
- Allocator use requires a later explicit design.

Verification:

- `scripts/audit-elf.sh --strict-qsoe-user` is the gate.
- `make container-rust-qsoe-link-smoke` produced no TLS or unwind sections.

## D-004: Pin The Rust Toolchain

Status: Accepted.

Decision:

Pin Rust to `1.95.0` for the migration spike and container toolchain.

Rationale:

The generated target behavior, compiler builtins, emitted relocations, and
`no_std` artifact shape should not drift silently during migration planning.

Consequences:

- `rust/rust-toolchain.toml` selects a concrete Rust version.
- The Debian container installs the same version with `rustfmt`, `clippy`, and
  `riscv64gc-unknown-none-elf`.

Verification:

- Container version probe reported `rustc 1.95.0`.
- `QSOE_RUST_COMPILE=1 scripts/rust-check.sh` passed in the container.

## D-005: Use A Custom QSOE RISC-V User Target For Artifact Experiments

Status: Accepted.

Decision:

Keep a checked-in target JSON at `rust/targets/riscv64-qsoe-user.json` for
QSOE userland link experiments.

Rationale:

QSOE userland is not Linux userland, even though it uses a RISC-V GNU linker and
a QSOE libc. A dedicated target file makes target assumptions visible.

Consequences:

- Cargo configuration is checked in under `rust/.cargo/config.toml`.
- Link smoke remains scripted instead of depending on per-user shell setup.

Verification:

- `make container-rust-qsoe-link-smoke` links
  `build/rust/qsoe-minimal-rs.elf`.

## D-006: Add Host-Side Fixtures Before Replacing Image Tools

Status: Accepted.

Decision:

Create qrvfs and GPT fixture checks before porting host image tooling to Rust.

Rationale:

Host image tools are a low-risk starting point, but they still define boot media
contracts. Fixtures make later parser or writer ports measurable.

Consequences:

- Fixture checks are exposed through `make check-host-tools`.
- Existing C/Python tools remain the oracle until Rust output is compared.

Verification:

- `scripts/check-qrvfs-fixture.sh` passes.
- `scripts/check-gpt-fixture.py` passes.

## D-007: Add Boot Smoke And Artifact Audit As Preflight Gates

Status: Accepted.

Decision:

Use a QEMU boot smoke script and an ELF audit script as mandatory preflight
tools for Rust migration.

Rationale:

Boot success and ELF compatibility are the two fastest regressions to detect
when changing build, loader, or userland code.

Consequences:

- `scripts/boot-smoke.sh` checks QSOE banner, init, slogger, block device,
  qrvfs mount, and login prompt.
- `scripts/audit-elf.sh` reports and can fail on unsupported userland ELF
  properties.

Verification:

- LQ container boot smoke reached login.
- Minimal Rust link smoke passed strict ELF audit.

## D-008: Treat seL4 Untyped Allocation Messages And Missing RTC As Baseline Noise

Status: Accepted.

Decision:

Known QSOE/L debug boot messages about seL4 untyped allocation failures and the
missing battery-backed RTC are recorded as baseline observations, not automatic
regressions.

Rationale:

The observed boot continued through init, storage startup, qrvfs mount, sysinit,
and login despite these messages.

Consequences:

- Future boot comparison should consider surrounding behavior and frequency.
- These messages should not block Rust pilot work unless they change behavior.

Verification:

- Baseline notes are recorded in `BASELINE.md`.

## D-009: Use Debian/Container For Source Builds From macOS

Status: Accepted.

Decision:

Use a Debian container toolchain for source builds and Rust link smoke from the
macOS host.

Rationale:

The release Makefiles expect Linux package names and paths such as
`riscv64-linux-gnu-gcc`, `python3-kconfiglib`, and Debian OpenSBI paths.
macOS does not provide `apt` or those paths.

Consequences:

- Docker/Colima is the local container runtime path.
- The source tree is bind-mounted; the image does not copy source code.
- Generated files remain host-editable by running as the host uid/gid.

Verification:

- `make container-source-build` passed.
- `scripts/container-toolchain.sh run scripts/boot-smoke.sh -k lq -t 120`
  passed.

## D-010: Use Debian Trixie, Not Bookworm, For The Container

Status: Accepted.

Decision:

Base the checked-in container image on Debian Trixie.

Rationale:

Debian Bookworm's RISC-V binutils/GCC rejected the current NQ ISA flags using
`zicntr`. Trixie provides GCC `14.2.0` and binutils `2.44`, which accept the
current source tree.

Consequences:

- `toolchains/debian/Dockerfile` starts from `debian:trixie`.
- Toolchain docs warn that Bookworm is too old for this tree.

Verification:

- NQ source build completed in the Trixie container.

## D-011: Use Debian Packages For seL4 Python Dependencies Where Available

Status: Accepted.

Decision:

Install seL4 generator dependencies from Debian packages where available:
`jinja2`, `ply`, `jsonschema`, `pyelftools`, `lxml`, `bs4`, `pexpect`, `sh`,
`libarchive-c`, `autopep8`, and related packages.

Rationale:

seL4's Python generator path imports more than `kconfiglib` and `yaml`.
Using Debian packages keeps most dependencies distro-managed and reproducible.

Consequences:

- The container image is larger.
- seL4 kernel generation no longer fails on missing `jinja2`.

Verification:

- seL4 CMake and Ninja kernel build completed in `make container-source-build`.

## D-012: Install `pyfdt` From PyPI Until Debian Provides `pyfdt.pyfdt`

Status: Accepted.

Decision:

Install `pyfdt` version `0.3` from the PyPI source tarball in the container.

Rationale:

seL4 imports `pyfdt.pyfdt`, and Debian Trixie does not package that module.
`python3-libfdt` is not the same API.

Consequences:

- The Dockerfile has one PyPI dependency.
- The install uses a pinned version argument, `PYFDT_VERSION=0.3`.

Verification:

- `python3 -c "import pyfdt.pyfdt"` passed in the container.
- LQ seL4 hardware generation completed.

## D-013: Keep QEMU Version Caveat Split By Use Case

Status: Accepted.

Decision:

Use Debian Trixie's QEMU `10.0.8` for LQ PLIC/virtio boot smoke and source
build checks, but keep QEMU `11.0.1+` as the requirement for NQ AIA MSI/MSI-X
boot experiments.

Rationale:

The known AIA issue affects MSI delivery on `virt,aia=aplic-imsic`. LQ defaults
to the PLIC path and does not need that newer QEMU for the current smoke.

Consequences:

- Container validation includes LQ boot smoke.
- NQ AIA boot smoke remains a host/custom-QEMU validation item.

Verification:

- LQ boot smoke passed with container QEMU `10.0.8`.
- Existing launcher comments still gate AIA on `11.0.1+`.

## D-014: Preserve Prepared Release Checkouts During Container Builds

Status: Accepted.

Decision:

`container-source-build` runs `make prepare` only when component directories are
missing, then runs `make`.

Rationale:

The release components are checked out at detached tags. Re-running prepare
unnecessarily can disturb local inspection state and produce noisy detached
HEAD messages.

Consequences:

- Existing prepared trees are reused.
- A missing component directory still triggers release acquisition.

Verification:

- `make container-source-build` reused the prepared tree and completed.

## D-015: Track Migration Work In Plain Markdown And Make Targets

Status: Accepted.

Decision:

Keep decisions, development history, specs, plans, and tasks under
`docs/rust-migration/`; expose repeatable checks through top-level Make targets.

Rationale:

The migration needs traceability but should stay lightweight enough to update
during active bring-up.

Consequences:

- New decisions go into this file.
- Chronological process updates go into `DEVLOG.md`.
- Check commands are discoverable through `Makefile`.

Verification:

- `README.md` links the docs in reading order.
- This dry run expands correctly:

```sh
make -n container-toolchain-build container-check \
  container-rust-qsoe-link-smoke container-source-build
```

## D-016: Start Host Parser Migration With Read-Only qrvfs Inspection

Status: Accepted.

Decision:

Add a Rust read-only qrvfs parser and tree-format inspector before attempting a
Rust qrvfs writer or in-guest filesystem replacement.

Rationale:

The qrvfs format is small, fixture-backed, and important to boot media. A
read-only parser exercises the on-disk contract with low runtime risk and gives
future Rust host tools a tested format layer.

Consequences:

- The first qrvfs Rust crate is host-side and read-only.
- The Rust tool must match current `treeqrvfs` output for the fixture before it
  is used as an oracle for further ports.
- Image writing remains owned by the existing C `mkfs-qrv` tool.

Verification:

- `make rust-check` passes with `qsoe-qrvfs` unit tests.
- `make check-qrvfs-rust-fixture` diffs Rust output against C `treeqrvfs`.
- `make container-check` includes the Rust/C qrvfs fixture comparison.

## D-017: Use Tiered Rust Workflow Gates

Status: Accepted.

Decision:

Split Rust checks into fast, quality, ABI, and deep tiers exposed through Make
targets.

Rationale:

Rust development needs a fast edit loop, but QSOE userland readiness depends on
more than `cargo check`. A tiered workflow keeps routine checks cheap while
making ABI, ELF, fixture, and optional deep-analysis gates explicit.

Consequences:

- `make rust-fast` is for local edit cadence only.
- `make rust-quality` and `make rust-check` remain the normal pre-push gate.
- `make rust-abi` requires built QSOE C artifacts and runs the link/audit smoke.
- `make rust-deep` runs optional heavier tools when installed.

Verification:

- `docs/rust-migration/WORKFLOW.md` documents the tiers.
- `scripts/rust-workflow.sh` implements the target routing.

## D-018: Separate Cargo Target Directories By Host And Workflow Scope

Status: Accepted.

Decision:

Rust workflow scripts set `CARGO_TARGET_DIR` by default to a host/workflow scoped
directory under `rust/target`.

Rationale:

The same source tree is used from macOS and the Debian Linux container. Sharing
Cargo's default workspace target directory across those environments causes
unnecessary rebuilds and noisy dep-info churn.

Consequences:

- Host checks use paths like `rust/target/host-darwin-aarch64` or
  `rust/target/host-linux-x86_64`.
- QSOE link smoke uses paths like `rust/target/qsoe-link-linux-x86_64`.
- Developers can still override `CARGO_TARGET_DIR`.

Verification:

- `scripts/rust-env.sh` is sourced by Rust workflow scripts.
- `rust-qsoe-link-smoke.sh` locates its staticlib through `CARGO_TARGET_DIR`.

## D-019: Start Rust Supply-Chain Policy With cargo-deny

Status: Accepted.

Decision:

Use `rust/deny.toml` as the first Rust dependency policy gate.

Rationale:

The Rust workspace currently has no third-party dependencies, but migration work
will likely add parser, test, and tooling crates over time. A checked-in policy
keeps license, advisory, duplicate-version, wildcard, registry, and git-source
expectations explicit before dependencies grow.

Consequences:

- Apache-2.0 is the initial allowed license.
- Unknown registries and unknown git sources are denied.
- Wildcard dependency requirements are denied.
- cargo-vet remains a later option if dependency review evidence becomes more
  important than a simple deny policy.

Verification:

- `make rust-deep` runs cargo-deny with `rust/deny.toml` when cargo-deny is
  installed.

## D-020: Use Layered C Indexing Rather Than clangd Alone

Status: Accepted.

Decision:

Use static indexes for fast C navigation and a Bear-generated compile database
for compiler-aware clangd/clang-tidy workflows.

Rationale:

QSOE has multiple build variants, generated artifacts, freestanding C, and a
containerized Linux build path from macOS. Static indexes are cheap and robust
for source reading. clangd needs a compile database to be accurate, but compile
database capture is slower and only complete when the relevant build commands
actually execute.

Consequences:

- Default static C indexing covers QSOE-owned trees and excludes generated build
  output.
- seL4 indexing is opt-in with `QSOE_INDEX_SEL4=1`.
- Container compile database capture rewrites paths for the host editor by
  default while preserving the container-path database.

Verification:

- `scripts/c-index.sh` implements file-list, tags, cscope, GNU Global, and Bear
  compile database modes.
- `docs/rust-migration/INDEXING.md` documents the workflow.

## D-021: Reject Near-Term Kernel Rust Implementation

Status: Accepted.

Decision:

Do not start near-term Rust implementation work inside `nq`. Phase 10 may
continue documenting safe candidates and kernel artifact audit requirements,
but implementation stays out of scope until userland and task-manager evidence
is stronger.

Rationale:

Completed migration work has proven useful building blocks:

- Rust host parsers and inspectors now cover qrvfs, CPIO, syscfg/sysmap, and
  ELF relocation fixtures.
- Opt-in Rust userland pilots have linked under the QSOE userland contract and
  booted for `slogger` and `devb-virtio`; virtio also has file-access smoke.
- The task-manager `tm_procfs` pilot has an inventory, selection, C/Rust
  boundary, rollback plan, and targeted C-default boot smoke.

That is not enough evidence for kernel Rust yet:

- no Rust component has completed a release-candidate period as the default
  implementation with C rollback available;
- no C implementation has reached the retirement gate;
- task-manager Rust is still design-only, so mixed-language work has not
  reached process-management internals;
- kernel candidates touch traps, context switching, scheduling, boot assembly,
  and low-level capability assumptions where rollback and debug cost are much
  higher than userland.

Consequences:

- Phase 10 kernel work is limited to candidate and audit documentation.
- No Rust crate or build flag should be wired into `nq` as part of near-term
  migration work.
- Userland and task-manager pilots remain the evidence path for later
  reassessment.
- Revisit this decision only after at least one Rust component has shipped
  through a Rust-default release candidate with C rollback and after
  task-manager pilot evidence exists beyond documentation.

Verification:

- `RETIREMENT.md` records that no C implementation is currently retireable.
- `TASK_MANAGER_PROCFS_BOUNDARY.md` records the first task-manager Rust boundary
  as future opt-in work.
- `VIRTIO_BLOCK.md`, `SLOGGER_BOOT_COMPARE.md`, and `TASKS.md` record the
  current userland evidence and remaining gates.
