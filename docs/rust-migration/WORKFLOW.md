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
the Rust/C qrvfs fixture comparison, and the built-ELF relocation fixture.

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

## Codebase Discovery Order

Use the Codebase Memory MCP graph before broad text search when navigating code
definitions, callers, callees, or migration impact. The preferred order is:

1. `search_graph` for functions, structs, classes, modules, and other named
   code entities.
2. `trace_path` for caller/callee and dependency impact.
3. `get_code_snippet` for exact symbol source after `search_graph` has found
   the qualified name.
4. `query_graph` or `detect_changes` for cross-cutting impact questions when
   the standard lookups are too broad.

Fall back to `rg`, `git grep`, Cargo metadata, or direct file reads only when
the graph is unavailable, the target is non-code, or the search is for literal
text such as log lines, Make variables, CI YAML, shell scripts, or issue
metadata. When a migration PR relies on fallback discovery because the graph
tool is unavailable, mention that in the PR validation notes so reviewers know
the impact analysis was text-based.

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

## Container Cache And `sccache`

Container runs keep persistent dependency/compiler cache state under:

```text
.qsoe-cache/container/home
.qsoe-cache/container/cargo-home
.qsoe-cache/container/sccache
```

The cache root can be changed, or disabled entirely:

```sh
QSOE_CONTAINER_CACHE_ROOT=/var/tmp/qsoe-cache make container-rust-quality
QSOE_CONTAINER_CACHE=0 make container-rust-quality
```

The GitHub Actions CI cache stores only Cargo registry/git state and the
`sccache` object store:

```text
.qsoe-cache/container/cargo-home/registry
.qsoe-cache/container/cargo-home/git
.qsoe-cache/container/sccache
```

It deliberately does not cache `build/release`, `rust/target`, component build
directories, QEMU images, or boot logs. The cache root is outside `build/` so
`make clean` and compile-database regeneration cannot erase an active cache
mount. Final outputs remain rebuilt by the normal Make and smoke-test gates.

CI enables both Rust and compiler-name-preserving C/C++ wrappers:

```text
QSOE_SCCACHE=1
QSOE_SCCACHE_C=1
```

`QSOE_SCCACHE=1` sets `RUSTC_WRAPPER=sccache` and defaults
`CARGO_INCREMENTAL=0` so Rust compile calls are cacheable in CI. Override
`CARGO_INCREMENTAL` explicitly when local incremental behavior matters more
than shared compiler cache hits. `QSOE_SCCACHE_C=1` prepends wrappers for `cc`,
`gcc`, `clang`, and the RISC-V GNU compiler names inside the container without
editing component Makefiles. Disable either variable while debugging
cache-sensitive compiler behavior.

Prefer non-login shells for custom cached container commands:

```sh
scripts/container-toolchain.sh run bash -c 'make rust-quality'
```

The container profile preserves an already-mounted `CARGO_HOME` and reapplies
the `sccache` wrapper path, but the CI workflow avoids login-shell surprises on
cache-sensitive steps.

Cache invalidation is keyed on:

- `rust/Cargo.lock`, `rust/fuzz/Cargo.lock`, Rust manifests, and
  `rust/rust-toolchain.toml`;
- `toolchains/debian/Dockerfile`;
- `scripts/container-toolchain.sh`, `scripts/sccache-compiler-wrapper.sh`, and
  Rust workflow scripts;
- component override patches under `patches/components/`.

Changes outside that set can still affect final OS images, which is why final
build products are not cached. Use this for cache visibility:

```sh
make container-sccache-stats
```

CI also sets `QSOE_SCCACHE_STATS=1`, which prints per-container-run `sccache`
stats before each container exits. The counters are not aggregated across
containers, but the backed object store persists across runs.

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

Rust migration PRs must include an unsafe-review line. Use
`UNSAFE_REVIEW.md` for the checklist, or state that the PR adds no new unsafe
code or FFI boundary changes.

For current pilot work, the order is:

1. Prove behavior with host tests and fixtures.
2. Link an opt-in QSOE userland artifact.
3. Audit the artifact.
4. Boot with an explicit Rust selection flag.
5. Compare boot logs and service behavior against the C baseline.

## Issue-Backed Tooling Gates

Migration tooling is tracked in the same GitHub Issues roadmap metadata as
components and phases. Tooling work should use `kind: "tooling"` and the
`roadmap:tooling` label so the Pages dashboard can separate process
improvements from C-to-Rust component candidates.

| Issue | Gate | Workflow role |
| --- | --- | --- |
| #200 | Component gate harness and roadmap sync | Generate the per-component evidence/RC/rollback checklist from issue metadata and reject malformed roadmap state in CI and before dashboard publication. |
| #201 | CI cache and sccache acceleration | Shorten repeated Rust/C taskman and smoke-test loops with Cargo registry/git cache, `sccache`, and explicit no-build-output cache boundaries. |
| #202 | Static analysis and supply-chain gates | Run CodeQL and dependency-review as non-blocking checks first, then promote after clean PR and main baselines. |
| #203 | Rust host test and parser fuzz workflow | Run `container-rust-deep` and `container-rust-fuzz-smoke` as non-blocking CI checks first, then promote parser-heavy PR gates after baseline stability. |

Tooling gates become required only after they have a clean baseline and a
rollback plan for false positives or cache invalidation. Until then, they may
land as documented, non-blocking, or scheduled checks. A component migration
PR should not be blocked on a brand-new tool the same PR introduces unless that
tool's issue explicitly says the gate has been promoted.

As of the #202/#203 rollout, CodeQL, dependency review, Rust deep checks, and
bounded parser fuzz smoke are warning-mode gates. Treat failures as evidence to
tune configuration, permissions, corpus shape, or runtime cost before promotion.

## Per-Component Operating Loop

For each component status transition:

1. Read the component's roadmap issue and docs before editing.
2. Generate the component checklist:

   ```sh
   make roadmap-component-gate COMPONENT=<component-id-or-issue-number>
   ```

3. Run the component evidence target, runtime smoke, RC smoke, and rollback
   smoke required by the issue metadata.
4. Update docs and the issue metadata in the same PR that changes selector
   state.
5. Validate roadmap metadata:

   ```sh
   make roadmap-validate
   ```

6. After merge, record the PR CI run, merge commit, and successful main CI run
   in the roadmap issue.
7. Keep the next gate explicit: opt-in, Rust-default RC, C retirement, or
   deferral.

`make roadmap-validate` fetches `roadmap` issues through the GitHub Issues API,
parses every `qsoe-roadmap:v1` metadata block, and verifies kind/status label
consistency. The main CI workflow runs it before build work starts, and the
Roadmap Pages workflow runs it before publishing the dashboard artifact.

`make roadmap-component-gate` is the review preflight for component moves. It
prints the current selectors, evidence commands, runtime/boot smokes, RC
commands, C rollback files/commands, and issue-update checklist from the
selected component's issue metadata. Treat missing output in one of those
sections as a metadata gap to fix before changing selector state.

## Optional Deep Tools

`make rust-deep` runs the checks available in the local environment:

- `cargo doc --workspace --no-deps` is always run.
- `cargo nextest run` is used when `cargo-nextest` is installed; otherwise the
  script falls back to `cargo test`.
- `cargo miri test` is used when Miri is installed.
- `cargo deny check -c rust/deny.toml` is used when cargo-deny is installed.
- `scripts/rust-fuzz-smoke.sh` is used when nightly cargo-fuzz is available.
- `scripts/rust-coverage.sh` is used when cargo-llvm-cov is installed.

Set this when missing optional tools should fail the run:

```sh
QSOE_RUST_DEEP_REQUIRE=1 make rust-deep
```

Miri and fuzzing are deep gates for parser and unsafe-boundary work, not default
edit-loop tools. Fuzz targets should be added for qrvfs, GPT, ELF, CPIO, and
message parsers as they move from planning into implementation.

Run the bounded parser fuzz smoke directly with:

```sh
make rust-fuzz-smoke
```

The current fuzz package covers `qrvfs`, `cpio`, `elf`, `syscfg`, and `sysmap`.
The wrapper prefers `cargo +nightly fuzz` because cargo-fuzz needs sanitizer
flags that are not available on the pinned stable toolchain. Add GPT to the
same `rust/fuzz` package when a Rust GPT parser crate exists.

Generate parser and ABI coverage reports with:

```sh
make rust-coverage
```

The coverage wrapper uses cargo-llvm-cov when installed and writes LCOV plus
text summary output under `build/rust-coverage/`, which is ignored by git.

## CI Shape

The checked-in GitHub Actions workflow keeps the same tiers and publishes
GitHub Checks for CodeRabbit review context:

| Job | Command | Notes |
| --- | --- | --- |
| Toolchain image | `make container-toolchain-build` | Builds the Debian trixie image used by all Linux-reproducible gates. |
| Source build | `make container-source-build` | Runs `make prepare` when release components are missing, then builds NQ and LQ. |
| Installed artifact audit | `make container-audit-artifacts` | Audits ELF files staged into the boot CPIO and qrvfs `/usr` roots. |
| Fixtures and Rust quality | `make container-check` | Includes host tools, Rust quality, qrvfs Rust/C parity, and ELF relocation fixtures. |
| Rust deep warning gate | `make container-rust-deep` | Non-blocking #203 baseline for nextest/test fallback, docs, deny, Miri, fuzz, and coverage tools when available. |
| Parser fuzz smoke warning gate | `make container-rust-fuzz-smoke` | Non-blocking #203 bounded fuzz smoke baseline. |
| Rust ABI | `make container-rust-abi` | Requires C source build artifacts. |
| C analysis | `QSOE_INDEX_CLEAN=1 QSOE_INDEX_DB_FLAVOR=container make index-c-compile-db` and bounded `make tidy-c` | Rebuilds under Bear, then runs the curated clang-tidy pass against container paths. |
| Boot | `scripts/container-toolchain.sh run scripts/boot-smoke.sh -k lq -t 120` | Required before enabling any Rust service in an image. |
| CodeQL warning gate | `.github/workflows/codeql.yml` | Non-blocking #202 C/C++ static security scan for main and trusted pull-request contexts. |
| Dependency review warning gate | `.github/workflows/dependency-review.yml` | Non-blocking #202 PR dependency review for manifest and lockfile changes. |

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
