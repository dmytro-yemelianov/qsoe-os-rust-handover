#![no_std]

use core::cell::UnsafeCell;
use core::ffi::{c_char, c_int, c_void};
use core::mem::size_of;
use core::panic::PanicInfo;
use core::ptr::{self, read_volatile, write_volatile};
use core::sync::atomic::{fence, Ordering};

use qsoe_ressrv::{
    qsoe_default_acquire, qsoe_default_adjust, qsoe_default_query, qsoe_default_release,
    qsoe_default_seek, Handle, OffT, Provider, ProviderVtable, SizeT, SsizeT, EBUSY, EINVAL, EIO,
    ENODEV, TM_S_IFBLK,
};
use qsoe_virtio::{
    accepted_block_features, DescriptorAccess, DescriptorFreeList, DescriptorIndex,
    DescriptorModel, VirtioBlkReq, VirtioMmio, VirtqAvail, VirtqDesc, VirtqUsed, GUEST_PAGE_SIZE,
    STATUS_ACKNOWLEDGE, STATUS_DRIVER, STATUS_DRIVER_OK, STATUS_FEATURES_OK,
    VIRTIO_BLK_SECTOR_SIZE, VIRTIO_DATA_BYTES, VIRTIO_DMA_SIZE, VIRTIO_OFF_DATA, VIRTIO_OFF_OPS,
    VIRTIO_OFF_USED, VIRTQ_NUM,
};

const VBLK_PATH: &[u8] = b"/dev/vblk0\0";
const VIRTIO_MMIO_BASE: u64 = 0x1000_1000;
const VIRTIO_MMIO_STRIDE: u64 = 0x1000;
const VIRTIO_MMIO_COUNT: u64 = 8;
const VIRTIO_REG_BYTES: usize = 0x1000;
const PROT_READ_WRITE: c_int = 1 | 2;
const MAP_SHARED: c_int = 0x01;
const MAP_PHYS: c_int = 0x10000;
const INTERRUPT_ACK_MASK: u32 = 0x3;
const MAP_FAILED: isize = -1;

struct ProviderCell(UnsafeCell<Provider>);

// SAFETY: `devb-virtio-rs` is a single-threaded resource-server pilot. The
// provider is initialized once before the dispatch loop owns it.
unsafe impl Sync for ProviderCell {}

impl ProviderCell {
    const fn new() -> Self {
        Self(UnsafeCell::new(Provider::zeroed()))
    }

    fn get(&self) -> *mut Provider {
        self.0.get()
    }
}

struct DeviceCell(UnsafeCell<Option<VirtioBlockDevice>>);

// SAFETY: the QSOE resource-server dispatch loop is single-threaded here, and
// all device access goes through the one published provider.
unsafe impl Sync for DeviceCell {}

impl DeviceCell {
    const fn new() -> Self {
        Self(UnsafeCell::new(None))
    }

    fn set(&self, device: VirtioBlockDevice) {
        // SAFETY: initialization runs before the provider is published, so no
        // request path can observe or mutate this slot yet.
        unsafe { *self.0.get() = Some(device) };
    }

    fn get(&self) -> *mut Option<VirtioBlockDevice> {
        self.0.get()
    }
}

static PROVIDER: ProviderCell = ProviderCell::new();
static DEVICE: DeviceCell = DeviceCell::new();

static VBLK_VTABLE: ProviderVtable = ProviderVtable {
    acquire: Some(qsoe_default_acquire),
    release: Some(qsoe_default_release),
    pull: Some(vblk_pull),
    push: None,
    seek: Some(qsoe_default_seek),
    query: Some(qsoe_default_query),
    adjust: Some(qsoe_default_adjust),
    control: None,
    ready: None,
    service: None,
    cancel: None,
    lookup: None,
    list: None,
    make: None,
    unlink: None,
    dup: None,
};

struct VirtioBlockDevice {
    mmio: VirtioMmio,
    dma_pa: u64,
    desc: *mut VirtqDesc,
    avail: *mut VirtqAvail,
    used: *mut VirtqUsed,
    ops: *mut VirtioBlkReq,
    status: *mut u8,
    databuf: *mut u8,
    free: DescriptorFreeList,
    used_idx: u16,
    capacity_sectors: u64,
    bounce: [u8; VIRTIO_DATA_BYTES],
}

impl VirtioBlockDevice {
    fn init(mmio: VirtioMmio, dma_va: *mut u8, dma_pa: u64) -> Result<Self, c_int> {
        if !mmio.is_legacy_block_device() {
            return Err(ENODEV);
        }

        mmio.reset_status();

        let mut status = STATUS_ACKNOWLEDGE;
        mmio.write_status(status);
        status |= STATUS_DRIVER;
        mmio.write_status(status);

        let features = accepted_block_features(mmio.device_features());
        mmio.write_driver_features(features);
        status |= STATUS_FEATURES_OK;
        mmio.write_status(status);
        status |= STATUS_DRIVER_OK;
        mmio.write_status(status);

        mmio.write_guest_page_size(GUEST_PAGE_SIZE);
        mmio.select_queue(0);

        let queue_max = mmio.queue_num_max();
        if queue_max == 0 || queue_max < VIRTQ_NUM as u32 {
            return Err(ENODEV);
        }
        mmio.write_queue_num(VIRTQ_NUM as u32);

        // SAFETY: `dma_va` points to a live physically-contiguous DMA region
        // of `VIRTIO_DMA_SIZE` bytes allocated by `qsoe_alloc_phys`.
        unsafe { ptr::write_bytes(dma_va, 0, VIRTIO_DMA_SIZE) };
        mmio.write_queue_pfn((dma_pa / GUEST_PAGE_SIZE as u64) as u32);

        // SAFETY: the DMA region is page-aligned and the offsets mirror the C
        // driver and legacy virtqueue layout.
        let (desc, avail, used, ops, status_ptr, databuf) = unsafe {
            (
                dma_va.cast::<VirtqDesc>(),
                dma_va
                    .add(VIRTQ_NUM * size_of::<VirtqDesc>())
                    .cast::<VirtqAvail>(),
                dma_va.add(VIRTIO_OFF_USED).cast::<VirtqUsed>(),
                dma_va.add(VIRTIO_OFF_OPS).cast::<VirtioBlkReq>(),
                dma_va
                    .add(VIRTIO_OFF_OPS + VIRTQ_NUM * size_of::<VirtioBlkReq>())
                    .cast::<u8>(),
                dma_va.add(VIRTIO_OFF_DATA),
            )
        };

        let capacity_sectors = mmio.read_config_u64(0);

        Ok(Self {
            mmio,
            dma_pa,
            desc,
            avail,
            used,
            ops,
            status: status_ptr,
            databuf,
            free: DescriptorFreeList::new(),
            used_idx: 0,
            capacity_sectors,
            bounce: [0; VIRTIO_DATA_BYTES],
        })
    }

    fn capacity_bytes(&self) -> u64 {
        self.capacity_sectors
            .saturating_mul(VIRTIO_BLK_SECTOR_SIZE as u64)
    }

    fn pull(&mut self, out: *mut u8, nbytes: usize, off: OffT) -> SsizeT {
        if nbytes == 0 {
            return 0;
        }
        if off < 0 {
            return -(EINVAL as SsizeT);
        }

        let capacity = self.capacity_bytes();
        let offset = off as u64;
        if offset >= capacity {
            return 0;
        }

        let mut nbytes = core::cmp::min(nbytes, VIRTIO_DATA_BYTES);
        if offset.saturating_add(nbytes as u64) > capacity {
            nbytes = (capacity - offset) as usize;
        }

        let first_lba = offset / VIRTIO_BLK_SECTOR_SIZE as u64;
        let last_lba = (offset + nbytes as u64 - 1) / VIRTIO_BLK_SECTOR_SIZE as u64;
        let sectors = last_lba - first_lba + 1;
        let head_skip = (offset % VIRTIO_BLK_SECTOR_SIZE as u64) as usize;
        let dma_bytes = (sectors as usize) * VIRTIO_BLK_SECTOR_SIZE;
        if dma_bytes > VIRTIO_DATA_BYTES {
            return -(EIO as SsizeT);
        }

        let bounce = self.bounce.as_mut_ptr();
        if let Err(errno) = self.rw(first_lba, bounce, dma_bytes, false) {
            return -(errno as SsizeT);
        }

        // SAFETY: `out` is provided by libressrv for a pull reply buffer of at
        // least `nbytes` bytes, and `head_skip + nbytes` was bounded above by
        // the one-page bounce buffer.
        unsafe { ptr::copy_nonoverlapping(self.bounce.as_ptr().add(head_skip), out, nbytes) };
        nbytes as SsizeT
    }

    fn rw(&mut self, sector: u64, buf: *mut u8, len: usize, write: bool) -> Result<(), c_int> {
        if len == 0 {
            return Ok(());
        }
        let len = core::cmp::min(len, VIRTIO_DATA_BYTES);
        let indices = self.alloc3()?;
        let header_slot = indices[0].raw() as usize;

        let ops_pa =
            self.dma_pa + VIRTIO_OFF_OPS as u64 + (header_slot * size_of::<VirtioBlkReq>()) as u64;
        let status_pa = self.dma_pa
            + VIRTIO_OFF_OPS as u64
            + (VIRTQ_NUM * size_of::<VirtioBlkReq>()) as u64
            + header_slot as u64;
        let data_pa = self.dma_pa + VIRTIO_OFF_DATA as u64;

        let header = DescriptorModel::driver_owned(
            indices[0],
            ops_pa,
            size_of::<VirtioBlkReq>() as u32,
            DescriptorAccess::DeviceReadable,
        )
        .with_next(indices[1]);
        let data_access = if write {
            DescriptorAccess::DeviceReadable
        } else {
            DescriptorAccess::DeviceWritable
        };
        let data = DescriptorModel::driver_owned(indices[1], data_pa, len as u32, data_access)
            .with_next(indices[2]);
        let status = DescriptorModel::driver_owned(
            indices[2],
            status_pa,
            1,
            DescriptorAccess::DeviceWritable,
        );

        // SAFETY: `ops`, `status`, `databuf`, and `desc` point inside the live
        // DMA region initialized in `init`; descriptor indices are bounded.
        unsafe {
            *self.ops.add(header_slot) = if write {
                VirtioBlkReq::write(sector)
            } else {
                VirtioBlkReq::read(sector)
            };
            if write {
                ptr::copy_nonoverlapping(buf as *const u8, self.databuf, len);
            }
            *self.status.add(header_slot) = 0xff;
            self.write_descriptor(header.publish_to_device());
            self.write_descriptor(data.publish_to_device());
            self.write_descriptor(status.publish_to_device());
        }

        self.publish(indices[0]);
        self.wait_used();
        self.mmio.acknowledge_interrupts(INTERRUPT_ACK_MASK);

        // SAFETY: `header_slot` is a bounded descriptor id and status points
        // to the per-descriptor status byte area.
        let errno = unsafe {
            if *self.status.add(header_slot) == 0 {
                0
            } else {
                EIO
            }
        };

        if !write && errno == 0 {
            // SAFETY: `buf` is the caller's writable transfer buffer of `len`
            // bytes, and `databuf` is the one-page DMA data buffer.
            unsafe { ptr::copy_nonoverlapping(self.databuf, buf, len) };
        }

        let reclaimed = [
            header.reclaim_to_driver(),
            data.reclaim_to_driver(),
            status.reclaim_to_driver(),
        ];
        self.zero_descriptors(&reclaimed);
        let _ = self.free.free_chain(reclaimed);

        if errno == 0 {
            Ok(())
        } else {
            Err(errno)
        }
    }

    fn alloc3(&mut self) -> Result<[DescriptorIndex; 3], c_int> {
        let zero = DescriptorIndex::new(0).ok_or(EBUSY)?;
        let mut indices = [zero; 3];
        let mut allocated = 0;
        while allocated < indices.len() {
            match self.free.alloc() {
                Some(index) => {
                    indices[allocated] = index;
                    allocated += 1;
                }
                None => {
                    while allocated > 0 {
                        allocated -= 1;
                        let _ = self.free.free_descriptor(indices[allocated]);
                    }
                    return Err(EBUSY);
                }
            }
        }
        Ok(indices)
    }

    fn write_descriptor(&mut self, descriptor: DescriptorModel) {
        // SAFETY: the caller passes a descriptor whose bounded index selects an
        // element inside the descriptor table.
        unsafe {
            ptr::write(
                self.desc.add(descriptor.index().raw() as usize),
                descriptor.raw(),
            )
        };
    }

    fn zero_descriptors(&mut self, descriptors: &[DescriptorModel]) {
        for descriptor in descriptors {
            // SAFETY: descriptor indices came from `DescriptorFreeList` and
            // therefore select entries inside the descriptor table.
            unsafe {
                ptr::write(
                    self.desc.add(descriptor.index().raw() as usize),
                    VirtqDesc::zeroed(),
                )
            };
        }
    }

    fn publish(&mut self, head: DescriptorIndex) {
        // SAFETY: `avail` points into the live DMA region initialized by
        // `init`; the ring slot is bounded by the queue depth.
        unsafe {
            let idx = read_volatile(&(*self.avail).idx);
            (*self.avail).ring[(idx as usize) % VIRTQ_NUM] = head.raw();
            fence(Ordering::SeqCst);
            write_volatile(&mut (*self.avail).idx, idx.wrapping_add(1));
            fence(Ordering::SeqCst);
        }
        self.mmio.notify_queue(0);
    }

    fn wait_used(&mut self) {
        loop {
            // SAFETY: `used` points into the live DMA region initialized by
            // `init`; the device owns this index while the queue is active.
            let device_idx = unsafe { read_volatile(&(*self.used).idx) };
            if self.used_idx != device_idx {
                self.used_idx = self.used_idx.wrapping_add(1);
                break;
            }
            fence(Ordering::SeqCst);
            // SAFETY: this POSIX wrapper takes no borrowed memory and only
            // yields the current thread if the runtime implements it.
            let _ = unsafe { qsoe_ffi::sched_yield() };
        }
    }
}

#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    debug_write(b"[devb-virtio-rs] panic\n");
    loop {
        core::hint::spin_loop();
    }
}

#[no_mangle]
pub extern "C" fn qsoe_devb_virtio_rust_marker() -> u64 {
    0x5153_4f45_5649_5254
}

#[no_mangle]
pub extern "C" fn main(_argc: isize, _argv: *const *const u8, _envp: *const *const u8) -> i32 {
    debug_write(b"[devb-virtio-rs] alive\n");

    let mmio = match find_block_device() {
        Some(mmio) => mmio,
        None => {
            debug_write(b"[devb-virtio-rs] no virtio-mmio block device found\n");
            return 1;
        }
    };

    let mut dma_pa = 0;
    // SAFETY: `qsoe_alloc_phys` writes one physical address to `dma_pa` and
    // returns a process VA for `VIRTIO_DMA_SIZE` bytes on success.
    let dma_va =
        unsafe { qsoe_ffi::qsoe_alloc_phys(VIRTIO_DMA_SIZE, PROT_READ_WRITE, &mut dma_pa) };
    if is_map_failed(dma_va) {
        debug_write(b"[devb-virtio-rs] alloc_phys DMA region failed\n");
        return 1;
    }

    let device = match VirtioBlockDevice::init(mmio, dma_va.cast::<u8>(), dma_pa) {
        Ok(device) => device,
        Err(_) => {
            debug_write(b"[devb-virtio-rs] device init failed\n");
            return 1;
        }
    };
    let capacity_bytes = device.capacity_bytes();
    DEVICE.set(device);

    // SAFETY: the provider storage and path/vtable are static and outlive the
    // dispatch loop.
    let provider = unsafe { &mut *PROVIDER.get() };
    unsafe {
        provider.init(
            &VBLK_VTABLE,
            VBLK_PATH.as_ptr().cast::<c_char>(),
            TM_S_IFBLK | 0o444,
        )
    };
    provider.attr.size = capacity_bytes as OffT;
    provider.attr.rdev = 8_u64 << 8;

    if provider.listen().is_err() {
        debug_write(b"[devb-virtio-rs] listen(/dev/vblk0) failed\n");
        return 1;
    }

    debug_write(b"[devb-virtio-rs] /dev/vblk0 ready\n");

    // SAFETY: `procmgr_detach` takes a scalar status and retains no borrowed
    // Rust state.
    if unsafe { qsoe_ffi::procmgr_detach(0) } != 0 {
        debug_write(b"[devb-virtio-rs] procmgr_detach failed\n");
    }

    provider.dispatch_run()
}

unsafe extern "C" fn vblk_pull(
    _self: *mut Provider,
    _h: *mut Handle,
    buf: *mut c_void,
    nbytes: SizeT,
    off: OffT,
) -> SsizeT {
    if buf.is_null() && nbytes != 0 {
        return -(EINVAL as SsizeT);
    }
    // SAFETY: all callers run on the single resource-server thread after
    // initialization. No aliasing mutable reference is created.
    let device = unsafe { (*DEVICE.get()).as_mut() };
    match device {
        Some(device) => device.pull(buf.cast::<u8>(), nbytes, off),
        None => -(EIO as SsizeT),
    }
}

fn find_block_device() -> Option<VirtioMmio> {
    let mut slot = 0;
    while slot < VIRTIO_MMIO_COUNT {
        let phys = VIRTIO_MMIO_BASE + slot * VIRTIO_MMIO_STRIDE;
        if let Some((mapping, mmio)) = map_regs(phys) {
            if mmio.is_legacy_block_device() {
                debug_write(b"[devb-virtio-rs] block device found\n");
                return Some(mmio);
            }
            // SAFETY: `mapping` is the base pointer returned by `qsoe_mmap`,
            // and the mapping length matches `map_regs`.
            let _ = unsafe { qsoe_ffi::munmap(mapping, VIRTIO_REG_BYTES) };
        }
        slot += 1;
    }
    None
}

fn map_regs(phys: u64) -> Option<(*mut c_void, VirtioMmio)> {
    // SAFETY: `qsoe_mmap` maps the physical MMIO register window into this
    // process; the returned pointer is checked before constructing `VirtioMmio`.
    let ptr = unsafe {
        qsoe_ffi::qsoe_mmap(
            ptr::null_mut(),
            VIRTIO_REG_BYTES,
            PROT_READ_WRITE,
            MAP_PHYS | MAP_SHARED,
            -1,
            phys as OffT,
        )
    };
    if is_map_failed(ptr) {
        return None;
    }
    // SAFETY: the mapping is a writable virtio-mmio register window candidate
    // with `VIRTIO_REG_BYTES` bytes.
    unsafe { VirtioMmio::new(ptr.cast::<u32>()).map(|mmio| (ptr, mmio)) }
}

fn is_map_failed(ptr: *mut c_void) -> bool {
    ptr.is_null() || ptr as isize == MAP_FAILED
}

fn debug_write(bytes: &[u8]) {
    // SAFETY: `bytes` points to readable memory for this synchronous debug
    // write call; QSOE does not retain the pointer.
    unsafe { qsoe_ffi::dbg_write(bytes.as_ptr().cast::<c_char>(), bytes.len()) };
}
