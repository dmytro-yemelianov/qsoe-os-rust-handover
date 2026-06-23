# QSOE C Source Indexing Workflow

This document covers C-side navigation and analysis for the QSOE umbrella tree.
Rust workflow details live in `WORKFLOW.md`.

## Goals

- Fast source navigation for day-to-day reading and refactoring.
- Higher-quality clangd/clang-tidy diagnostics when a compile database exists.
- Explicit handling for variant-specific builds and container path rewriting.
- Opt-in indexing for large third-party trees such as seL4.

## Tool Layers

| Layer | Command | Main Use | Tradeoff |
| --- | --- | --- | --- |
| File list | `make index-c-files` | Auditable list of C/ASM files selected for indexing. | Cheapest; not semantic. |
| Universal Ctags | `make index-c-tags` | Fast symbol jumps in Vim/Emacs and many editors. | Lexical, not compiler-accurate. |
| cscope | `make index-c-cscope` | Callers, callees, references, text navigation. | C-oriented and fast, but not type-aware. |
| GNU Global | `make index-c-global` | Cross-reference database usable by many tools. | More complete than tags for some queries, still not clang. |
| clangd DB | `make container-index-c-compile-db` | Compiler-aware navigation, diagnostics, and clang-tidy. | Requires an actual build capture. |
| clang-tidy | `make tidy-c` | Bounded compiler-aware static analysis over the active DB. | Noisy by nature; starts with a small file limit. |

The combined static index is:

```sh
make container-index-c-static
```

The generated output is under:

```text
build/index/c/
```

## Indexed Scope

Default indexed roots are QSOE-owned code:

```text
boot common host_tools libc libtaskman lq nq quser
```

Generated build directories are excluded. seL4 is intentionally opt-in because
it is large and mostly third-party for this migration planning work:

```sh
QSOE_INDEX_SEL4=1 make container-index-c-static
```

Use `QSOE_INDEX_ROOTS` to narrow or broaden a run:

```sh
QSOE_INDEX_ROOTS="libc quser/sbin/slogger quser/ressrv" make container-index-c-static
```

## clangd Setup

The checked-in `.clangd` points clangd at:

```text
build/index/c/compile_commands.json
```

Generate that file from the Debian toolchain container:

```sh
make container-index-c-compile-db
```

Bear only captures commands that execute. If the tree is already fully built,
the resulting database can be empty. For a complete capture:

```sh
QSOE_INDEX_CLEAN=1 make container-index-c-compile-db
```

For a focused refresh:

```sh
scripts/container-toolchain.sh run scripts/c-index.sh compile-db make nq/build/libc/libc.so
```

## Host And Container Paths

Inside the container the repo path is:

```text
/work/qsoe/os
```

On the macOS host it is currently:

```text
/Users/dmytro/Documents/github/qsoe/os
```

`container-index-c-compile-db` passes `QSOE_HOST_ROOT` into the container, so
the default compile database is rewritten for the host editor:

```text
build/index/c/compile_commands.json
build/index/c/compile_commands.host.json
```

The original container-path database is kept as:

```text
build/index/c/compile_commands.container.json
```

`make container-tidy-c` prefers that container-path database when it exists, so
clang-tidy runs against paths visible inside the Debian toolchain container.

For a devcontainer or container-local clangd, request container paths:

```sh
QSOE_INDEX_DB_FLAVOR=container make container-index-c-compile-db
```

## Quality, Speed, Completeness

Use the static index for speed:

```sh
make container-index-c-static
```

Use a compile database for quality:

```sh
make container-index-c-compile-db
```

Use a clean Bear capture for completeness:

```sh
QSOE_INDEX_CLEAN=1 make container-index-c-compile-db
```

Keep variant context explicit. NQ, LQ, libc, and quser can compile shared files
with different defines and include paths. Do not merge unrelated compile
databases blindly once the project grows variant-specific DBs; prefer one active
database per workflow or preserve named databases under `build/index/c/`.

## clang-tidy

The bounded clang-tidy wrapper reads:

```text
build/index/c/compile_commands.json
```

Run the default bounded pass:

```sh
make tidy-c
```

The default limit is intentionally small. Expand it explicitly:

```sh
QSOE_TIDY_LIMIT=100 make tidy-c
scripts/c-tidy.sh --all
```

Analyze a focused source set:

```sh
scripts/c-tidy.sh libtaskman/src/pathmgr.c quser/sbin/slogger/main.c
```

The checked-in `.clang-tidy` records the initial checker policy:

- `clang-analyzer-*`;
- `bugprone-*`;
- `performance-*`;
- `portability-restrict-system-includes`;
- disabled high-noise platform families and identifier-style checks.

The wrapper excludes generated `build/` output and third-party
`sel4-bootstrap/` entries by default. Use `QSOE_TIDY_ROOTS` to narrow or expand
QSOE-owned source roots:

```sh
QSOE_TIDY_ROOTS="libtaskman quser/sbin/slogger" make tidy-c
```

Any future suppressions or disabled checks should be recorded in `.clang-tidy`
or this document, not hidden in editor-local settings.

## Analysis Follow-Up

The next useful quality layer is to promote recurring clang-tidy findings into
targeted fixes or documented suppressions once the bounded pass has enough
signal.
