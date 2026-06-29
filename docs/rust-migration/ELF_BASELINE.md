# QSOE C Userland ELF Baseline

Captured: 2026-06-29 18:45 CEST.

This baseline records representative C userland ELF properties for comparison
with future Rust artifacts. It is not a complete release inventory; it focuses
on binaries relevant to early migration work and smoke coverage.

Selected artifacts:

- `devb-virtio`: later driver pilot.
- `fs-qrv`: filesystem server and parser-heavy behavior.
- `qsh`: large shell baseline and high-relocation example.
- `login`: on-disk login path.
- `test_syncspace`, `suite`: in-guest test helpers. The former C
  `test_msgpass` helper is retired and no longer part of the current C
  baseline set.
- The former C `slogger` service is also retired and no longer part of the
  current C baseline set.

Regenerate the compact table from a built tree:

```sh
make container-elf-baseline
```

Regenerate full raw audit output:

```sh
scripts/container-toolchain.sh run \
  scripts/capture-elf-baseline.sh --raw-dir build/elf-baseline
```

The raw audit output is generated under `build/elf-baseline/`, which is ignored
by git. The checked-in table below is the reviewable baseline summary.

## Summary

| Artifact | Interpreter | Needed | Relocations | Undefined | TLS | Unwind |
| --- | --- | --- | --- | ---: | --- | --- |
| `quser/build/dev/virtio/devb-virtio.elf` | `/lib/ld-qsoe.so.1` | `libc.so` | `R_RISCV_64=1,R_RISCV_JUMP_SLOT=19` | 42 | no | yes |
| `quser/build/fs/qrv/fs-qrv.elf` | `/lib/ld-qsoe.so.1` | `libc.so` | `R_RISCV_64=1,R_RISCV_JUMP_SLOT=25` | 54 | no | yes |
| `quser/build/qsh/qsh.elf` | `/lib/ld-qsoe.so.1` | `libc.so` | `R_RISCV_64=186,R_RISCV_JUMP_SLOT=66` | 138 | no | yes |
| `quser/build/sbin/login/login.elf` | `/lib/ld-qsoe.so.1` | `libc.so` | `R_RISCV_64=3,R_RISCV_JUMP_SLOT=29` | 68 | no | yes |
| `quser/build/test/syncspace/test_syncspace.elf` | `/lib/ld-qsoe.so.1` | `libc.so` | `R_RISCV_JUMP_SLOT=9` | 20 | no | yes |
| `quser/build/test/suite/suite.elf` | `/lib/ld-qsoe.so.1` | `libc.so` | `R_RISCV_JUMP_SLOT=66` | 134 | no | yes |

## Observations

- All selected C userland binaries are RISC-V ET_EXEC artifacts with
  interpreter `/lib/ld-qsoe.so.1`.
- All selected binaries depend on `libc.so`.
- Relocation types stay within the current QSOE userland baseline:
  `R_RISCV_64` and `R_RISCV_JUMP_SLOT`.
- No selected C binary uses TLS sections.
- All selected C binaries contain unwind-related sections, typically
  `.eh_frame_hdr` and `.eh_frame`.

## Rust Comparison Rule

Current C binaries having unwind sections does not relax the first Rust gate.
Initial Rust userland artifacts must still avoid TLS and unwind sections unless
the loader/runtime support is explicitly reviewed and accepted.
