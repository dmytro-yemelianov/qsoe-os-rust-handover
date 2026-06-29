# Task Manager `/proc` Pilot Selection

Captured: 2026-06-24 02:02 CEST.

The selected non-critical internal task-manager module was the portable
`tm_procfs` model:

```text
rust/crates/qsoe-tm-procfs
libtaskman/include/tm_procfs.h
```

The Rust provider targets only that portable model. It does not replace LQ's
process table, connection context handling, open/read dispatch, or any seL4
invocation code.

The C/Rust boundary, failure behavior, and rollback plan are specified in
`TASK_MANAGER_PROCFS_BOUNDARY.md`.

## Why This Module

`tm_procfs` owns a small read-only diagnostic model:

- resolve `/proc`, `/proc/<pid>`, and `/proc/<pid>/info`;
- format one `/proc/<pid>/info` text snapshot;
- walk root directory pid entries through a callback;
- emit the single per-pid `info` directory entry.

The module has no direct effect on initial process creation:

- `/sbin/init` lookup and launch happen through `main.c`, embedded CPIO, and
  `tm_spawn`, not through `tm_procfs`;
- `tm_procfs_init()` only stores two callbacks and returns `void`;
- process creation, pid allocation, TCB setup, address-space mapping, stdio cap
  setup, and `TCB_Resume` all remain in C paths outside this module;
- the LQ glue reads existing process records after they exist.

## Excluded From This Selection

These files stay C for the first pilot:

- `lq/taskman/path/procfs.c`: LQ-specific open/read/readdir glue and connection
  context handling.
- `lq/taskman/proc/process.c`: process table, pid allocation, lifecycle,
  teardown, and cap ownership.
- `lq/taskman/proc/spawn.c`: initial and later process creation.
- `lq/taskman/main.c`: boot registration and dispatch loop.
- `lq/taskman/qsoe/**`, `qsoe_invoke.h`, `sel4_syscalls.h`, and
  `sel4_types.h`: taskman-private syscall and seL4 invocation layer.

## Comparison Against Other Candidates

| Candidate | Reason not first |
| --- | --- |
| `tm_sysfs` | `/sys/cmdline` can influence init's mainfs path and early mount flow. |
| `tm_pathmgr` | Every open and device registration depends on path resolution. |
| `tm_cpio` | Embedded archive lookup is spawn-adjacent. |
| `tm_script` | Shebang parsing is pure, but it is called from `tm_spawn`. |
| `tm_elf` / `tm_reloc` | Directly part of loader and relocation behavior. |
| `rsrcdb` | Good later accounting candidate, but it is a service-facing allocation API. |
| `devnull` / `devzero` | Small, but they enter through taskman's IO dispatch and cap-backed fd flow. |

## Rust-Only Provider

`qsoe-tm-procfs` exports the existing `tm_procfs.h` ABI and is mandatory in
taskman after C provider retirement:

```text
QSOE_RUST_TM_PROCFS=1  -> Rust `qsoe-tm-procfs` is linked through qsoe-tm-providers
QSOE_RUST_TM_PROCFS=0  -> rejected; C tm_procfs is retired
```

NQ/LQ taskman link the selected provider through the shared
`qsoe-tm-providers` archive, built for `riscv64imac-unknown-none-elf` so it
matches taskman's soft-float ABI.

Multiple `QSOE_RUST_TM_*` selectors may be enabled together. The shared archive
owns the single no-std panic handler; individual provider crates remain `rlib`
crates that export the existing C ABI.

## Evidence

The Rust model is covered by `make check-tm-procfs-model`, which runs the
`qsoe-tm-procfs` host tests for:

- path resolution for `/proc`, `/proc/`, `/proc/<pid>`, `/proc/<pid>/`,
  `/proc/<pid>/info`, unknown pids, malformed pids, and unknown entries;
- info formatting for alive and zombie records;
- name truncation behavior at `TM_PROCFS_NAME_MAX`;
- root `readdir` cursor behavior over sorted callback results;
- per-pid directory `readdir` behavior for the single `info` entry;
- behavior when callbacks are unset or a pid disappears between operations.

The same tests can be run directly through:

```sh
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-procfs --features host-tests
```

Image-level validation stays simple for the retired provider:

- boot to the normal login milestone;
- run `make tm-procfs-evidence`, which audits the Rust provider archive,
  verifies that NQ/LQ taskman archives no longer contain `tm_procfs.o`, checks
  retired selector rejection, audits NQ/LQ taskman ELF flags/sections, and runs
  the Rust-only `/proc` smoke;
- verify existing process creation and boot markers are unchanged.

Trusted CI runs `make container-tm-procfs-evidence` on the configured
`[self-hosted, X64]` runner for same-repository PRs, pushes, and manual
dispatches. Trusted `main` CI run `28102250069` accepted the #103 evidence
before any separate Rust-default selection decision.

## Rust-Default RC Smoke

`scripts/tm-procfs-rc-smoke.sh` now validates the retired Rust-only image path:

```sh
make tm-procfs-rc-smoke
```

The retired path sets `QSOE_RUST_TM_PROCFS=1` and uses the existing `/proc`
smoke. `TM_PROCFS_RC_ROLLBACK=1` now fails fast because the C provider is
removed. See `TASK_MANAGER_PROCFS_RC.md` for the historical release-candidate
record and `TASK_MANAGER_PROCFS_RETIREMENT.md` for the removal record.

## Selection Result

`tm_procfs` is selected for the first task-manager Rust pilot because it is
bounded, read-only, callback-driven, and diagnostic. It avoids direct spawn,
capability, relocation, and loader paths while still exercising a real internal
task-manager model.
