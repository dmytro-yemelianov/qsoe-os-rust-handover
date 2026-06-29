# `slogger-rs` Rust-Default Release Candidate

Captured: 2026-06-24 14:20 CEST.

This note records the first `slogger` Rust-default release-candidate path. It
did not retire the C implementation at the time. It is now historical evidence:
the C service was retired later, and the current Rust-only image path is
documented in `SLOGGER_RETIREMENT.md`.

## Rust Migration: `slogger`

Status: Rust default RC.
Release or build: `slogger-rs-rc1`, introduced by the
`codex/slogger-rc-default` branch.

### Language Change

- Previous default implementation: C `/sbin/slogger`
- New RC default implementation: Rust `slogger-rs`
- Rust artifact or crate: `rust/bins/slogger-rs`, linked to
  `build/rust/qsoe-slogger-rs.elf`
- C implementation status: rollback-only for the RC image path; still present
  in tree and still used by non-RC normal builds
- User-visible behavior changes: none expected for `/dev/slog` clients

Known startup-log difference:

- C prints pid, chid, and ring-size details.
- Rust prints shorter startup markers:
  - `[slogger-rs] alive`
  - `[slogger-rs] /dev/slog registered`
  - `[slogger-rs] entering MsgReceive loop`

## Rollback

- Rollback available: yes
- Rollback flag: `QSOE_SLOGGER_RC_ROLLBACK=1`
- Rollback command:

```sh
make slogger-rc-rollback-smoke
```

Equivalent boot-only rollback drill:

```sh
QSOE_SLOGGER_RC_ROLLBACK=1 make slogger-rc-boot-smoke
```

Rollback window: still open until the C retirement gate in `RETIREMENT.md` is
satisfied and a separate removal PR is reviewed.

Rollback limitations: none known for the QSOE/L smoke paths. The rollback image
uses the same C `/sbin/slogger` artifact as the pre-RC path.

## Test Evidence

- Host tests: `make rust-quality`
- Artifact audit: `make rust-slogger-link-smoke`
- Rust-default RC boot smoke: `make slogger-rc-boot-smoke`
- Rust-default RC readback smoke: `make slogger-rc-readback-smoke`
- C rollback readback smoke: `make slogger-rc-rollback-smoke`
- CI or local-equivalent run: accepted on 2026-06-24 14:20 CEST with local
  QEMU evidence captured in `DEVLOG.md`
- Rust-default RC readback log:
  `build/slog-readback-smoke-lq-slogger-rc-rust-default-20260624-142035.log`
- C rollback readback log:
  `build/slog-readback-smoke-lq-slogger-rc-c-rollback-20260624-142039.log`

The readback smoke boots QSOE/L into the rescue shell, runs `/bin/sloginfo`,
and verifies a boot-time `pci-server:` slog entry is readable through
`/dev/slog`.

## Known Limitations

- No C source was removed by this RC. The later retirement is documented in
  `SLOGGER_RETIREMENT.md`.
- The RC covers QSOE/L QEMU readback behavior, not a full hardware release.
- The Rust startup text remains shorter than the C startup text as documented
  in `SLOGGER_BOOT_COMPARE.md`.
- C retirement is no longer blocked for `slogger`; this RC evidence was used by
  the later retirement PR. Other components still need their own #26 checklist
  exercise before C removal.

## Review Notes

- Unsafe review: no new Rust unsafe code in this RC target wiring.
- Data or on-disk format migration: none.
- Historical operator impact at RC time: `make slogger-rc-readback-smoke`
  validated the Rust default RC path and `make slogger-rc-rollback-smoke`
  validated rollback. After retirement, use `make slogger-rc-readback-smoke`
  only; rollback is intentionally rejected.
