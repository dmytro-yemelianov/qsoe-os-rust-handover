# C Implementation Retirement Gate

Captured: 2026-06-24 01:56 CEST.

This document turns the Phase 8 retirement rule into an explicit gate. No C
implementation is approved for removal yet. The current Rust pilots remain
either opt-in artifacts or selected future work, and each existing C
implementation remains the rollback path until the release-candidate evidence
below exists.

## State Model

Every migrated component moves through these states:

| State | Meaning | C implementation |
| --- | --- | --- |
| C default | Normal images install and run the C artifact. | Required |
| Rust opt-in | A build flag can replace the artifact with Rust for focused tests. | Required rollback |
| Rust default RC | Release-candidate images default to Rust while a build flag or release artifact restores C. | Required rollback |
| Retired | The C artifact is removed from normal source and image paths. | Not required in current tree |

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

| Component | Rust state | Evidence present | Retirement status |
| --- | --- | --- | --- |
| `slogger` | Opt-in pilot | Behavior spec, Rust ring tests, link smoke, ELF audit, Rust boot comparison | Not retireable: missing readback smoke and Rust-default RC |
| `devb-virtio` | Opt-in pilot | Behavior spec, MMIO/queue tests, link smoke, ELF audit, Rust boot smoke, file access smoke | Not retireable: missing Rust-default RC |
| `pipe` | Selected future service | C behavior mini-spec and C registration smoke | Not retireable: no Rust implementation |
| `test_msgpass` | Selected future test helper | C helper contract and selection rationale | Not retireable: no Rust implementation |

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
- [ ] Release notes describe the language change and rollback window.
- [ ] The PR removes only the C implementation and stale C-specific build paths.
```

If any checklist item is missing, the C implementation stays in tree.
