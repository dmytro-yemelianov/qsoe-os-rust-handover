# Task Manager Path Registry Provider

Captured: 2026-06-29 CEST.

`tm_pathmgr` is a Rust opt-in provider for the portable task-manager path
namespace registry:

```text
libtaskman/src/pathmgr.c
libtaskman/include/tm_pathmgr.h
```

## Scope

The Rust provider exports the existing `tm_pathmgr.h` C ABI:

```text
void tm_pathmgr_init(void);
int tm_pathmgr_register(const char *path, const tm_pathmgr_obj_t *obj);
int tm_pathmgr_unregister_pid(pid_t pid);
int tm_pathmgr_resolve(const char *path, tm_pathmgr_obj_t *out,
                       unsigned *out_consumed_bytes);
int tm_pathmgr_repath(const char *path, const tm_pathmgr_obj_t *new_obj);
int tm_pathmgr_symlink(const char *link_path, const char *target_path);
int tm_pathmgr_expand_symlink_cpio(const uint8_t *cpio, uint64_t size,
                                   const char *path, char *out, unsigned cap);
int tm_pathmgr_expand_symlink(const char *path, char *out, unsigned out_cap);
int tm_pathmgr_child_at(const char *path, unsigned idx, char *name_out,
                        unsigned name_cap, unsigned *out_namelen);
```

It preserves the C provider's fixed 64-node bump pool, per-component name and
target limits, longest-prefix resolution, PMDIR missing-child behavior,
external-only unregister, newest-first child ordering, and one-hop symlink
rules. The CPIO symlink expansion path still calls the existing C
`tm_cpio_find_file` ABI; this provider does not reimplement CPIO parsing.

It does not replace path IO dispatch, FD ownership, CPIOFS/PROCFS/SYSFS
serving, process creation, device-server registration policy, or any seL4
object manipulation. NQ and LQ taskman still run those layers in C.

## Selector

Normal taskman builds remain C-default:

```text
QSOE_RUST_TM_PATHMGR=0  -> C `libtaskman/src/pathmgr.c` remains selected
QSOE_RUST_TM_PATHMGR=1  -> Rust `qsoe-tm-pathmgr` staticlib is linked instead
```

When Rust is selected, `libtaskman/Makefile` excludes `pathmgr.o` from
`libtaskman.a`, and the NQ/LQ taskman links add:

```text
build/rust/tm-pathmgr/libqsoe_tm_pathmgr.a
```

The archive is built for `riscv64imac-unknown-none-elf` so it matches
taskman's soft-float ABI.

Current taskman Rust providers are mutually exclusive. Do not set more than one
`QSOE_RUST_TM_*` taskman provider selector until the providers are packaged into
one shared staticlib.

## Evidence

The C behavior baseline is covered by:

```sh
make check-tm-pathmgr-model
```

The Rust provider has equivalent host coverage:

```sh
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-pathmgr --features host-tests
```

The full opt-in evidence gate is:

```sh
make tm-pathmgr-evidence
```

It runs the C fixture, Rust host tests, builds and audits the Rust staticlib,
checks all exported `tm_pathmgr_*` symbols, verifies all archive members are
RVC soft-float, and links both NQ and LQ taskman in C rollback and
Rust-selected modes. The gate also verifies `pathmgr.o` is present for
`QSOE_RUST_TM_PATHMGR=0` and absent for `QSOE_RUST_TM_PATHMGR=1`.

## Current State

`tm_pathmgr` is Rust opt-in only. It is not a Rust-default release candidate
and has no C retirement approval. Keep `libtaskman/src/pathmgr.c` as the
rollback implementation until open/device-registration runtime coverage, the
global retirement checklist, and a separate removal PR are satisfied.
