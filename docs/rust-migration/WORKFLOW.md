# QSOE Rust Workflow Optimization

This document defines the Rust-side workflow for the migration. It complements
the C indexing workflow: Rust source navigation should use Cargo and
`rust-analyzer`, while QSOE ABI confidence still comes from explicit link,
artifact, and boot gates.

## Goals

- Keep the edit loop fast enough to run after small changes.
- Keep quality gates deterministic and cheap enough for pre-push use.
- Keep completeness gates focused on QSOE-specific risks: ABI layout, freestanding
  codegen, ELF shape, and boot behavior.
- Avoid cross-host Cargo cache churn between macOS and the Debian container.

## Tiers

| Tier | Command | Purpose | Expected Cost |
| --- | --- | --- | --- |
| Fast | `make rust-fast` | `cargo check` plus focused host library tests. | Lowest; use while editing. |
| Quality | `make rust-quality` or `make rust-check` | Formatting, full workspace check, clippy, host tests. | Normal pre-push gate. |
| ABI | `make rust-abi` | Link the minimal Rust staticlib through QSOE `crt0.o`/`libc.so` and run strict ELF audit. | Requires built QSOE C artifacts. |
| Deep | `make rust-deep` | Docs, tests, and optional tools such as nextest, Miri, and cargo-deny when installed. | Slow or environment-dependent. |

Container equivalents are available for Linux-reproducible checks:

```sh
make container-rust-fast
make container-rust-quality
make container-rust-abi
make container-rust-deep
```

`container-check` continues to run host fixtures, the normal Rust quality gate,
and the Rust/C qrvfs fixture comparison.

## Editor And Indexing

Use `rust-analyzer` against the checked-in Rust workspace:

```text
rust/Cargo.toml
```

Do not force the whole editor workspace to the QSOE/RISC-V user target. The
current workspace contains host-side tools such as `qsoe-qrvfs`, which need
`std` and should be indexed/tested for the host target. RISC-V and QSOE ELF
properties are validated by scripts, not by the editor.

Recommended editor behavior:

- Open `rust/` as the Cargo workspace root, or configure the editor to link
  `rust/Cargo.toml`.
- Use rust-analyzer's default host checks for completion and diagnostics.
- Run `make rust-abi` only after the C tree has built the QSOE startup and libc
  artifacts.
- Treat any generated QSOE target JSON issues as script/CI failures first,
  then decide whether editor configuration needs to follow.

The Debian toolchain image installs the rust-analyzer component so containerized
editors or devcontainers can use the same pinned Rust toolchain as the checks.

## Cargo Target Directories

QSOE development commonly alternates between macOS host checks and Linux
container checks. Cargo's default `rust/target` directory is shared by both,
which causes needless invalidation and noisy dependency files because host
artifacts are not portable across those environments.

The Rust workflow scripts now set `CARGO_TARGET_DIR` when the caller has not
already set it:

```text
rust/target/host-<os>-<arch>
rust/target/qsoe-link-<os>-<arch>
```

Examples:

```text
rust/target/host-darwin-aarch64
rust/target/host-linux-aarch64
rust/target/host-linux-x86_64
rust/target/qsoe-link-linux-x86_64
```

This preserves Cargo incremental speed within each environment and avoids
macOS/container cache contention. Developers can still override the location:

```sh
CARGO_TARGET_DIR=/tmp/qsoe-rust-target make rust-quality
```

## Quality Policy

`make rust-quality` is the minimum gate for changes under `rust/`:

- `cargo fmt --all --check`
- `cargo check --workspace`
- `cargo clippy --workspace -- -D warnings`
- host tests for `qsoe-abi`, `qsoe-ressrv`, and `qsoe-qrvfs`

`make rust-fast` is intentionally weaker. It exists to keep edit cadence high,
not to replace review gates.

## Completeness Policy

Rust code is not considered ready for QSOE userland merely because host tests
pass. A component that can enter an image needs:

- host tests for pure logic and parser behavior;
- fixture parity against the current C tool or service where applicable;
- ABI/layout assertions for every cross-language struct;
- QSOE target compile or link evidence;
- strict ELF audit for TLS, unwind sections, interpreter, relocations, and
  dynamic dependencies;
- QEMU boot smoke before replacing a C default.

For current pilot work, the order is:

1. Prove behavior with host tests and fixtures.
2. Link an opt-in QSOE userland artifact.
3. Audit the artifact.
4. Boot with an explicit Rust selection flag.
5. Compare boot logs and service behavior against the C baseline.

## Optional Deep Tools

`make rust-deep` runs the checks available in the local environment:

- `cargo doc --workspace --no-deps` is always run.
- `cargo nextest run` is used when `cargo-nextest` is installed; otherwise the
  script falls back to `cargo test`.
- `cargo miri test` is used when Miri is installed.
- `cargo deny check -c rust/deny.toml` is used when cargo-deny is installed.

Set this when missing optional tools should fail the run:

```sh
QSOE_RUST_DEEP_REQUIRE=1 make rust-deep
```

Miri and fuzzing are deep gates for parser and unsafe-boundary work, not default
edit-loop tools. Fuzz targets should be added for qrvfs, GPT, ELF, CPIO, and
message parsers as they move from planning into implementation.

## CI Shape

The checked-in GitHub Actions workflow keeps the same tiers and publishes
GitHub Checks for CodeRabbit review context:

| Job | Command | Notes |
| --- | --- | --- |
| Toolchain image | `make container-toolchain-build` | Builds the Debian trixie image used by all Linux-reproducible gates. |
| Source build | `make container-source-build` | Runs `make prepare` when release components are missing, then builds NQ and LQ. |
| Fixtures and Rust quality | `make container-check` | Includes host tools, Rust quality, and qrvfs Rust/C parity. |
| Rust ABI | `make container-rust-abi` | Requires C source build artifacts. |
| C analysis | `QSOE_INDEX_CLEAN=1 QSOE_INDEX_DB_FLAVOR=container make index-c-compile-db` and bounded `make tidy-c` | Rebuilds under Bear, then runs the curated clang-tidy pass against container paths. |
| Boot | `scripts/container-toolchain.sh run scripts/boot-smoke.sh -k lq -t 120` | Required before enabling any Rust service in an image. |
| Deep | `make rust-deep` | Scheduled or before risky parser/unsafe changes. |

The workflow intentionally uses `runs-on: [self-hosted, X64]` to match the
hosted runner label used by the main Rapsody CI jobs.

## External References

- Cargo `check`: <https://doc.rust-lang.org/cargo/commands/cargo-check.html>
- rust-analyzer: <https://rust-analyzer.github.io/book/>
- Clippy: <https://doc.rust-lang.org/clippy/>
- Miri: <https://github.com/rust-lang/miri>
- cargo-nextest: <https://nexte.st/>
- cargo-fuzz: <https://rust-fuzz.github.io/book/cargo-fuzz.html>
- cargo-deny: <https://embarkstudios.github.io/cargo-deny/>
- cargo-vet: <https://mozilla.github.io/cargo-vet/>
- sccache Rust notes: <https://raw.githubusercontent.com/mozilla/sccache/main/docs/Rust.md>
