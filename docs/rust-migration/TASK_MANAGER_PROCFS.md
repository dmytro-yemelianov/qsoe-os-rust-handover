# Task Manager `/proc` Pilot Selection

Captured: 2026-06-24 02:02 CEST.

The selected non-critical internal task-manager module is the portable
`tm_procfs` model:

```text
libtaskman/src/tm_procfs.c
libtaskman/include/tm_procfs.h
```

The first Rust pilot should target only that portable model. It should not
replace LQ's process table, connection context handling, open/read dispatch, or
any seL4 invocation code.

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

## Required Evidence Before Implementation

Before a Rust `tm_procfs` module is wired into taskman, add host tests covering:

- path resolution for `/proc`, `/proc/`, `/proc/<pid>`, `/proc/<pid>/`,
  `/proc/<pid>/info`, unknown pids, malformed pids, and unknown entries;
- info formatting for alive and zombie records;
- name truncation behavior at `TM_PROCFS_NAME_MAX`;
- root `readdir` cursor behavior over sorted callback results;
- per-pid directory `readdir` behavior for the single `info` entry;
- behavior when callbacks are unset or a pid disappears between operations.

Image-level validation should stay simple for the first integration:

- boot to the normal login milestone;
- run `make procfs-smoke`, which exercises `/proc` readdir and
  `/proc/1/info` reads before any Rust taskman wiring;
- verify existing process creation and boot markers are unchanged.

## Selection Result

`tm_procfs` is selected for the first task-manager Rust pilot because it is
bounded, read-only, callback-driven, and diagnostic. It avoids direct spawn,
capability, relocation, and loader paths while still exercising a real internal
task-manager model.
