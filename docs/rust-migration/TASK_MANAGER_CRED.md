# Task Manager Credential Policy Provider

Captured: 2026-06-29 CEST.

`tm_cred` is the second bounded task-manager Rust provider after `tm_procfs`.
It covers only the portable credential, cwd, and umask state model:

```text
libtaskman/src/cred.c
libtaskman/include/tm_cred.h
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

Normal builds remain C-default:

```text
QSOE_RUST_TM_CRED=0  -> C `libtaskman/src/cred.c` remains selected
QSOE_RUST_TM_CRED=1  -> Rust `qsoe-tm-cred` staticlib is linked instead
```

When Rust is selected, `libtaskman/Makefile` excludes `cred.o` from
`libtaskman.a`, and the NQ/LQ taskman links add the shared provider archive:

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

The C behavior baseline is covered by:

```sh
make check-tm-cred-model
```

That fixture verifies ABI layout, initialization semantics, absolute cwd
updates, getcwd copy behavior without an added NUL, umask exchange/masking,
`TM_CRED_KEEP` field preservation, self-info snapshots, and root/non-root
credential-change policy.

The Rust provider has equivalent host coverage:

```sh
cargo test --manifest-path rust/Cargo.toml -p qsoe-tm-cred --features host-tests
```

The full opt-in evidence gate is:

```sh
make tm-cred-evidence
```

It runs the C fixture, Rust host tests, builds and audits the Rust staticlib,
checks exported symbols, verifies all archive members are RVC soft-float, and
links both NQ and LQ taskman in C rollback and Rust-selected modes. The gate
also verifies `cred.o` is present for `QSOE_RUST_TM_CRED=0` and absent for
`QSOE_RUST_TM_CRED=1`.

## Current State

`tm_cred` is Rust opt-in only. It is not a Rust-default release candidate and
has no C retirement approval. Keep `libtaskman/src/cred.c` as the rollback
implementation until the global retirement checklist and a separate removal PR
are satisfied.
