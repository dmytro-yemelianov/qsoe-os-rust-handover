# Task Manager Path Registry Provider

Captured: 2026-06-30 CEST.

`tm_pathmgr` is a retired Rust-only provider for the portable task-manager path
namespace registry:

```text
rust/crates/qsoe-tm-pathmgr
libtaskman/include/tm_pathmgr.h
```

The previous C provider `libtaskman/src/pathmgr.c` is removed. The public C ABI
header remains because taskman path IO, spawn, and service-registration code
still call the `tm_pathmgr_*` symbols exported by Rust.

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
rules. The CPIO symlink expansion path still calls the `tm_cpio_find_file` ABI;
this provider does not own CPIO parsing.

It does not replace path IO dispatch, FD ownership, CPIOFS/PROCFS/SYSFS
serving, process creation, device-server registration policy, or any seL4
object manipulation. NQ and LQ taskman still run those layers in C.

## Selector

`tm_pathmgr` is mandatory after C provider retirement:

```text
QSOE_RUST_TM_PATHMGR=1  -> Rust `qsoe-tm-pathmgr` is linked
QSOE_RUST_TM_PATHMGR=0  -> rejected; C rollback is retired
```

NQ/LQ taskman builds omit C `pathmgr.o` and link the shared provider archive:

```text
build/rust/tm-providers/libqsoe_tm_providers.a
```

The archive is built for `riscv64imac-unknown-none-elf` so it matches
taskman's soft-float ABI. The shared `qsoe-tm-providers` archive packages all
selected taskman Rust providers behind one no-std panic handler. Legacy targets
such as `make rust-tm-pathmgr-provider` still produce the historical focused
archive path for evidence compatibility.

## Evidence

The Rust provider has host coverage through:

```sh
make check-tm-pathmgr-model
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-pathmgr --features host-tests
```

The retirement evidence gate is:

```sh
make tm-pathmgr-evidence
```

It runs the Rust host tests, builds and audits the Rust provider archive,
checks all exported `tm_pathmgr_*` symbols, verifies all archive members are
RVC soft-float, verifies NQ/LQ taskman links omit C `pathmgr.o`, and verifies
retired selector rejection for standalone `libtaskman`, NQ, LQ, and the Rust
provider builder.

The focused runtime and retired compatibility gates are:

```sh
make tm-pathmgr-runtime-smoke
make tm-pathmgr-rc-smoke
```

They boot QSOE/L with the Rust-only provider, verify C `pathmgr.o` is absent,
verify the shared Rust provider exports the ABI symbols, and exercise runtime
consumers: `/dev` PMDIR readdir, `/etc/passwd` via the cpio-root symlink,
`/dev/console` repath to `/dev/ser1`, helper registration under
`/dev/pathmgr_probe`, duplicate registration rejection, MsgSend through the
resolved external binding, and unregister-on-exit cleanup after the helper
exits.

## Rollback

No C rollback target remains.

- `QSOE_RUST_TM_PATHMGR=0` fails fast in taskman and provider-archive builds.
- `TM_PATHMGR_RC_ROLLBACK=1 scripts/tm-pathmgr-rc-smoke.sh` fails fast.
- Historical RC and rollback evidence is recorded in `TASK_MANAGER_PATHMGR_RC.md`.

## Current State

`tm_pathmgr` is retired to Rust. Normal NQ/LQ taskman builds use the Rust
provider through the shared taskman Rust provider archive while keeping the
existing path registry ABI and surrounding C taskman ownership model.
