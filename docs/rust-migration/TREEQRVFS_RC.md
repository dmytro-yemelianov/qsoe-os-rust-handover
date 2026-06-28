# `qrvfs-tree` Rust-Default Release Candidate

Captured: 2026-06-28 21:17 CEST.

This note records the host `treeqrvfs` inspector Rust-default
release-candidate path. It does not replace the C `mkfs-qrv` image writer, and
the existing C inspector remains available as the rollback implementation and
fixture oracle.

## Rust Migration: Host `treeqrvfs`

Status: Rust default RC.
Release or build: `qrvfs-tree-rc1`, introduced by the
`codex/treeqrvfs-rust-default-rc` branch.

Implementation-language change:

- Previous default implementation: C `host_tools/treeqrvfs.c`
- New RC default implementation: Rust `qrvfs-tree`
- Rust artifact or crate: `rust/crates/qsoe-qrvfs`, binary `qrvfs-tree`
- C implementation status: rollback-only for the selected `make tree` artifact;
  still present and still used as the fixture comparison oracle
- Image writer status: unchanged C `host_tools/mkfs-qrv.c`

## Scope

Only the read-only host inspector default changes. `make tree` now obtains
`build/treeqrvfs` through `scripts/treeqrvfs-artifact.sh`, which selects Rust by
default with `QSOE_RUST_TREEQRVFS=1`.

The image writer, qrvfs on-disk format, GPT tooling, and boot images are not
changed by this release candidate.

## Rollback

Rollback command:

```sh
make treeqrvfs-rc-rollback-smoke
```

Equivalent selector:

```sh
QSOE_RUST_TREEQRVFS=0 make tree
```

Rollback limitations: none known for the host fixture path. The rollback
artifact is compiled from the same C `host_tools/treeqrvfs.c` implementation as
the pre-RC path.

## Evidence

Required local evidence:

- Existing C fixture and oracle: `make check-qrvfs-fixture`
- Existing Rust/C byte-for-byte comparison: `make check-qrvfs-rust-fixture`
- Rust-default selected artifact smoke: `make treeqrvfs-rc-smoke`
- C rollback selected artifact smoke: `make treeqrvfs-rc-rollback-smoke`
- Rust host tests: `make rust-quality`

The RC smoke regenerates the qrvfs fixture, builds the selected
`build/treeqrvfs` artifact, runs it on the fixture image, and diffs the selected
output against the C oracle log.

## Known Limitations

- This is not a qrvfs writer migration. `mkfs-qrv` remains C.
- The C inspector remains the fixture oracle during the RC window.
- This does not retire `host_tools/treeqrvfs.c`; removal still requires the
  retirement checklist and a separate C-removal PR.

## Operator Impact

Use `make treeqrvfs-rc-smoke` to validate the Rust default host inspector path
and `make treeqrvfs-rc-rollback-smoke` to validate rollback. Use
`QSOE_RUST_TREEQRVFS=0 make tree` when the C inspector is required explicitly.
