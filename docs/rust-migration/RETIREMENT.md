# C Implementation Retirement Gate

Captured: 2026-06-29 CEST.

This document turns the Phase 8 retirement rule into an explicit gate. The
first removal was the in-guest test helper `test_msgpass`, which had a
Rust-default release-candidate path and C rollback drill before its retirement
PR removed the C helper. The second removal is the production `/sbin/slogger`
service after its own Rust-default release-candidate evidence. The third
removal is the production `/sbin/pipe` service after its Rust-default data-path
RC. The fourth removal is the production `/sbin/devb-virtio` block driver after
its Rust-default file-read RC. All remaining Rust pilots stay either opt-in or
Rust-default RC paths, and each non-retired C implementation remains the
rollback path until the release-candidate evidence below exists.

## State Model

Every migrated component moves through these states:

| State | Meaning | C implementation |
| --- | --- | --- |
| C default | Normal images install and run the C artifact. | Required |
| Rust opt-in | A build flag can replace the artifact with Rust for focused tests. | Required rollback |
| Rust default RC | Release-candidate images default to Rust while a build flag or release artifact restores C. | Required rollback |
| Retired | The C artifact is removed from normal source and image paths. | Removed for that component |

A component cannot enter `Retired` directly from `Rust opt-in`. It must first
ship through at least one release candidate with Rust selected by default and a
documented C rollback path.

## Mandatory Evidence

A C removal PR must be separate from the PR that flips the default to Rust, and
it must include evidence for all of these items:

- C behavior specification and known Rust differences.
- Host tests or fixtures for pure logic and parser/state behavior.
- QSOE target link output for the Rust artifact.
- Strict ELF audit covering type, machine, interpreter, relocations, TLS,
  unwind metadata, and unsupported runtime references.
- QEMU boot smoke for the image variant that uses the component.
- Targeted in-guest smoke or suite coverage for the component behavior.
- CI or local-equivalent workflow evidence for the same commands.
- One release-candidate cycle where Rust is the default and C rollback remains
  available.
- Rollback drill showing the exact build flag, artifact selection, or release
  package that restores the C implementation.
- Release notes naming the implementation-language change and rollback window.

## Current Component Status

The live status matrix is `STATUS.md`. It records C default, Rust opt-in, Rust
default, and retired status for every tracked migration component. At this
capture, `test_msgpass`, `slogger`, `pipe`, and `devb-virtio` are the tracked
components in `Retired` status. `test_msgpass` is the first retired helper;
`slogger`, `pipe`, and `devb-virtio` are retired production paths. `tm_procfs`
is the first retired task-manager provider. Remaining production services and
task-manager providers still require their own separate removal PRs after RC
evidence and rollback drills.

## Retired Components

| Component | Retirement note | Prior RC evidence | Current rollback |
| --- | --- | --- | --- |
| `test_msgpass` | `TEST_MSGPASS_RETIREMENT.md` | `TEST_MSGPASS_RC.md`, `make test-msgpass-rc-smoke`, previous `make test-msgpass-rc-rollback-smoke` evidence | No C rollback target remains; the retired helper is Rust-only in test images. |
| `slogger` | `SLOGGER_RETIREMENT.md` | `SLOGGER_RC.md`, `make slogger-rc-readback-smoke`, previous `make slogger-rc-rollback-smoke` evidence | No C rollback target remains; Rust `slogger-rs` is staged as `/sbin/slogger` in NQ/LQ images. |
| `pipe` | `PIPE_RETIREMENT.md` | `PIPE_RC.md`, `make pipe-rc-data-smoke`, previous `make pipe-rc-rollback-smoke` evidence | No C rollback target remains; Rust `pipe-rs` is staged as `/sbin/pipe` in NQ/LQ images. |
| `devb-virtio` | `VIRTIO_RETIREMENT.md` | `VIRTIO_RC.md`, `make virtio-rc-file-smoke`, previous `make virtio-rc-rollback-smoke` evidence | No C rollback target remains; Rust `devb-virtio-rs` is staged as `/sbin/devb-virtio` in NQ/LQ images. |
| `tm_procfs` | `TASK_MANAGER_PROCFS_RETIREMENT.md` | `TASK_MANAGER_PROCFS_RC.md`, `make tm-procfs-rc-smoke`, previous `make tm-procfs-rc-rollback-smoke` evidence | No C rollback target remains; Rust `qsoe-tm-procfs` is mandatory in taskman through the shared provider archive. |

## Removal PR Checklist

Use this checklist when a future component is eligible for removal:

```text
- [ ] Component is in Rust-default RC state.
- [ ] RC tag/build identifier is recorded.
- [ ] C rollback flag, artifact, or package was available through the RC.
- [ ] Rollback drill command and output are linked.
- [ ] C behavior spec and Rust differences are linked.
- [ ] Rust host tests and in-guest smokes are linked.
- [ ] Strict ELF audit output is linked.
- [ ] Release notes use `RELEASE_NOTE_TEMPLATE.md` and describe the language
      change and rollback window.
- [ ] The PR removes only the C implementation and stale C-specific build paths.
```

If any checklist item is missing, the C implementation stays in tree.
