# QSOE Rust Migration Development Log

Last updated: 2026-06-23 23:11 CEST.

This log tracks the development process for the Rust migration and reproducible
toolchain work. It records what changed, what was observed, what failed, and
what was verified. Append new entries at the top.

Entry template:

```text
## YYYY-MM-DD HH:MM TZ - Short Title

Scope:
- ...

Commands:
- ...

Result:
- ...

Follow-up:
- ...
```

## 2026-06-23 23:11 CEST - Error Mapping Defined

Scope:

- Added explicit Rust wrappers for the two existing QSOE status conventions:
  `ReplyStatus` for direct `MsgReply` labels and `MethodStatus` for
  resource-server method returns.
- Added host tests for positive direct errno labels, negative method errno
  results, and the `QSOE_DEFER` sentinel.
- Documented that Rust code preserves the current `0`/positive errno and
  `>=0`/`-errno`/defer ABI conventions.
- Marked the Phase 5 error-mapping task complete.

Commands:

- `make rust-quality`

Result:

- Direct-service and method-style Rust error mapping is explicit and covered
  by the normal host quality gate.

Follow-up:

- Add wrapper-level tests for state transitions and receive-loop behavior.

## 2026-06-23 23:01 CEST - Resource Server Example Documented

Scope:

- Turned `qsoe-service-example-rs` into a documented direct resource-server
  example with a named request classifier.
- Added `host-tests` feature coverage for lifecycle acknowledgements, write
  byte counts, read payload caps, and unsupported request handling.
- Included the example package in `make rust-quality` host tests.
- Marked the Phase 5 resource-server example task complete.

Commands:

- `make rust-quality`
- `make container-rust-service-example-link-smoke`

Result:

- The example compiles, documents its minimal request/reply loop, and links
  through the QSOE userland CRT/libc path.

Follow-up:

- Define common error mapping for Rust direct services.

## 2026-06-23 22:47 CEST - Direct Service Bootstrap Extracted

Scope:

- Added `DirectRequestHandler` and `DirectServer` to `qsoe-ressrv`.
- Moved `slogger-rs` onto the shared direct-service register, detach, and
  receive-loop path.
- Added `qsoe-service-example-rs`, a tiny service that uses the same wrapper
  path for connect, write, read, and close-style requests.
- Added a link-smoke target and Rust README note for the example service.
- Marked the Phase 5 common bootstrap task complete.

Commands:

- `make rust-quality`
- `make container-rust-slogger-link-smoke`
- `make container-rust-service-example-link-smoke`

Result:

- `slogger-rs` and the example service compile through the same direct-service
  bootstrap path.
- Both service binaries link through the QSOE userland CRT/libc path.

Follow-up:

- Expand the example into a documented resource-server sample.

## 2026-06-23 22:37 CEST - C And Rust Slogger Boot Logs Compared

Scope:

- Rebuilt and booted the default C `slogger` LQ image.
- Compared C boot milestones against the latest Rust `slogger-rs` boot-smoke
  log.
- Documented reviewed differences in `SLOGGER_BOOT_COMPARE.md`.
- Marked the Phase 4 boot-log comparison task complete.

Commands:

- `make -C quser cpio LIBC_SO=... RTLD_SO=... DYNLIBC_SO=...`
- `make -C lq`
- `scripts/boot-smoke.sh -k lq -t 180 -o build/boot-smoke-lq-c-compare.log`
- `strings build/boot-smoke-lq-c-compare.log | rg "slogger|fs-qrv: mounted|login:|devb-virtio|dispatcher ready|spawning /sbin/init"`
- `strings build/boot-smoke-lq-20260623-223518.log | rg "slogger|fs-qrv: mounted|login:|devb-virtio|dispatcher ready|spawning /sbin/init"`

Result:

- Both C and Rust boots reached login.
- Rust startup logs are shorter: no pid, chid, or ring-size text yet.
- Device, filesystem, and login milestones matched.

Follow-up:

- Decide whether pid/chid/ring-size startup parity is needed before replacing
  the default C service.

## 2026-06-23 22:35 CEST - Rust Slogger Boot Smoke Added

Scope:

- Added `make rust-slogger-boot-smoke`.
- Added a wrapper that builds an LQ modpkg archive with only
  `sbin/slogger` replaced by the selected Rust artifact.
- Rebuilt the LQ QEMU image with `MODPKG_CPIO` pointing at that opt-in archive.
- Let `boot-smoke.sh` accept a custom slogger startup pattern.
- Marked the Phase 4 Rust boot-image task complete.

Commands:

- `make rust-slogger-boot-smoke`

Result:

- QEMU reached login with `[slogger-rs] alive` in the console log.

Follow-up:

- Compare C and Rust boot logs before making the Rust service less
  experimental.

## 2026-06-23 22:28 CEST - Rust Slogger Build Flag Added

Scope:

- Added `QSOE_RUST_SLOGGER`, defaulting to the existing C `slogger`.
- Added `make slogger-artifact`, which stages the selected implementation at
  `build/rust/selected/sbin/slogger.elf`.
- Added `QSOE_RUST_SLOGGER=1 make slogger-artifact` for the Rust pilot.
- Kept CPIO and boot-image substitution for the next task.
- Marked the Phase 4 build-flag task complete.

Commands:

- `make slogger-artifact`
- `QSOE_RUST_SLOGGER=1 make slogger-artifact`
- `make container-slogger-artifact`
- `QSOE_RUST_SLOGGER=1 make container-slogger-artifact`

Result:

- The C service remains the default selected artifact.
- One explicit make variable selects the Rust `slogger-rs` artifact.

Follow-up:

- Use the selected artifact in an opt-in boot image and run the Rust `slogger`
  boot smoke.

## 2026-06-23 22:25 CEST - Rust Slogger Entry Point Added

Scope:

- Added `qsoe-slogger-rs`, a no-std staticlib that exports the QSOE userland
  `main(argc, argv, envp)` entry point.
- Registered `/dev/slog` through the direct resource-server wrapper.
- Wired `_IO_CONNECT`, `_IO_DUP`, close, write, read, and fstat handlers to the
  Rust slog ring.
- Added QSOE `EOK` and `ENOSYS` ABI constants.
- Parameterized the Rust QSOE link smoke helper and added
  `make rust-slogger-link-smoke`.
- Marked the Phase 4 service-entry-point task complete.

Commands:

- `make rust-quality`
- `make container-rust-qsoe-link-smoke`
- `make container-rust-slogger-link-smoke`
- `bash -n scripts/rust-qsoe-link-smoke.sh scripts/rust-workflow.sh scripts/rust-check.sh`

Result:

- `slogger-rs` links through the QSOE `crt0.o` and `libc.so` userland path.
- The link smoke strips inert unwind metadata before the strict ELF audit.
- The existing minimal Rust link smoke still passes with the parameterized
  script.
- The C `slogger` remains the default boot service.

Follow-up:

- Add the explicit build flag that selects Rust `slogger` for boot images.

## 2026-06-23 21:32 CEST - Rust Slogger Ring Added

Scope:

- Added the `qsoe-slogger` no-std crate.
- Implemented the byte-ring behavior needed by `slogger-rs`.
- Documented that the slog event header is the current 24-byte LP64 ABI layout,
  not the stale 16-byte wording in the ignored component header.
- Recorded that the stale `sys/slog.h` ring-size comment still needs an
  upstream component-source correction because `libc/` is ignored here.
- Added the crate to Rust workflow test coverage.
- Marked the Phase 4 Rust ring-buffer task complete.

Commands:

- `cargo test --manifest-path rust/Cargo.toml -p qsoe-slogger`
- `make rust-quality`
- `scripts/container-toolchain.sh run bash -lc 'cd rust && cargo check -p qsoe-slogger --target riscv64gc-unknown-none-elf'`
- RISC-V C layout probe for `qsoe_slog_event_t` with
  `riscv64-linux-gnu-gcc`.

Result:

- Host tests passed, including append, drain, wraparound, exact-full,
  drop-oldest eviction, oversized rejection, incomplete-event read guard, read
  caps, and corrupt head-event clamping during eviction.
- `qsoe-slogger` compiled for the RISC-V no-std target in the Debian
  container. The compile emitted the existing `f`/`d` target-feature warnings.

Follow-up:

- Add the `/dev/slog` readback smoke before replacing the C service.
- Correct the stale `libc/include/sys/slog.h` comments in the component source
  repository.

## 2026-06-23 21:25 CEST - Direct Resource-Server Wrapper Added

Scope:

- Added shared Rust ABI constants for the `_IO_*` resource-manager protocol.
- Added `tm_stat_t` as `qsoe_abi::TmStat`.
- Added a direct-service wrapper surface in `qsoe-ressrv` for the current
  `slogger` model: channel ownership, path registration, daemon-ready detach,
  receive, pulse detection, replies, and explicit shutdown.
- Added `IoRequest` and `IoReply` wire buffers for the `slogger` request/reply
  shape.
- Marked the Phase 3 `slogger` wrapper task complete.

Commands:

- `cargo check --manifest-path rust/Cargo.toml --workspace`
- `cargo test --manifest-path rust/Cargo.toml -p qsoe-abi -p qsoe-ressrv`
- `make rust-quality`
- `scripts/container-toolchain.sh run bash -lc 'cd rust && cargo check -p qsoe-ressrv --target riscv64gc-unknown-none-elf'`

Result:

- Host Rust quality checks passed.
- `qsoe-abi` and `qsoe-ressrv` layout and helper tests passed.
- `qsoe-ressrv` compiled for the RISC-V no-std target in the Debian
  container. The compile emitted the existing `f`/`d` target-feature warnings.

Follow-up:

- Implement the Rust `slogger` ring buffer with host tests before linking a
  `slogger-rs` binary.

## 2026-06-23 21:20 EEST - Linux Handover Written

Scope:

- Added `HANDOVER.md`.
- Linked it from the migration README.

Commands:

- `gh --version`
- `gh auth status`
- `git status -sb --untracked-files=all`
- `git remote -v`

Result:

- The active GitHub CLI account is `dmytro-yemelianov`.
- Current `origin` remains `https://gitlab.com/qsoe/os.git`.
- Handover now records Linux package setup, restore commands, validation state,
  caveats, and next tasks.

Follow-up:

- Create a private GitHub handover repository and push this snapshot without
  changing the GitLab `origin`.

## 2026-06-23 21:00 EEST - Rust Workflow Tiers Added

Scope:

- Added `WORKFLOW.md`.
- Added `scripts/rust-env.sh` for scoped Cargo target directories.
- Added `scripts/rust-workflow.sh`.
- Added Make targets for `rust-fast`, `rust-quality`, `rust-abi`, and
  `rust-deep`, plus container aliases.
- Added rust-analyzer to the Debian Rust toolchain component list.
- Added `rust/deny.toml` for the first Rust dependency policy gate.

Commands:

- `make rust-fast`
- `make rust-quality`
- `make check-qrvfs-rust-fixture`
- `make rust-deep`
- `cargo deny --manifest-path rust/Cargo.toml check -c rust/deny.toml`
- `make container-toolchain-build`
- `make container-check`
- `make container-rust-abi`
- `make -n rust-abi rust-deep container-rust-fast container-rust-quality`

Result:

- Rust workflow now has separate fast, normal-quality, ABI, and optional deep
  gates.
- Host and container Cargo artifacts no longer share the same default target
  directory.
- `rust-deep` exposed the missing cargo-deny policy; adding `rust/deny.toml`
  made the deep gate pass when cargo-deny is installed.
- The rebuilt Debian container image accepts the rust-analyzer component and
  passes `container-check`.
- Container Rust ABI smoke still links `build/rust/qsoe-minimal-rs.elf` with
  no TLS or unwind sections.

Follow-up:

- Revisit cargo-vet once third-party Rust dependencies appear.
- Add cargo-fuzz targets when qrvfs/GPT/ELF/CPIO parser work expands.

## 2026-06-23 21:00 EEST - C Indexing Workflow Added

Scope:

- Added `.clangd`.
- Added `scripts/c-index.sh`.
- Added C indexing Make targets.
- Added container wrapper commands for static C indexes and compile database
  capture.
- Added C indexing/analysis packages to the Debian toolchain image.
- Added `INDEXING.md`.

Commands:

- `docker run --rm debian:trixie ... apt-cache policy ...`
- `make container-toolchain-build`
- `make container-index-c-static`

Result:

- Debian Trixie provides ripgrep, Bear, clangd, clang-tidy, clang-tools,
  Universal Ctags, cscope, GNU Global, and jq.
- The workflow now separates fast static navigation from slower compile database
  capture.
- The rebuilt Debian image generated static C indexes for 816 QSOE-owned C/ASM
  files.

Follow-up:

- Capture a small compile database first, then decide whether a clean full-tree
  Bear capture is worth the time for the active refactoring pass.

## 2026-06-23 20:40 EEST - Rust qrvfs Host Inspector Added

Scope:

- Added `rust/crates/qsoe-qrvfs`.
- Added `qrvfs-tree`, a Rust tree-format inspector.
- Added `scripts/check-qrvfs-rust-fixture.sh`.
- Added `make check-qrvfs-rust-fixture`.
- Extended `make container-check` to include the Rust/C qrvfs comparison.

Commands:

- `make rust-check`
- `make check-qrvfs-rust-fixture`
- `make container-check`

Result:

- Rust parser unit tests passed.
- Rust `qrvfs-tree` output matched C `treeqrvfs` output byte-for-byte for the
  generated fixture.
- Debian container check passed with host fixtures, Rust checks, and qrvfs
  Rust/C comparison.

Follow-up:

- Keep `mkfs-qrv` as the image writer until a Rust writer has fixture and
  byte/semantic compatibility gates.

## 2026-06-23 20:40 EEST - C `slogger` Behavior Specified

Scope:

- Reviewed `quser/sbin/slogger/main.c`.
- Reviewed libc `slogf`/`slogb` event construction.
- Reviewed `sloginfo` and existing suite slog smoke.
- Added `SLOGGER.md`.

Commands:

- `sed -n '1,260p' quser/sbin/slogger/main.c`
- `sed -n '1,260p' libc/qsoe/slog.c`
- `sed -n '1,260p' libc/include/sys/slog.h`
- `sed -n '220,390p' libc/include/qsoe/tm_msgs.h`

Result:

- Current startup, ring, wire protocol, read/write/fstat/open/dup/close, client
  event format, and consumer behavior are documented.
- The implemented ring size is recorded as `64 KiB`.
- A stale `256 KiB` ring-size comment in `sys/slog.h` is recorded as a
  follow-up.
- The `/dev/slog` readback smoke remains open because the existing suite only
  checks `slogf` return values.

Follow-up:

- Add an automated `/dev/slog` write/readback smoke before implementing
  `slogger-rs`.

## 2026-06-23 20:04 EEST - C Userland ELF Baseline Captured

Scope:

- Added `scripts/capture-elf-baseline.sh`.
- Added `make elf-baseline`.
- Added `make container-elf-baseline`.
- Added `ELF_BASELINE.md`.
- Generated full raw audit output under `build/elf-baseline/`.

Commands:

- `scripts/container-toolchain.sh run scripts/capture-elf-baseline.sh --raw-dir build/elf-baseline`
- `make -n elf-baseline container-elf-baseline`

Result:

- Eight representative C userland artifacts were summarized:
  - `slogger`.
  - `devb-virtio`.
  - `fs-qrv`.
  - `qsh`.
  - `login`.
  - `test_msgpass`.
  - `test_syncspace`.
  - `suite`.
- Raw audit output totals 1,770 lines in ignored build output.
- All selected artifacts use `/lib/ld-qsoe.so.1` and `libc.so`.
- Relocations are within the current QSOE userland baseline.
- No selected C artifact uses TLS.
- All selected C artifacts include unwind-related sections.

Follow-up:

- Keep the first Rust userland gate stricter than the C baseline: no TLS and no
  unwind sections unless loader/runtime support is explicitly reviewed.

## 2026-06-23 19:59 EEST - Decision And Process Tracking Added

Scope:

- Added an explicit decision log.
- Added this chronological development log.
- Linked both from the migration README.

Commands:

- `date '+%Y-%m-%d %H:%M:%S %Z'`

Result:

- Decision tracking is now part of the repository docs.
- Future migration work has a stable place to record reasoning and evidence.

Follow-up:

- Keep adding decisions as `D-###` entries in `DECISIONS.md`.
- Keep adding process entries here whenever toolchain, build, boot, or artifact
  behavior changes.

## 2026-06-23 - Debian Container Toolchain Validated

Scope:

- Added `toolchains/debian/Dockerfile`.
- Added `scripts/container-toolchain.sh`.
- Added Make targets:
  - `container-toolchain-build`.
  - `container-shell`.
  - `container-check`.
  - `container-rust-qsoe-link-smoke`.
  - `container-source-build`.
- Documented the toolchain in `TOOLCHAIN.md`.

Commands:

- `colima start`
- `make container-toolchain-build`
- `scripts/container-toolchain.sh run bash -c 'python3 -c "import yaml, pyfdt.pyfdt, jinja2, ply, jsonschema, elftools"; rustc --version; riscv64-linux-gnu-gcc --version | head -1; qemu-system-riscv64 --version | head -1'`
- `make container-check`
- `make container-source-build`
- `make container-rust-qsoe-link-smoke`
- `scripts/container-toolchain.sh run bash -c 'QSOE_RUST_COMPILE=1 scripts/rust-check.sh'`
- `scripts/container-toolchain.sh run scripts/boot-smoke.sh -k lq -t 120`

Result:

- Container image built successfully.
- Tool versions observed:
  - Rust `1.95.0`.
  - Cargo `1.95.0`.
  - RISC-V GCC `14.2.0`.
  - GNU binutils `2.44`.
  - QEMU `10.0.8`.
  - Kconfiglib `14.1.0`.
  - PyYAML `6.0.2`.
  - Jinja2 `3.1.6`.
- `make container-check` passed.
- `make container-source-build` passed for NQ, quser, LQ, seL4, taskman, and
  the QSOE/L QEMU image.
- Rust link smoke passed and produced `build/rust/qsoe-minimal-rs.elf`.
- LQ boot smoke reached login from the container-built image.

Follow-up:

- Keep QEMU `11.0.1+` available outside this Debian image for NQ AIA boot
  experiments.

## 2026-06-23 - Container Toolchain Failures Resolved

Scope:

- Iterated on missing and incompatible Linux build dependencies.

Observed failures:

- macOS host reported `apt: command not found`.
- Initial local source build could not find `riscv64-linux-gnu-gcc`.
- Debian Bookworm cross tools rejected `-march=..._zicntr`.
- LQ seL4 CMake failed on missing Python modules:
  - `yaml`.
  - `pyfdt.pyfdt`.
  - `jinja2`.

Decisions:

- Use Debian/container source builds from macOS.
- Switch container base from Bookworm to Trixie.
- Add `python3-yaml`.
- Add `pyfdt` `0.3` from PyPI because Debian lacks `pyfdt.pyfdt`.
- Add seL4 Python generator dependencies from Debian packages.

Result:

- The next `make container-source-build` completed successfully.

Follow-up:

- If a future seL4 update adds more Python imports, prefer Debian packages
  first and document any PyPI fallback.

## 2026-06-23 - Rust Link Smoke Completed

Scope:

- Added a minimal Rust staticlib binary crate.
- Linked it through QSOE startup and libc.
- Audited the produced ELF.

Commands:

- `make container-rust-qsoe-link-smoke`

Result:

- Linked `build/rust/qsoe-minimal-rs.elf`.
- ELF shape:
  - `EXEC` RISC-V.
  - Interpreter `/lib/ld-qsoe.so.1`.
  - Needed library `libc.so`.
  - No TLS sections.
  - No unwind sections.
  - Relocations limited to current accepted userland baseline.
- Task backlog updated to mark minimal Rust link and audit gates complete.

Follow-up:

- The artifact is still a spike and is not installed into the default image.

## 2026-06-23 - Rust Workspace And ABI Spike Added

Scope:

- Added `rust/` workspace.
- Added pinned Rust toolchain configuration.
- Added Cargo configuration and QSOE RISC-V target file.
- Added crates:
  - `qsoe-abi`.
  - `qsoe-ffi`.
  - `qsoe-ressrv`.
  - `qsoe-minimal-rs`.

Commands:

- `make rust-check`
- `QSOE_RUST_COMPILE=1 scripts/rust-check.sh`

Result:

- Host Rust tests passed.
- RISC-V compile path passed once the container provided the toolchain.
- Layout assertions for QSOE and resource-server ABI structs passed.

Follow-up:

- Expand wrappers only after specifying the first real service behavior.

## 2026-06-23 - Safety Net Scripts Added

Scope:

- Added host fixture checks.
- Added boot smoke helper.
- Added ELF audit helper.
- Added Make targets for repeatable checks.

Commands:

- `make check-host-tools`
- `bash -n scripts/*.sh`
- `python3 -m py_compile scripts/check-gpt-fixture.py`

Result:

- qrvfs fixture check passed.
- GPT fixture check passed.
- Shell syntax checks passed.
- Python compile check passed.

Follow-up:

- Capture baseline ELF audit output for selected C userland binaries.

## 2026-06-23 - Migration Specs, Plan, And Backlog Written

Scope:

- Added migration documentation:
  - `README.md`.
  - `BASELINE.md`.
  - `HOST_TOOLS.md`.
  - `RUST_SPIKE.md`.
  - `BINDINGS.md`.
  - `SPEC.md`.
  - `PLAN.md`.
  - `TASKS.md`.

Decisions captured:

- No wholesale rewrite.
- Preserve C boot path and rollback.
- Start with baseline, fixtures, artifact audit, and minimal Rust spike.
- Prefer `slogger-rs` as the first in-guest service pilot.
- Defer libc, dynamic loader, task-manager loader paths, and kernels.

Result:

- Migration is now planned as incremental, evidence-driven work with acceptance
  criteria.

Follow-up:

- Start Phase 4 only after `slogger` behavior and `/dev/slog` smoke coverage
  are specified.

## 2026-06-23 - Baseline Boot And Source Context Reviewed

Scope:

- Reviewed cloned QSOE release components under the local umbrella tree.
- Recorded release component versions and commit SHAs.
- Reviewed local run modes and initial boot behavior.

Observed:

- Release components are checked out at detached release tags.
- QSOE/L boot reached user space and login.
- Known boot messages included seL4 untyped allocation warnings and missing RTC
  recognition.

Result:

- Baseline component SHAs and known boot warnings are documented in
  `BASELINE.md`.

Follow-up:

- Keep release tags stable while planning Rust migration.
