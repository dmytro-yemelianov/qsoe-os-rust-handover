# Rust Migration Release Note Template

Captured: 2026-06-24 02:42 CEST.

Use this template for any release, release candidate, or migration PR that
changes a tracked component's implementation language, selector, default state,
or C retirement status. Keep every section present; write `None` where a field
does not apply.

## Copy Template

```md
## Rust Migration: <component>

Status: <C default | Rust opt-in | Rust default RC | Retired>
Release or build: <tag, SHA, image name, or RC identifier>

### Language Change

- Previous default implementation: <C | Rust | not installed>
- New default implementation: <C | Rust | not installed>
- Rust artifact or crate: <path/package>
- C implementation status: <default | rollback-only | removed>
- User-visible behavior changes: <None or summary>

### Rollback

- Rollback available: <yes | no>
- Rollback flag, artifact, or package: <name and value/path>
- Rollback command or procedure: `<command>`
- Rollback window: <until next RC | until release N | permanent>
- Rollback limitations: <None or summary>

### Test Evidence

- Host tests: `<command>` -> <pass/fail/not run>
- Rust quality gate: `<command>` -> <pass/fail/not run>
- Artifact audit: `<command>` -> <pass/fail/not run>
- Boot smoke: `<command>` -> <pass/fail/not run>
- Component or in-guest smoke: `<command>` -> <pass/fail/not run>
- CI or local-equivalent run: <link/log/path>

### Known Limitations

- Missing test coverage: <None or summary>
- Unsupported hardware or image modes: <None or summary>
- Behavior differences from C: <None or summary>
- Open follow-up issues: <None or links>

### Review Notes

- Unsafe review: <no new unsafe code | checklist summary/link>
- Data or on-disk format migration: <None or summary>
- Operator impact: <None or summary>
```

## Minimum Bar

Before a component is selected as Rust default, the release note must name the
rollback flag or artifact, link the boot/component smoke evidence, and list any
known behavior difference from the C default.

Before a C implementation is retired, the release note must name the
Rust-default release candidate that carried the component with C rollback still
available.
