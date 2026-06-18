# QSOE Roadmap — to the unified 1.0

QSOE is one QNX-style POSIX userspace running, byte-for-byte, on **two
interchangeable microkernels**: the formally-verified **seL4** (QSOE/L) and
the from-scratch LWKT-derived **Skimmer** (QSOE/N). The umbrella version
(this file) is *feature-themed*; it is distinct from the per-component
versions tracked in [`component.list`](component.list) (`lq`, `nq`, `libc`,
`quser`). Each umbrella release bundles a tested set of component versions.

**The 1.0 gate** is QNX-libc compatibility good enough to **recompile and
run unmodified QNX userland software** — source/recompile compatibility,
since there is no QNX RISC-V ABI to preserve. 1.0 bundles NQ 1.0, LQ 1.0,
quser 1.0, and libc 1.0.

This roadmap is the working plan, not a contract — milestones may shift as
the work reveals what's really next.

---

## 0.1 — First public release  ·  *foundation + login*

The two-kernel foundation as it stands, plus a real interactive login:

- Both kernels boot to a shell; shared dynamically-linked userspace
  (rtld + `libc.so` + qsh + drivers + utils); QNX-shape IPC, `Sync*`,
  signals-as-pulses; the shared regression suite.
- **Read-only `fs-qrv` filesystem** mounted at `/usr` (NVMe on the
  Unmatched, virtio-mmio under QEMU); spawn-from-fs; on-disk staged init.
- **getty + login** — interactive, multi-user login on both kernels.
  Exercising a real session path will surface gaps in LQ, NQ, and libc
  (terminal/tty handling, `setuid`, sessions, environment) — fixed here and
  reflected back into `component.list`.
- **Sources opened on GitLab**, Apache-2.0 throughout.

The shared test suite (/usr/bin/suite) is fully green on **both** kernels.
The remaining (from pre-0.1) per-kernel seam gaps are closed (priority model,
dup, readdir, spawn-by-name, …). This keeps the "one userspace, two kernels"
promise honest.

## 0.2 — Text-mode console on the GK208 ("Kepler")

A watchable on-device display, so the real-time audio test can be observed
on real hardware rather than over serial.

## 0.3 — First writable filesystem

qrvfs gains writes: `O_CREAT`/`O_TRUNC`, file create/unlink, `realpath` and
symlink resolution. The disk stops being a read-only delivery vehicle.

## 0.4 — Canonical Dual-Panel File Manager

The QSOE flagship application — a two-pane file manager — exercising the
writable filesystem and the userspace end to end.

## 0.5 — First `deva-hdmi` + real-time groundwork

The GK208 HDMI-audio function brought up as a device, with the
priority/IST/scheduling groundwork the hard-real-time path needs. First
step toward the north-star RT test.

## 0.6 — Comprehensive suites + audio RT package

Broaden conformance/syscall test coverage, and land the audio real-time
package (up to N hard-RT tasks on an N-CPU system).

## 0.7

To be defined

## 0.8 — Second hardware target + AIA

Bring up the SpaceMit K3 (RVA23-class) as a second board, and finish the
AIA interrupt architecture (IMSIC/APLIC) so MSI/MSI-X delivery works across
QEMU `virt`, the K3, and the Unmatched uniformly.

## 0.9 — QNX-libc compatibility push

Recompile and run a target set of QNX-source userland utilities, closing
the remaining libc gaps (except fork() of course). This is where
"QNX compatibility" becomes measured rather than aspirational.

## 1.0 — QSOE initial release

NQ 1.0 + LQ 1.0 + quser 1.0 + libc 1.0. QNX-libc compatibility good enough
to run many QNX user-space applications after recompilation, with minimal
modifications (fork -> posix_spawn).

---

### Threads that span milestones

- **Hard real-time / HDMI audio** — text-mode console → `deva-hdmi` → audio package
  play sequence builds toward the north-star: a 24-hour HDMI-audio capture on a
  GK208 under sustained multi-core load with   continuous NVMe/Ethernet IRQs.
- **Networking** (FLEET-inspired transparent distributed networking) is
  **post-1.0** — node-descriptor placeholders already thread through the
  IPC surface so it can land without an ABI break.
- **Both kernels, every milestone** — Skimmer and seL4 advance together;
  the discipline of keeping the shared userspace is maintained with every QSOE release.
