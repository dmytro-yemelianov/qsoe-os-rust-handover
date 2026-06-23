#![no_std]

use core::marker::PhantomData;
use core::ptr::{read_volatile, write_volatile, NonNull};

pub const MMIO_BYTES: usize = 0x1000;
pub const REGISTER_BYTES: usize = core::mem::size_of::<u32>();

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Register {
    offset: usize,
}

impl Register {
    pub const fn new(offset: usize) -> Self {
        Self { offset }
    }

    pub const fn offset(self) -> usize {
        self.offset
    }

    pub const fn word_index(self) -> usize {
        self.offset / REGISTER_BYTES
    }
}

pub mod regs {
    use super::Register;

    pub const MAGIC_VALUE: Register = Register::new(0x000);
    pub const VERSION: Register = Register::new(0x004);
    pub const DEVICE_ID: Register = Register::new(0x008);
    pub const VENDOR_ID: Register = Register::new(0x00c);
    pub const DEVICE_FEATURES: Register = Register::new(0x010);
    pub const DRIVER_FEATURES: Register = Register::new(0x020);
    pub const GUEST_PAGE_SIZE: Register = Register::new(0x028);
    pub const QUEUE_SEL: Register = Register::new(0x030);
    pub const QUEUE_NUM_MAX: Register = Register::new(0x034);
    pub const QUEUE_NUM: Register = Register::new(0x038);
    pub const QUEUE_ALIGN: Register = Register::new(0x03c);
    pub const QUEUE_PFN: Register = Register::new(0x040);
    pub const QUEUE_NOTIFY: Register = Register::new(0x050);
    pub const INTERRUPT_STATUS: Register = Register::new(0x060);
    pub const INTERRUPT_ACK: Register = Register::new(0x064);
    pub const STATUS: Register = Register::new(0x070);
    pub const CONFIG: Register = Register::new(0x100);
}

pub const VIRTIO_MAGIC: u32 = 0x7472_6976;
pub const VIRTIO_VERSION_LEGACY: u32 = 1;
pub const VIRTIO_DEVID_BLK: u32 = 2;

pub const STATUS_ACKNOWLEDGE: u32 = 1;
pub const STATUS_DRIVER: u32 = 2;
pub const STATUS_DRIVER_OK: u32 = 4;
pub const STATUS_FEATURES_OK: u32 = 8;

pub const GUEST_PAGE_SIZE: u32 = 4096;
pub const VIRTQ_NUM: usize = 8;
pub const VIRTIO_BLK_SECTOR_SIZE: usize = 512;
pub const VIRTIO_DATA_BYTES: usize = 4096;
pub const VIRTIO_DMA_PAGE_BYTES: usize = 4096;
pub const VIRTIO_DMA_PAGES: usize = 4;
pub const VIRTIO_DMA_SIZE: usize = VIRTIO_DMA_PAGE_BYTES * VIRTIO_DMA_PAGES;
pub const VIRTIO_OFF_USED: usize = VIRTIO_DMA_PAGE_BYTES;
pub const VIRTIO_OFF_OPS: usize = 2 * VIRTIO_DMA_PAGE_BYTES;
pub const VIRTIO_OFF_DATA: usize = 3 * VIRTIO_DMA_PAGE_BYTES;

pub const BLK_F_RO: u32 = 5;
pub const BLK_F_SCSI: u32 = 7;
pub const BLK_F_CONFIG_WCE: u32 = 11;
pub const BLK_F_MQ: u32 = 12;
pub const F_ANY_LAYOUT: u32 = 27;
pub const RING_F_INDIRECT_DESC: u32 = 28;
pub const RING_F_EVENT_IDX: u32 = 29;

pub const fn feature_bit(bit: u32) -> u32 {
    1u32 << bit
}

pub const UNSUPPORTED_BLOCK_FEATURES: u32 = feature_bit(BLK_F_RO)
    | feature_bit(BLK_F_SCSI)
    | feature_bit(BLK_F_CONFIG_WCE)
    | feature_bit(BLK_F_MQ)
    | feature_bit(F_ANY_LAYOUT)
    | feature_bit(RING_F_INDIRECT_DESC)
    | feature_bit(RING_F_EVENT_IDX);

pub const fn accepted_block_features(device_features: u32) -> u32 {
    device_features & !UNSUPPORTED_BLOCK_FEATURES
}

pub const VIRTIO_BLK_T_IN: u32 = 0;
pub const VIRTIO_BLK_T_OUT: u32 = 1;

pub const VRING_DESC_F_NEXT: u16 = 1;
pub const VRING_DESC_F_WRITE: u16 = 2;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct VirtqDesc {
    pub addr: u64,
    pub len: u32,
    pub flags: u16,
    pub next: u16,
}

impl VirtqDesc {
    pub const fn zeroed() -> Self {
        Self {
            addr: 0,
            len: 0,
            flags: 0,
            next: 0,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct VirtqAvail {
    pub flags: u16,
    pub idx: u16,
    pub ring: [u16; VIRTQ_NUM],
    pub unused: u16,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct VirtqUsedElem {
    pub id: u32,
    pub len: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct VirtqUsed {
    pub flags: u16,
    pub idx: u16,
    pub ring: [VirtqUsedElem; VIRTQ_NUM],
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct VirtioBlkReq {
    pub type_: u32,
    pub reserved: u32,
    pub sector: u64,
}

impl VirtioBlkReq {
    pub const fn read(sector: u64) -> Self {
        Self {
            type_: VIRTIO_BLK_T_IN,
            reserved: 0,
            sector,
        }
    }

    pub const fn write(sector: u64) -> Self {
        Self {
            type_: VIRTIO_BLK_T_OUT,
            reserved: 0,
            sector,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DescriptorIndex(u16);

impl DescriptorIndex {
    pub const fn new(index: u16) -> Option<Self> {
        if (index as usize) < VIRTQ_NUM {
            Some(Self(index))
        } else {
            None
        }
    }

    pub const fn raw(self) -> u16 {
        self.0
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DescriptorOwner {
    Driver,
    Device,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DescriptorAccess {
    DeviceReadable,
    DeviceWritable,
}

impl DescriptorAccess {
    pub const fn write_flag(self) -> u16 {
        match self {
            Self::DeviceReadable => 0,
            Self::DeviceWritable => VRING_DESC_F_WRITE,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DescriptorModel {
    index: DescriptorIndex,
    owner: DescriptorOwner,
    access: DescriptorAccess,
    addr: u64,
    len: u32,
    next: Option<DescriptorIndex>,
}

impl DescriptorModel {
    pub const fn driver_owned(
        index: DescriptorIndex,
        addr: u64,
        len: u32,
        access: DescriptorAccess,
    ) -> Self {
        Self {
            index,
            owner: DescriptorOwner::Driver,
            access,
            addr,
            len,
            next: None,
        }
    }

    pub const fn with_next(mut self, next: DescriptorIndex) -> Self {
        self.next = Some(next);
        self
    }

    pub const fn publish_to_device(mut self) -> Self {
        self.owner = DescriptorOwner::Device;
        self
    }

    pub const fn reclaim_to_driver(mut self) -> Self {
        self.owner = DescriptorOwner::Driver;
        self
    }

    pub const fn index(self) -> DescriptorIndex {
        self.index
    }

    pub const fn owner(self) -> DescriptorOwner {
        self.owner
    }

    pub const fn access(self) -> DescriptorAccess {
        self.access
    }

    pub const fn next(self) -> Option<DescriptorIndex> {
        self.next
    }

    pub const fn raw(self) -> VirtqDesc {
        let mut flags = self.access.write_flag();
        let mut next = 0;
        if let Some(index) = self.next {
            flags |= VRING_DESC_F_NEXT;
            next = index.raw();
        }

        VirtqDesc {
            addr: self.addr,
            len: self.len,
            flags,
            next,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DescriptorBuffer {
    addr: u64,
    len: u32,
    access: DescriptorAccess,
}

impl DescriptorBuffer {
    pub const fn new(addr: u64, len: u32, access: DescriptorAccess) -> Self {
        Self { addr, len, access }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DescriptorQueueError {
    EmptyChain,
    OutOfDescriptors,
    DescriptorAlreadyFree,
    DescriptorOwnedByDevice,
    DuplicateDescriptor,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DescriptorFreeList {
    free: [bool; VIRTQ_NUM],
    available: usize,
}

impl DescriptorFreeList {
    pub const fn new() -> Self {
        Self {
            free: [true; VIRTQ_NUM],
            available: VIRTQ_NUM,
        }
    }

    pub const fn available(&self) -> usize {
        self.available
    }

    pub fn is_free(&self, index: DescriptorIndex) -> bool {
        self.free[index.raw() as usize]
    }

    pub fn alloc(&mut self) -> Option<DescriptorIndex> {
        let mut index = 0;
        while index < VIRTQ_NUM {
            if self.free[index] {
                self.free[index] = false;
                self.available -= 1;
                return Some(DescriptorIndex(index as u16));
            }
            index += 1;
        }
        None
    }

    pub fn alloc_chain<const N: usize>(
        &mut self,
        buffers: [DescriptorBuffer; N],
    ) -> Result<[DescriptorModel; N], DescriptorQueueError> {
        if N == 0 {
            return Err(DescriptorQueueError::EmptyChain);
        }
        if self.available < N {
            return Err(DescriptorQueueError::OutOfDescriptors);
        }

        let mut indices = [DescriptorIndex(0); N];
        let mut index = 0;
        while index < N {
            indices[index] = self.alloc().ok_or(DescriptorQueueError::OutOfDescriptors)?;
            index += 1;
        }

        Ok(core::array::from_fn(|index| {
            let buffer = buffers[index];
            let descriptor = DescriptorModel::driver_owned(
                indices[index],
                buffer.addr,
                buffer.len,
                buffer.access,
            );
            if index + 1 < N {
                descriptor.with_next(indices[index + 1])
            } else {
                descriptor
            }
        }))
    }

    pub fn free_descriptor(&mut self, index: DescriptorIndex) -> Result<(), DescriptorQueueError> {
        let slot = index.raw() as usize;
        if self.free[slot] {
            return Err(DescriptorQueueError::DescriptorAlreadyFree);
        }

        self.free[slot] = true;
        self.available += 1;
        Ok(())
    }

    pub fn free_chain<const N: usize>(
        &mut self,
        chain: [DescriptorModel; N],
    ) -> Result<(), DescriptorQueueError> {
        if N == 0 {
            return Err(DescriptorQueueError::EmptyChain);
        }

        let mut index = 0;
        while index < N {
            let descriptor = chain[index];
            if descriptor.owner() != DescriptorOwner::Driver {
                return Err(DescriptorQueueError::DescriptorOwnedByDevice);
            }
            if self.is_free(descriptor.index()) {
                return Err(DescriptorQueueError::DescriptorAlreadyFree);
            }

            let mut next = index + 1;
            while next < N {
                if descriptor.index() == chain[next].index() {
                    return Err(DescriptorQueueError::DuplicateDescriptor);
                }
                next += 1;
            }
            index += 1;
        }

        let mut index = 0;
        while index < N {
            self.free_descriptor(chain[index].index())?;
            index += 1;
        }
        Ok(())
    }
}

impl Default for DescriptorFreeList {
    fn default() -> Self {
        Self::new()
    }
}

pub struct VirtioMmio {
    base: NonNull<u32>,
    _not_send_sync: PhantomData<*mut u32>,
}

impl VirtioMmio {
    /// Build a wrapper around a mapped virtio-mmio register window.
    ///
    /// # Safety
    ///
    /// `base` must point to a live, writable `MMIO_BYTES` virtio-mmio mapping
    /// whose lifetime outlives the returned wrapper. The mapping must not be
    /// concurrently accessed through other Rust references.
    pub unsafe fn new(base: *mut u32) -> Option<Self> {
        NonNull::new(base).map(|base| Self {
            base,
            _not_send_sync: PhantomData,
        })
    }

    pub fn read(&self, register: Register) -> u32 {
        assert_valid_register(register);
        // SAFETY: `new`'s caller guarantees that `base` is a live MMIO window
        // of `MMIO_BYTES`. `assert_valid_register` bounds the 32-bit offset.
        unsafe { read_volatile(self.base.as_ptr().add(register.word_index())) }
    }

    pub fn write(&self, register: Register, value: u32) {
        assert_valid_register(register);
        // SAFETY: `new`'s caller guarantees that `base` is a live writable
        // MMIO window of `MMIO_BYTES`. `assert_valid_register` bounds the
        // 32-bit offset.
        unsafe { write_volatile(self.base.as_ptr().add(register.word_index()), value) };
    }

    pub fn is_legacy_block_device(&self) -> bool {
        self.read(regs::MAGIC_VALUE) == VIRTIO_MAGIC
            && self.read(regs::VERSION) == VIRTIO_VERSION_LEGACY
            && self.read(regs::DEVICE_ID) == VIRTIO_DEVID_BLK
    }

    pub fn device_features(&self) -> u32 {
        self.read(regs::DEVICE_FEATURES)
    }

    pub fn write_driver_features(&self, features: u32) {
        self.write(regs::DRIVER_FEATURES, features);
    }

    pub fn status(&self) -> u32 {
        self.read(regs::STATUS)
    }

    pub fn write_status(&self, status: u32) {
        self.write(regs::STATUS, status);
    }

    pub fn reset_status(&self) {
        self.write_status(0);
    }

    pub fn select_queue(&self, queue: u32) {
        self.write(regs::QUEUE_SEL, queue);
    }

    pub fn queue_num_max(&self) -> u32 {
        self.read(regs::QUEUE_NUM_MAX)
    }

    pub fn write_queue_num(&self, queue_num: u32) {
        self.write(regs::QUEUE_NUM, queue_num);
    }

    pub fn write_guest_page_size(&self, page_size: u32) {
        self.write(regs::GUEST_PAGE_SIZE, page_size);
    }

    pub fn write_queue_pfn(&self, pfn: u32) {
        self.write(regs::QUEUE_PFN, pfn);
    }

    pub fn notify_queue(&self, queue: u32) {
        self.write(regs::QUEUE_NOTIFY, queue);
    }

    pub fn interrupt_status(&self) -> u32 {
        self.read(regs::INTERRUPT_STATUS)
    }

    pub fn acknowledge_interrupts(&self, mask: u32) {
        self.write(regs::INTERRUPT_ACK, self.interrupt_status() & mask);
    }

    pub fn read_config_u64(&self, offset: usize) -> u64 {
        let lo = self.read(Register::new(regs::CONFIG.offset() + offset)) as u64;
        let hi = self.read(Register::new(
            regs::CONFIG.offset() + offset + REGISTER_BYTES,
        )) as u64;
        lo | (hi << 32)
    }
}

fn assert_valid_register(register: Register) {
    assert_eq!(register.offset() % REGISTER_BYTES, 0);
    assert!(register.offset() + REGISTER_BYTES <= MMIO_BYTES);
}

#[cfg(test)]
extern crate std;

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::{align_of, size_of};

    fn with_regs<T>(f: impl FnOnce(VirtioMmio, &mut [u32; MMIO_BYTES / REGISTER_BYTES]) -> T) -> T {
        let mut regs = [0u32; MMIO_BYTES / REGISTER_BYTES];
        // SAFETY: the backing array is writable, register-sized, and lives for
        // the duration of the wrapper used in this test.
        let mmio = unsafe { VirtioMmio::new(regs.as_mut_ptr()).unwrap() };
        f(mmio, &mut regs)
    }

    #[test]
    fn register_offsets_match_legacy_virtio_mmio_layout() {
        assert_eq!(regs::MAGIC_VALUE.word_index(), 0x000 / 4);
        assert_eq!(regs::DEVICE_FEATURES.word_index(), 0x010 / 4);
        assert_eq!(regs::QUEUE_PFN.word_index(), 0x040 / 4);
        assert_eq!(regs::STATUS.word_index(), 0x070 / 4);
        assert_eq!(regs::CONFIG.word_index(), 0x100 / 4);
    }

    #[test]
    fn virtqueue_layouts_match_c_driver_shapes() {
        assert_eq!(VIRTQ_NUM, 8);
        assert_eq!(VIRTIO_DATA_BYTES, 4096);
        assert_eq!(VIRTIO_DMA_SIZE, 16 * 1024);
        assert_eq!(VIRTIO_OFF_USED, 4096);
        assert_eq!(VIRTIO_OFF_OPS, 8192);
        assert_eq!(VIRTIO_OFF_DATA, 12288);

        assert_eq!(size_of::<VirtqDesc>(), 16);
        assert_eq!(align_of::<VirtqDesc>(), 8);
        assert_eq!(size_of::<VirtqAvail>(), 22);
        assert_eq!(align_of::<VirtqAvail>(), 2);
        assert_eq!(size_of::<VirtqUsedElem>(), 8);
        assert_eq!(align_of::<VirtqUsedElem>(), 4);
        assert_eq!(size_of::<VirtqUsed>(), 68);
        assert_eq!(align_of::<VirtqUsed>(), 4);
        assert_eq!(size_of::<VirtioBlkReq>(), 16);
        assert_eq!(align_of::<VirtioBlkReq>(), 8);
    }

    #[test]
    fn descriptor_index_is_bounded_to_queue_depth() {
        assert_eq!(DescriptorIndex::new(0).unwrap().raw(), 0);
        assert_eq!(
            DescriptorIndex::new((VIRTQ_NUM - 1) as u16).unwrap().raw(),
            7
        );
        assert_eq!(DescriptorIndex::new(VIRTQ_NUM as u16), None);
    }

    #[test]
    fn descriptor_model_tracks_owner_and_device_mutability() {
        let header = DescriptorModel::driver_owned(
            DescriptorIndex::new(0).unwrap(),
            0x2000,
            size_of::<VirtioBlkReq>() as u32,
            DescriptorAccess::DeviceReadable,
        )
        .with_next(DescriptorIndex::new(1).unwrap());
        let data = DescriptorModel::driver_owned(
            DescriptorIndex::new(1).unwrap(),
            0x3000,
            VIRTIO_DATA_BYTES as u32,
            DescriptorAccess::DeviceWritable,
        )
        .with_next(DescriptorIndex::new(2).unwrap());

        assert_eq!(header.owner(), DescriptorOwner::Driver);
        assert_eq!(header.access(), DescriptorAccess::DeviceReadable);
        assert_eq!(header.next(), DescriptorIndex::new(1));
        assert_eq!(
            header.raw(),
            VirtqDesc {
                addr: 0x2000,
                len: 16,
                flags: VRING_DESC_F_NEXT,
                next: 1,
            }
        );
        assert_eq!(
            data.raw(),
            VirtqDesc {
                addr: 0x3000,
                len: 4096,
                flags: VRING_DESC_F_WRITE | VRING_DESC_F_NEXT,
                next: 2,
            }
        );

        let published = data.publish_to_device();
        assert_eq!(published.owner(), DescriptorOwner::Device);
        assert_eq!(
            published.reclaim_to_driver().owner(),
            DescriptorOwner::Driver
        );
    }

    #[test]
    fn block_request_headers_encode_direction_and_sector() {
        assert_eq!(
            VirtioBlkReq::read(9),
            VirtioBlkReq {
                type_: VIRTIO_BLK_T_IN,
                reserved: 0,
                sector: 9,
            }
        );
        assert_eq!(
            VirtioBlkReq::write(10),
            VirtioBlkReq {
                type_: VIRTIO_BLK_T_OUT,
                reserved: 0,
                sector: 10,
            }
        );
    }

    #[test]
    fn descriptor_chain_allocation_builds_legacy_request_shape() {
        let mut free = DescriptorFreeList::new();
        let chain = free
            .alloc_chain([
                DescriptorBuffer::new(
                    0x2000,
                    size_of::<VirtioBlkReq>() as u32,
                    DescriptorAccess::DeviceReadable,
                ),
                DescriptorBuffer::new(
                    0x3000,
                    VIRTIO_BLK_SECTOR_SIZE as u32,
                    DescriptorAccess::DeviceWritable,
                ),
                DescriptorBuffer::new(0x2080, 1, DescriptorAccess::DeviceWritable),
            ])
            .unwrap();

        assert_eq!(free.available(), VIRTQ_NUM - 3);
        assert_eq!(chain[0].index().raw(), 0);
        assert_eq!(chain[1].index().raw(), 1);
        assert_eq!(chain[2].index().raw(), 2);
        assert_eq!(
            chain[0].raw(),
            VirtqDesc {
                addr: 0x2000,
                len: 16,
                flags: VRING_DESC_F_NEXT,
                next: 1,
            }
        );
        assert_eq!(
            chain[1].raw(),
            VirtqDesc {
                addr: 0x3000,
                len: 512,
                flags: VRING_DESC_F_WRITE | VRING_DESC_F_NEXT,
                next: 2,
            }
        );
        assert_eq!(
            chain[2].raw(),
            VirtqDesc {
                addr: 0x2080,
                len: 1,
                flags: VRING_DESC_F_WRITE,
                next: 0,
            }
        );
    }

    #[test]
    fn descriptor_chain_exhaustion_does_not_consume_free_entries() {
        let mut free = DescriptorFreeList::new();
        let buffer = DescriptorBuffer::new(0x4000, 1, DescriptorAccess::DeviceReadable);

        let held = free.alloc_chain([buffer; VIRTQ_NUM - 2]).unwrap();
        assert_eq!(free.available(), 2);

        assert_eq!(
            free.alloc_chain([buffer; 3]),
            Err(DescriptorQueueError::OutOfDescriptors)
        );
        assert_eq!(free.available(), 2);

        free.free_chain(held).unwrap();
        assert_eq!(free.available(), VIRTQ_NUM);
    }

    #[test]
    fn descriptor_free_list_reclaims_chain_and_reuses_lowest_indices() {
        let mut free = DescriptorFreeList::new();
        let buffer = DescriptorBuffer::new(0x5000, 1, DescriptorAccess::DeviceReadable);
        let chain = free.alloc_chain([buffer; 3]).unwrap();
        let published = chain.map(|descriptor| descriptor.publish_to_device());

        assert_eq!(
            free.free_chain(published),
            Err(DescriptorQueueError::DescriptorOwnedByDevice)
        );
        assert_eq!(free.available(), VIRTQ_NUM - 3);

        let reclaimed = published.map(|descriptor| descriptor.reclaim_to_driver());
        free.free_chain(reclaimed).unwrap();
        assert_eq!(free.available(), VIRTQ_NUM);
        assert!(free.is_free(DescriptorIndex::new(0).unwrap()));
        assert!(free.is_free(DescriptorIndex::new(1).unwrap()));
        assert!(free.is_free(DescriptorIndex::new(2).unwrap()));

        let reused = free.alloc_chain([buffer; 3]).unwrap();
        assert_eq!(reused[0].index().raw(), 0);
        assert_eq!(reused[1].index().raw(), 1);
        assert_eq!(reused[2].index().raw(), 2);
    }

    #[test]
    fn descriptor_free_list_rejects_empty_and_duplicate_frees() {
        let mut free = DescriptorFreeList::new();
        let empty: [DescriptorBuffer; 0] = [];
        assert_eq!(
            free.alloc_chain(empty),
            Err(DescriptorQueueError::EmptyChain)
        );

        let index = free.alloc().unwrap();
        assert_eq!(free.free_descriptor(index), Ok(()));
        assert_eq!(
            free.free_descriptor(index),
            Err(DescriptorQueueError::DescriptorAlreadyFree)
        );
    }

    #[test]
    fn descriptor_free_list_rejects_duplicate_chain_entries_without_partial_free() {
        let mut free = DescriptorFreeList::new();
        let first = free.alloc().unwrap();
        let second = free.alloc().unwrap();
        let descriptor =
            DescriptorModel::driver_owned(first, 0x6000, 1, DescriptorAccess::DeviceReadable)
                .with_next(second);

        assert_eq!(
            free.free_chain([descriptor, descriptor]),
            Err(DescriptorQueueError::DuplicateDescriptor)
        );
        assert_eq!(free.available(), VIRTQ_NUM - 2);
        assert!(!free.is_free(first));
        assert!(!free.is_free(second));

        free.free_descriptor(first).unwrap();
        free.free_descriptor(second).unwrap();
        assert_eq!(free.available(), VIRTQ_NUM);
    }

    #[test]
    fn probes_legacy_block_identity_registers() {
        with_regs(|mmio, regs| {
            regs[regs::MAGIC_VALUE.word_index()] = VIRTIO_MAGIC;
            regs[regs::VERSION.word_index()] = VIRTIO_VERSION_LEGACY;
            regs[regs::DEVICE_ID.word_index()] = VIRTIO_DEVID_BLK;
            assert!(mmio.is_legacy_block_device());

            regs[regs::DEVICE_ID.word_index()] = 1;
            assert!(!mmio.is_legacy_block_device());
        });
    }

    #[test]
    fn reads_and_writes_registers_through_volatile_accessors() {
        with_regs(|mmio, regs| {
            mmio.write_status(STATUS_ACKNOWLEDGE | STATUS_DRIVER);
            assert_eq!(
                regs[regs::STATUS.word_index()],
                STATUS_ACKNOWLEDGE | STATUS_DRIVER
            );
            assert_eq!(mmio.status(), STATUS_ACKNOWLEDGE | STATUS_DRIVER);

            mmio.select_queue(0);
            mmio.write_queue_num(8);
            mmio.write_guest_page_size(GUEST_PAGE_SIZE);
            mmio.write_queue_pfn(0x1234);
            mmio.notify_queue(0);

            assert_eq!(regs[regs::QUEUE_SEL.word_index()], 0);
            assert_eq!(regs[regs::QUEUE_NUM.word_index()], 8);
            assert_eq!(regs[regs::GUEST_PAGE_SIZE.word_index()], GUEST_PAGE_SIZE);
            assert_eq!(regs[regs::QUEUE_PFN.word_index()], 0x1234);
            assert_eq!(regs[regs::QUEUE_NOTIFY.word_index()], 0);
        });
    }

    #[test]
    fn strips_unsupported_block_features() {
        let supported = feature_bit(0) | feature_bit(1) | feature_bit(2);
        let device_features = supported | UNSUPPORTED_BLOCK_FEATURES;
        assert_eq!(accepted_block_features(device_features), supported);
    }

    #[test]
    fn reads_64_bit_config_values_from_low_high_words() {
        with_regs(|mmio, regs| {
            regs[regs::CONFIG.word_index()] = 0x89ab_cdef;
            regs[regs::CONFIG.word_index() + 1] = 0x0123_4567;
            assert_eq!(mmio.read_config_u64(0), 0x0123_4567_89ab_cdef);
        });
    }

    #[test]
    fn acknowledges_only_interrupt_bits_selected_by_mask() {
        with_regs(|mmio, regs| {
            regs[regs::INTERRUPT_STATUS.word_index()] = 0b1011;
            mmio.acknowledge_interrupts(0b0011);
            assert_eq!(regs[regs::INTERRUPT_ACK.word_index()], 0b0011);
        });
    }
}
