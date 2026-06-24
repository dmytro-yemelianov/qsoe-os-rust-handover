# QSOE Virtio Block Driver Behavior

This document specifies the current C `devb-virtio` behavior that
`devb-virtio-rs` must preserve before any Rust implementation is selected.
The C driver remains the default rollback path.

## Role

`quser/dev/virtio` provides `/sbin/devb-virtio`, the QSOE/L QEMU block
resource manager. It serves one raw whole-disk block node:

```text
/dev/vblk0
```

The disk contains a qrvfs image directly, without GPT partitioning. `fs-qrv`
mounts `/dev/vblk0` at `/usr`, where the on-disk sysinit, login path, test
binaries, credentials, and home skeleton live.

## Device Discovery

Discovery is specific to QEMU's RISC-V `virt` machine:

- Probe eight virtio-mmio slots.
- Slot base: `0x10001000`.
- Slot stride: `0x1000`.
- Slot register window size: `0x1000`.
- Map each candidate slot with `qsoe_mmap(..., MAP_PHYS | MAP_SHARED, ...)`.
- Accept the first slot whose registers match:
  - magic `0x74726976` (`"virt"`),
  - legacy version `1`,
  - device id `2` (`virtio-blk`).
- Unmap non-block slots before moving to the next slot.

If no block device is found, `devb-virtio` prints an error and exits with
status `1`.

## DMA Region

The driver allocates one physically contiguous DMA region with
`qsoe_alloc_phys` before device initialization.

Current layout:

| Region | Offset | Size | Purpose |
| --- | ---: | ---: | --- |
| page 0 | `0x0000` | 4096 | descriptor table and available ring |
| page 1 | `0x1000` | 4096 | used ring |
| page 2 | `0x2000` | 4096 | per-descriptor request headers and status bytes |
| page 3 | `0x3000` | 4096 | shared data bounce buffer |

Constants:

- queue depth: `8`.
- descriptor size: `16` bytes.
- maximum single transfer: `4096` bytes.
- logical sector size: `512` bytes.
- DMA region size: `4 * 4096` bytes.

The C driver keeps a separate non-DMA read staging buffer in `main.c`. Reads
DMA into the driver's shared data page, copy to that staging buffer, then copy
the requested byte slice into the resource-server reply buffer.

## Device Bring-Up

`virtio_blk_init` preserves the legacy virtio-mmio bring-up sequence:

1. Re-probe the mapped registers and fail with `-ENODEV` if they are not a
   legacy block device.
2. Reset `STATUS` to `0`.
3. Set `ACKNOWLEDGE`.
4. Set `DRIVER`.
5. Read device features, clear unsupported feature bits, and write the
   resulting set to `DRIVER_FEATURES`.
6. Set `FEATURES_OK`.
7. Set `DRIVER_OK`.
8. Write guest page size `4096`.
9. Select queue `0`.
10. Require `QUEUE_NUM_MAX >= 8`.
11. Set `QUEUE_NUM = 8`.
12. Zero the DMA region.
13. Write `QUEUE_PFN = dma_pa / 4096`.
14. Set driver pointers into the DMA region for descriptor, available, used,
    request, status, and data areas.
15. Mark all descriptors free.
16. Read the 64-bit capacity from device config offset `0x100`, in 512-byte
    sectors.

The current driver clears these feature bits before accepting the device:

- `VIRTIO_BLK_F_RO`
- `VIRTIO_BLK_F_SCSI`
- `VIRTIO_BLK_F_CONFIG_WCE`
- `VIRTIO_BLK_F_MQ`
- `VIRTIO_F_ANY_LAYOUT`
- `VIRTIO_RING_F_EVENT_IDX`
- `VIRTIO_RING_F_INDIRECT_DESC`

No interrupt handler is installed. Completion is polling-only.

## Request Lifecycle

`virtio_blk_rw` performs one synchronous request at a time:

1. Clamp zero-length requests to success.
2. Clamp requests larger than `4096` bytes to `4096`.
3. Allocate three free descriptors; return `-EBUSY` if unavailable.
4. Populate a `virtio_blk_req` header:
   - type `VIRTIO_BLK_T_IN` for reads,
   - type `VIRTIO_BLK_T_OUT` for writes,
   - sector set to the requested LBA.
5. Build a descriptor chain:
   - descriptor 0: request header, device-readable, `NEXT`.
   - descriptor 1: data buffer, `NEXT`, plus `WRITE` for reads.
   - descriptor 2: status byte, device-writable.
6. For writes, copy caller data into the shared DMA data page before publish.
7. Publish descriptor 0 into the available ring and increment `avail->idx`,
   with synchronization barriers before and after the index write.
8. Kick queue `0` through `QUEUE_NOTIFY`.
9. Poll until the used-ring index advances, yielding while waiting.
10. Acknowledge any pending interrupt-status bits with mask `0x3`.
11. Treat any non-zero device status byte as `-EIO`.
12. For successful reads, copy the shared DMA data page back to the caller.
13. Free the descriptor chain.

The resource-server `pull` method adapts byte-addressed reads to this sector
API:

- return `0` at or beyond device capacity.
- cap each read to `4096` bytes.
- compute the first and last 512-byte LBA covering the requested byte range.
- read whole covering sectors into the staging buffer.
- copy only the requested byte slice into the framework reply buffer.
- return the number of bytes copied.

Writes are not exposed through the resource-server provider today.

## Resource-Server Surface

`devb-virtio` publishes one provider:

```text
path: /dev/vblk0
mode: S_IFBLK | 0444
size: capacity_sectors * 512
```

The provider vtable uses `QSOE_PROVIDER_DEFAULTS` plus:

- `.pull = vblk_pull`

The defaults provide acquire, release, seek, and query behavior. Because
`.push` is unset, write-style operations are rejected by the resource-server
framework with `ENOSYS`.

Startup sequence:

1. Discover virtio-mmio block device.
2. Allocate DMA region.
3. Initialize the virtio block device and queue.
4. Initialize and listen on the `/dev/vblk0` provider.
5. Print readiness.
6. Call `procmgr_detach(0)` so init can continue.
7. Enter `qsoe_dispatch_run`.

The boot-smoke marker for readiness is:

```text
devb-virtio: /dev/vblk0 ready
```

## Mount Dependency

The boot cpio `/sbin/init` reads `mainfs=` from `/sys/cmdline`.

For QSOE/L, the expected command-line device is:

```text
mainfs=/dev/vblk0
```

When `mainfs` starts with `/dev/vblk`, init runs:

```sh
/sbin/devb-virtio
/sbin/fs-qrv "$mainfs" /usr
```

Both programs detach after their resource paths are ready, so the next init
step can rely on the path manager state.

`fs-qrv` opens the device, initializes qrvfs, publishes `/usr`, detaches, and
enters its dispatch loop. The expected boot marker is:

```text
fs-qrv: mounted qrvfs at /usr (dev=/dev/vblk0)
```

If `/usr/sbin/sysinit/level1.sh` exists after the mount, cpio init execs it.
That on-disk init then starts `/usr/sbin/getty`, which leads to the login
prompt. A missing or unmountable `/usr` falls back to the cpio rescue shell,
so the Rust driver acceptance path must preserve `/dev/vblk0`, the qrvfs mount,
and the login path.

## Image Contract

The umbrella `make virtio` target copies the generated qrvfs image directly to:

```text
build/virtio.img
```

There is no GPT container for the virtio path. The NVMe path writes the same
qrvfs image into GPT partition 8, but `devb-virtio` exposes the raw qrvfs image
as the whole block device.

## Rust Acceptance Notes

The first Rust `devb-virtio-rs` must keep these externally visible behaviors:

- discover the same QEMU virt legacy virtio-mmio block device slots.
- expose `/dev/vblk0` with read-only block-device attributes.
- preserve the current 512-byte sector and 4096-byte transfer limits unless
  the C driver changes first.
- use one queue and the same three-descriptor request shape.
- keep writes disabled through the resource-server surface.
- detach only after `/dev/vblk0` is registered and ready.
- allow `fs-qrv /dev/vblk0 /usr` to mount and the boot smoke to reach `login:`.

## Rust MMIO Wrapper

`rust/crates/qsoe-virtio` contains the first Rust wrapper for the legacy
virtio-mmio register block. Its scope is intentionally only the volatile
register boundary:

- `VirtioMmio` owns a non-null base pointer to one mapped 4 KiB register
  window.
- register offsets and identity/status/queue constants match
  `quser/dev/virtio/virtio_blk.h`.
- all volatile pointer reads and writes are contained inside `VirtioMmio`.
- the constructor is `unsafe` because the caller must prove the mapping is
  live, writable, register-sized, and outlives the wrapper.
- host tests use a plain `[u32; 0x1000 / 4]` backing array to cover probing,
  register reads/writes, feature masking, config reads, and interrupt
  acknowledgement without requiring QEMU.

Future Rust queue and driver code should use this crate instead of performing
raw pointer arithmetic at each call site.

## Rust Virtqueue Descriptor Model

`qsoe-virtio` also contains the initial Rust model for the legacy virtqueue
shapes used by the C driver:

- `VirtqDesc`, `VirtqAvail`, `VirtqUsedElem`, `VirtqUsed`, and `VirtioBlkReq`
  are `repr(C)` mirrors of the C structs.
- `DescriptorIndex` bounds descriptor ids to the current queue depth.
- `DescriptorAccess` distinguishes buffers the device may only read from
  buffers the device may write.
- `DescriptorOwner` distinguishes driver-owned descriptors from descriptors
  published to the device.
- `DescriptorModel` combines index, owner, access, address, length, and next
  pointer metadata and converts to the raw `VirtqDesc` ring entry.
- `DescriptorFreeList` mirrors the C driver's first-free descriptor map and
  allocates fixed-size host-testable chains.

Host tests cover the current three-descriptor request shape, descriptor
exhaustion without partial consumption, device-owned chain rejection, reclaim,
and descriptor reuse without touching hardware.

## Rust Opt-In Driver Artifact

`rust/bins/devb-virtio-rs` is the opt-in Rust driver binary. It is built as a
no-std staticlib and linked through the existing QSOE userland path with
`libressrv`:

```sh
make rust-virtio-link-smoke
```

The link smoke emits `build/rust/qsoe-devb-virtio-rs.elf` and runs
`scripts/audit-elf.sh --strict-qsoe-user` on it.

Selection stays explicit:

```sh
make virtio-artifact
QSOE_RUST_VIRTIO=1 make virtio-artifact
```

The default `QSOE_RUST_VIRTIO=0` stages the C `devb-virtio` artifact. The Rust
mode stages the audited Rust ELF at
`build/rust/selected/sbin/devb-virtio.elf`, ready for the next boot-smoke task
to place into an opt-in QSOE/L image.

## Rust Opt-In Boot Smoke

`scripts/rust-virtio-boot-smoke.sh` builds an opt-in QSOE/L image by replacing
only `sbin/devb-virtio` in a temporary boot CPIO:

```sh
make rust-virtio-boot-smoke
```

The smoke delegates to `scripts/boot-smoke.sh` with
`QSOE_BOOT_VIRTIO_PATTERN="[devb-virtio-rs] /dev/vblk0 ready"` and still
requires the common milestones:

- `[slogger] alive`.
- `[devb-virtio-rs] /dev/vblk0 ready`.
- `fs-qrv: mounted qrvfs at /usr`.
- `login:`.

Validated log:

```text
build/boot-smoke-lq-rust-virtio.log
```

## Rust File Access Smoke

`scripts/rust-virtio-file-smoke.sh` layers one more acceptance check on top of
the opt-in Rust virtio boot smoke:

```sh
make rust-virtio-file-smoke
```

The helper creates a temporary `quser/conf/sysinit/*.sh` fragment before boot.
The normal qrvfs image build stages `/usr/conf/sysinit` into the virtio disk,
and `/usr/sbin/sysinit/level1.sh` sources the fragment after `/usr` is mounted.
The fragment runs:

```sh
/bin/cat /usr/conf/passwd >/dev/null
```

Success is reported by this in-guest marker:

```text
rust-virtio-file-smoke: read /usr/conf/passwd ok
```

Validated log:

```text
build/boot-smoke-lq-rust-virtio-file.log
```
