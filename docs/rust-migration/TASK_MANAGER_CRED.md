# Task Manager Credential Policy Provider

Captured: 2026-06-30 CEST.

`tm_cred` is a bounded retired task-manager Rust provider. It covers only the
portable credential, cwd, and umask state model:

```text
libtaskman/include/tm_cred.h
rust/crates/qsoe-tm-cred
```

## Scope

The Rust provider exports the existing `tm_cred.h` C ABI:

```text
void tm_cred_init(tm_cred_state_t *s);
int tm_cred_chdir(tm_cred_state_t *s, const char *path, unsigned path_len);
int tm_cred_getcwd(const tm_cred_state_t *s, char *dst, unsigned cap,
                   unsigned *out_len);
int tm_cred_umask(tm_cred_state_t *s, int set, unsigned *out_old);
int tm_cred_set(tm_cred_state_t *s, unsigned ruid, unsigned euid,
                unsigned suid, unsigned rgid, unsigned egid,
                unsigned sgid);
int tm_cred_change_permitted(const struct _cred_info *cur,
                             unsigned ruid, unsigned euid, unsigned suid,
                             unsigned rgid, unsigned egid, unsigned sgid);
void tm_cred_self_info(const tm_cred_state_t *s,
                       struct _cred_info *out_cred);
```

It does not replace process-table lookup, IPC decoding, path validation against
real filesystem state, login policy, or any seL4 object manipulation. LQ and NQ
taskman callers still own their process records and pass `tm_cred_state_t`
pointers into the portable provider.

## Selector

Normal builds are Rust-only after C provider retirement:

```text
QSOE_RUST_TM_CRED=1  -> Rust `qsoe-tm-cred` is selected
QSOE_RUST_TM_CRED=0  -> rejected after C `tm_cred` retirement
```

`libtaskman/Makefile` excludes `cred.o` from `libtaskman.a`, and the NQ/LQ
taskman links add the shared provider archive:

```text
build/rust/tm-providers/libqsoe_tm_providers.a
```

The archive is built for `riscv64imac-unknown-none-elf` so it matches
taskman's soft-float ABI.

Multiple taskman Rust providers may be selected together. The shared
`qsoe-tm-providers` archive packages the selected provider crates behind one
no-std panic handler. Legacy targets such as `make rust-tm-cred-provider`
still produce the historical single-provider output path for focused evidence.

## Evidence

The Rust behavior model is covered by:

```sh
make check-tm-cred-model
```

That target runs the Rust crate host tests. The tests verify ABI layout,
initialization semantics, absolute cwd
updates, getcwd copy behavior without an added NUL, umask exchange/masking,
`TM_CRED_KEEP` field preservation, self-info snapshots, and root/non-root
credential-change policy.

The direct command is:

```sh
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-cred --features host-tests
```

The full RC evidence gate is:

```sh
make tm-cred-evidence
```

It runs Rust host tests, builds and audits the Rust staticlib, checks exported
symbols, verifies all archive members are RVC soft-float, links NQ and LQ
taskman with `cred.o` absent, verifies final taskman ELF `tm_cred_*` symbols,
and verifies retired selector rejection for `QSOE_RUST_TM_CRED=0`.

The focused runtime gate is:

```sh
make tm-cred-runtime-smoke
```

It boots QSOE/L with `QSOE_RUST_TM_CRED=1` and `QSOE_RUST_TM_PROCFS=1`, verifies
the selected `libtaskman.a` omits C `cred.o`, verifies the Rust provider archive
exports the `tm_cred_*` ABI, stages `/usr/bin/cred_probe` only into the smoke
qrvfs image, and runs it from sysinit. The helper checks initial root ids, umask
exchange, cwd round-trip through `/usr/conf`, held-id uid/gid transitions,
non-root `setuid(0)` rejection, and inherited ids/cwd/umask in a spawned child.

The retired compatibility gate is:

```sh
make tm-cred-rc-smoke
```

The gate validates NQ and LQ archive membership with `cred.o` absent and then
reuses the live runtime smoke. `TM_CRED_RC_ROLLBACK=1` now fails fast after
retirement.

## Current State

`tm_cred` is retired to Rust. `libtaskman/src/cred.c` and the old C host fixture
are removed, `QSOE_RUST_TM_CRED=0` fails fast, and the public
`libtaskman/include/tm_cred.h` ABI remains the taskman boundary. Historical RC
and rollback evidence lives in `TASK_MANAGER_CRED_RC.md`; retirement evidence
lives in `TASK_MANAGER_CRED_RETIREMENT.md`.
