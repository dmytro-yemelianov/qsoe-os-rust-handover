# Task Manager `/proc` C/Rust Boundary

Captured: 2026-06-24 02:03 CEST.

This boundary design covers the selected portable `tm_procfs` pilot. The
current C implementation remains the default. A future Rust implementation must
be a drop-in provider of the existing `tm_procfs.h` ABI and must not change LQ
taskman process creation, capability handling, relocation, or loader code.

## Boundary Surface

The public C header stays authoritative:

```text
libtaskman/include/tm_procfs.h
```

A Rust pilot may replace only these symbols:

```c
void tm_procfs_init(tm_procfs_get_fn get, tm_procfs_next_fn next);
int tm_procfs_resolve(const char *path, int *pid_out);
int tm_procfs_path_exists(const char *path);
unsigned tm_procfs_info(int pid, char *dst, unsigned cap);
int tm_procfs_readdir_root(unsigned long *cursor, char *name_out,
                           unsigned *namelen_out, int *d_type_out);
int tm_procfs_readdir_piddir(unsigned long cursor, char *name_out,
                             unsigned *namelen_out, int *d_type_out);
```

The Rust side must export those exact C ABI names with `extern "C"` and keep
the C header unchanged for all C callers.

## Data Ownership

- `tm_procfs_init()` receives two C callback pointers and stores them for later
  calls. It does not own the process table.
- The callbacks write a temporary `struct tm_procfs_proc` record supplied by
  the procfs model.
- `path`, `dst`, `name_out`, `namelen_out`, `d_type_out`, and `pid_out` are
  caller-owned C pointers.
- `path` and required output pointers must be non-null, matching the current C
  caller contract. `pid_out` remains optional where the C ABI allows it.
- The Rust implementation may read valid C strings until the first NUL byte
  only.
- Output writes must stay within the current C contract:
  - `dst` is valid for `cap` bytes in `tm_procfs_info`;
  - `name_out` is assumed large enough for decimal pid names or `info`, as the
    current C ABI has no explicit name buffer cap;
  - `namelen_out`, `d_type_out`, and optional `pid_out` receive scalar values.
- No heap allocation is allowed. All temporary state must be fixed-size stack
  or static state matching the current C behavior.

## Failure Behavior

The Rust implementation must preserve current return conventions:

| Function | Failure or empty condition | Required result |
| --- | --- | --- |
| `tm_procfs_init` | Null callback pointer | Store exactly what was provided; later calls handle missing callbacks. |
| `tm_procfs_resolve` | Malformed path, path outside `/proc`, malformed pid, pid overflow, unknown pid, unknown entry, missing `get` callback | Return `0`. |
| `tm_procfs_path_exists` | `tm_procfs_resolve` returns `0` | Return `0`. |
| `tm_procfs_info` | Missing `get` callback, `cap < TM_PROCFS_INFO_MAX`, unknown pid | Return `0`. |
| `tm_procfs_readdir_root` | Missing `next` callback or callback returns `<= 0` | Return `0`. |
| `tm_procfs_readdir_piddir` | Cursor is `>= 1` | Return `0`. |

On success:

- `tm_procfs_resolve` returns `1` for `/proc`, `2` for `/proc/<pid>`, and `3`
  for `/proc/<pid>/info`.
- `tm_procfs_info` returns the byte count of the rendered text without a
  trailing NUL on the wire.
- `tm_procfs_readdir_root` returns `1`, writes the decimal pid name, writes
  `TM_PROCFS_DT_DIR`, and advances `*cursor` to `pid + 1`.
- `tm_procfs_readdir_piddir` returns `1`, writes `info`, writes length `4`, and
  writes `TM_PROCFS_DT_REG`.

The Rust module must not panic across the C boundary. Any unexpected invalid
pointer precondition remains an unsafe caller contract, matching C, but all
documented malformed inputs must use the return values above.

## Current Build Status

The implementation now uses Rust as the only taskman provider:

```text
QSOE_RUST_TM_PROCFS=1  -> build and link the Rust tm_procfs provider
QSOE_RUST_TM_PROCFS=0  -> rejected; C tm_procfs is retired
```

The Rust artifact lives under the existing Rust workspace as `qsoe-tm-procfs`,
with a `no_std`, `panic = "abort"` crate and no allocator. The NQ and LQ
taskman builds link it through the shared `qsoe-tm-providers` archive.

Rollback is closed for this provider:

- `libtaskman/src/tm_procfs.c` is removed;
- `QSOE_RUST_TM_PROCFS=0` fails fast;
- the historical RC rollback evidence is recorded in
  `TASK_MANAGER_PROCFS_RC.md`, and the removal record is
  `TASK_MANAGER_PROCFS_RETIREMENT.md`.

## Validation

The retired Rust provider remains covered by:

- Rust host tests for path resolution, info formatting, and readdir behavior;
- the Rust crate builds for host tests and the taskman soft-float no-std target;
- the selected taskman artifact passes the existing ELF audit expectations for
  taskman;
- boot smoke reaches the normal login milestone;
- `make tm-procfs-evidence` audits the Rust provider archive, verifies that
  NQ/LQ taskman archives contain no `tm_procfs.o`, checks retired selector
  rejection, checks NQ/LQ taskman ELF flags/sections, and runs the Rust-only
  `/proc` smoke;
- `make container-tm-procfs-evidence` passes on the configured trusted Linux
  runner for same-repository PRs, pushes, and manual dispatches.

## Boundary Review Result

The boundary is acceptable for the first retired task-manager provider because
the Rust module preserves a stable C ABI, holds only callback pointers and
fixed formatting logic, and leaves spawn, cap, relocation, loader, and LQ
dispatch code in C.
