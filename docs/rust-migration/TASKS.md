# QSOE Rust Migration Task Backlog

This backlog is ordered for incremental execution. Each task should land as a
small reviewable change unless it explicitly says otherwise.

## Phase 0: Baseline And Safety Net

- [x] Record release component SHAs.
  - Acceptance: a checked-in document lists `os`, `lq`, `nq`, `libc`, `quser`,
    and `mr-bml` versions and commit SHAs used for the baseline.

- [x] Document supported local run modes.
  - Acceptance: docs distinguish macOS prebuilt QEMU runs from Debian/Ubuntu or
    container source builds and list required packages/tools for each.

- [x] Add Debian container toolchain wrapper.
  - Acceptance: one Make target builds the toolchain image, one target opens a
    shell in the mounted umbrella tree, and one target runs the Rust link smoke
    inside the container.

- [x] Add QEMU boot smoke script.
  - Acceptance: one command launches the release image and exits successfully
    after detecting the login prompt.

- [x] Add boot timeout and log capture.
  - Acceptance: failed boots save QEMU console output to a known path and exit
    non-zero.

- [x] Document known current boot warnings.
  - Acceptance: seL4 untyped allocation messages and RTC absence are documented
    as baseline observations with example text.

- [x] Add decision and development logs.
  - Acceptance: accepted decisions and chronological development process are
    recorded in checked-in Markdown files and linked from the migration README.

- [x] Add ELF artifact audit script.
  - Acceptance: the script reports ELF type, machine, interpreter, dynamic tags,
    relocations, TLS sections, unwind sections, and undefined symbols for a
    given binary.

- [x] Capture baseline ELF audit for current userland binaries.
  - Acceptance: audit output for selected C binaries is checked in or stored as
    reproducible generated output.

- [x] Inventory existing in-guest tests.
  - Acceptance: docs list `msgpass`, `syncspace`, `suite`, and any other test
    helpers with what each currently verifies.

## Phase 1: Host Tool Hardening

- [x] Add qrvfs image fixtures.
  - Acceptance: fixtures can be generated from the current build and inspected
    by tests without booting QEMU.

- [x] Add GPT fixture coverage.
  - Acceptance: tests verify partition offsets, sizes, and labels for a known
    image.

- [x] Specify `mkfs-qrv` behavior.
  - Acceptance: docs cover block size, inode count, directory layout, and error
    behavior expected from the current C implementation.

- [x] Specify `treeqrvfs` behavior.
  - Acceptance: docs include expected output for at least one fixture image.

- [x] Create initial Rust host crate for qrvfs inspection.
  - Acceptance: `cargo test` parses a fixture and reports the same top-level
    metadata as the existing tool.

- [x] Compare Rust parser with current tool output.
  - Acceptance: a test or script fails if semantic output diverges.

## Phase 2: Rust Toolchain Spike

- [x] Pin Rust toolchain.
  - Acceptance: `rust/rust-toolchain.toml` specifies a concrete compiler
    version and required components.

- [x] Add Cargo config.
  - Acceptance: `rust/.cargo/config.toml` defines target, linker, and relevant
    rustflags without requiring per-user shell setup.

- [x] Add QSOE RISC-V target spec.
  - Acceptance: target JSON documents architecture, panic strategy, relocation
    model, linker flavor, and disabled unsupported features.

- [x] Build minimal `no_std` object.
  - Acceptance: the object compiles with `panic=abort` and no allocator.

- [x] Link minimal Rust binary through QSOE startup.
  - Acceptance: the binary uses QSOE `crt0.o`, QSOE libc, and the existing
    interpreter path.

- [x] Audit minimal Rust binary.
  - Acceptance: artifact audit shows no TLS, no unwind dependency, and no
    unsupported relocations.

- [x] Keep Rust spike out of default image.
  - Acceptance: normal `make` output is unchanged unless an explicit Rust flag
    is provided.

## Phase 3: ABI And Bindings

- [x] Create `qsoe-abi` crate.
  - Acceptance: public constants and structs needed by the first pilot are
    represented with `#[repr(C)]` where they cross the ABI.

- [x] Create `qsoe-ffi` crate.
  - Acceptance: raw extern declarations compile for the QSOE target and are not
    exposed as safe APIs directly.

- [x] Create `qsoe-ressrv` crate.
  - Acceptance: resource-server ABI structs compile as `no_std`, layout tests
    match the current C headers, and thin wrappers cover provider initialization,
    provider listen, and dispatch-loop entry.

- [x] Add safe `slogger` resource-server wrapper surface.
  - Acceptance: safe wrappers cover registration, receive, reply, and shutdown
    paths needed by `slogger`.

- [x] Add layout assertions.
  - Acceptance: tests fail if Rust struct size or alignment differs from C.

- [x] Document ownership and lifetime rules.
  - Acceptance: bindings docs explain which side owns handles, buffers, and
    reply state.

- [x] Review unsafe blocks.
  - Acceptance: every unsafe block in the binding crates has a stated invariant.

## Phase 4: `slogger-rs`

- [x] Specify current `slogger` behavior.
  - Acceptance: docs cover startup, device registration, ring size, message
    receive loop, overflow behavior, and observable logs.

- [x] Add `/dev/slog` smoke test.
  - Acceptance: a test or helper writes a log message and verifies it is
    accepted or observable through the existing interface.

- [x] Implement ring buffer in Rust.
  - Acceptance: host tests cover wraparound, full buffer behavior, and message
    truncation if applicable.

- [x] Implement QSOE service entry point.
  - Acceptance: `slogger-rs` links as a QSOE userland binary.

- [x] Add build flag for Rust `slogger`.
  - Acceptance: the RC window used one explicit make variable; after
    retirement the Rust selector is the only supported path.

- [x] Boot image with Rust `slogger`.
  - Acceptance: QEMU reaches login and console logs show `slogger-rs` alive.

- [x] Compare C and Rust boot logs.
  - Acceptance: differences are reviewed and documented.

## Phase 5: Resource-Server Pattern Promotion

- [x] Extract common service bootstrap.
  - Acceptance: `slogger-rs` and a trivial example service share the same
    wrapper path.

- [x] Add resource-server example.
  - Acceptance: example compiles and demonstrates a minimal request/reply loop.

- [x] Define error mapping.
  - Acceptance: Rust errors map to existing QSOE negative errno or status
    conventions without inventing a new ABI.

- [x] Add wrapper-level tests.
  - Acceptance: host-side tests cover state transitions that do not require
    QEMU; in-guest smoke covers the rest.

## Phase 6: `devb-virtio-rs`

- [x] Specify current virtio block driver behavior.
  - Acceptance: docs cover device discovery, queue setup, request lifecycle,
    exposed device path, and mount dependency.

- [x] Build volatile MMIO wrapper.
  - Acceptance: unsafe pointer access is isolated and reviewed.

- [x] Build virtqueue descriptor model.
  - Acceptance: descriptor ownership and mutability are represented explicitly.

- [x] Add host-side queue tests.
  - Acceptance: tests cover descriptor chaining and free-list behavior without
    hardware.

- [x] Implement opt-in Rust virtio block driver.
  - Acceptance: binary links and passes artifact audit.

- [x] Boot with Rust virtio block driver.
  - Acceptance: `/dev/vblk0` appears, qrvfs mounts at `/usr`, and login starts.

- [x] Run file access smoke.
  - Acceptance: an in-guest command can read files from `/usr`.

## Phase 7: Shared Parsers

- [x] Add CPIO parser crate.
  - Acceptance: parser handles valid and malformed fixtures without panics.

- [x] Add syscfg/sysmap view crate.
  - Acceptance: read-only views validate bounds before exposing fields.

- [x] Add ELF inspection crate.
  - Acceptance: host tests identify relocation types used by existing QSOE
    binaries.

- [x] Reuse one parser in host and guest contexts.
  - Acceptance: the same crate builds for host tests and `no_std` guest use.

## Phase 8: Additional Migrations

- [x] Rank remaining userland services.
  - Acceptance: each candidate has size, dependency, ABI surface, testability,
    and rollback scores.

- [x] Pick second Rust service.
  - Acceptance: selected component has a written mini-spec and smoke test before
    implementation.

- [x] Pick first Rust test helper.
  - Acceptance: helper validates IPC or sync behavior and is safe to include in
    test images.

- [x] Retire one C implementation after proving parity.
  - Acceptance: removal is approved only after at least one release candidate
    with Rust default and C rollback available.
  - Status: complete for the first exercises. `test_msgpass`, `slogger`, and
    `pipe` have retired C implementations after Rust-default RC evidence; see
    `RETIREMENT.md` for current status and the checklist future removals must
    repeat.

## Phase 9: Task Manager Readiness

- [x] Inventory task-manager modules.
  - Acceptance: docs separate pure logic from spawn, cap, relocation, and loader
    critical paths.

- [x] Select one non-critical internal module.
  - Acceptance: module has no direct effect on initial process creation.

- [x] Design C/Rust boundary for task-manager pilot.
  - Acceptance: boundary review includes failure behavior and rollback plan.

- [x] Add targeted boot coverage.
  - Acceptance: smoke tests exercise the selected path before Rust changes land.

## Phase 10: Kernel Reassessment

- [x] Write kernel Rust decision record.
  - Acceptance: decision uses evidence from completed userland migrations and
    explicitly accepts or rejects near-term kernel Rust work.

- [x] Identify safe kernel candidates.
  - Acceptance: candidates exclude traps, context switching, scheduler core,
    boot assembly, and seL4 capability assumptions.

- [x] Define kernel artifact audit needs.
  - Acceptance: audit covers codegen assumptions, sections, linker script
    compatibility, panic behavior, and forbidden runtime references.

## Cross-Cutting Tasks

- [x] Add CI or local equivalent for build matrix.
  - Acceptance: one command can run host tests, artifact audit, and boot smoke
    for selected configurations.

- [x] Add C source indexing workflow.
  - Acceptance: Make targets generate file lists, tags, cscope, GNU Global
    indexes, and a Bear compile database path for clangd.

- [x] Add container C indexing tools.
  - Acceptance: the Debian toolchain image includes ripgrep, Bear, clangd,
    clang-tidy, clang-tools, Universal Ctags, cscope, GNU Global, and jq.

- [x] Add tiered Rust workflow targets.
  - Acceptance: `make rust-fast`, `make rust-quality`, `make rust-abi`, and
    `make rust-deep` are documented and route to checked-in scripts.

- [x] Add `make rust-check`.
  - Acceptance: Rust formatting, linting, and tests run without building a full
    boot image.

- [x] Isolate Rust Cargo target directories per host/workflow.
  - Acceptance: workflow scripts set `CARGO_TARGET_DIR` by default so macOS and
    Linux/container checks do not churn the same cache.

- [x] Add `make audit-artifacts`.
  - Acceptance: audit can be run on all installed userland binaries.

- [x] Add bounded clang-tidy wrapper.
  - Acceptance: one command runs a curated checker set against the active
    compile database without requiring full-tree editor setup.

- [x] Add Rust dependency policy.
  - Acceptance: cargo-deny or cargo-vet configuration records allowed licenses,
    advisory handling, source policy, and review/audit expectations.

- [x] Add Rust parser fuzz targets.
  - Acceptance: qrvfs and future GPT/ELF/CPIO parsers have cargo-fuzz targets
    and a bounded smoke command suitable for a deep local gate.

- [x] Add Rust coverage reporting.
  - Acceptance: host crates can produce coverage for parser and ABI tests,
    preferably with generated output under ignored build directories.

- [x] Add unsafe-code review checklist.
  - Acceptance: checklist is referenced by Rust migration PRs.

- [x] Add migration status table.
  - Acceptance: docs show C default, Rust opt-in, Rust default, and retired
    status for each component.

- [x] Add release-note template.
  - Acceptance: template records language changes, rollback flags, test
    evidence, and known limitations.
