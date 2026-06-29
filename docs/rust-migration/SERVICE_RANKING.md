# QSOE Userland Service Ranking

Captured: 2026-06-24 01:44 CEST.

Historical note: `pipe` was selected from this ranking, moved through a
Rust-default RC, and is now a retired C service. Keep the original scores as the
selection record.

This ranking supports Phase 8 service selection. It excludes components that
already have Rust pilots (`slogger`, `devb-virtio`) and excludes standalone
test helpers, which are tracked separately. Higher scores mean lower migration
risk for the next Rust service.

## Scoring

Each dimension is scored from 1 to 5:

- Size: 5 is smallest and easiest to review; 1 is large or broad.
- Dependencies: 5 is mostly libc; 1 has multiple QSOE or hardware libraries.
- ABI surface: 5 has no custom IPC; 1 owns broad driver, shell, or process
  behavior.
- Testability: 5 has deterministic host or simple QEMU coverage; 1 lacks a
  focused smoke path.
- Rollback: 5 can be switched back to C by selecting one binary; 1 is hard to
  isolate once changed.

## Measurements

LOC counts are direct C source lines in the component directory. ELF sizes are
from the current `quser/build` artifacts in this checkout.

| Candidate | Path | LOC | ELF bytes | Main dependencies |
| --- | --- | ---: | ---: | --- |
| `getty` | `quser/sbin/getty` | 251 | 21,392 | libc, console stdio, `posix_spawn` to `login` |
| `login` | `quser/sbin/login` | 250 | 21,552 | libc auth files, console stdio, `posix_spawn` to shell |
| `pipe` | `quser/sbin/pipe` | 385 | 21,952 | libc, taskman pipe minting contract, path manager |
| `devc-sersifive` | `quser/dev/sersifive` | 468 | 31,072 | UART MMIO, interrupt/channel path, path manager |
| `devc-ser8250` | `quser/dev/ser8250` | 516 | 33,800 | UART MMIO, interrupt/channel path, path manager |
| `fs-qrv` | `quser/fs/qrv` | 787 | 77,144 | `libressrv`, block-device reads, qrvfs metadata |
| `devb-nvme` | `quser/dev/nvme` | 1,366 | 155,616 | `libressrv`, `libgpt`, `libpci`, MMIO, interrupts |
| `pci-server` | `quser/sbin/pci-server` | 1,902 | 102,264 | `libpci`, DesignWare ATU/MSI, platform hardware |
| `qsh` | `quser/qsh` | 22,982 | 1,009,048 | broad libc/process/shell grammar and job-control surface |

## Ranking

| Rank | Candidate | Size | Deps | ABI | Test | Rollback | Total | Recommendation |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | `pipe` | 4 | 4 | 3 | 4 | 4 | 19 | Best next service: small, bounded resource manager, and useful for shell pipelines. |
| 2 | `getty` | 5 | 3 | 3 | 4 | 4 | 19 | Good login-path candidate after a focused console/login smoke exists. |
| 3 | `login` | 5 | 3 | 3 | 3 | 4 | 18 | Small, but auth and shell handoff need careful fixture coverage. |
| 4 | `fs-qrv` | 3 | 3 | 3 | 4 | 3 | 16 | Attractive after qrvfs parser reuse, but boot-critical mount behavior raises rollback risk. |
| 5 | `devc-sersifive` | 4 | 3 | 2 | 2 | 3 | 14 | Small enough, but hardware and interrupt coverage make it a later driver candidate. |
| 6 | `devc-ser8250` | 4 | 3 | 2 | 2 | 3 | 14 | Same shape as `devc-sersifive`; defer until console-driver smoke is stronger. |
| 7 | `pci-server` | 2 | 2 | 2 | 2 | 2 | 10 | Platform-critical and hardware-specific; not a near-term Rust service. |
| 8 | `qsh` | 1 | 1 | 1 | 3 | 3 | 9 | Keep as C until multiple smaller services have shipped in Rust. |
| 9 | `devb-nvme` | 2 | 1 | 1 | 2 | 2 | 8 | Defer; it combines storage, PCI, GPT, interrupts, and boot-critical behavior. |

## Notes

- `pipe` was selected as the second-service candidate and has since retired its
  C implementation.
- `getty` and `login` are small, but they sit directly on the user login path.
  They need a smoke that covers prompt, auth failure, auth success, and shell
  handoff before implementation.
- `fs-qrv` can reuse `qsoe-qrvfs`, but it should wait until the parser crate is
  used behind a resource-server boundary with fixture coverage.
- `devc-*`, `pci-server`, and `devb-nvme` need stronger hardware-specific
  smoke coverage before Rust implementation.
