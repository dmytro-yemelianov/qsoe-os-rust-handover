#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

use core::ffi::{c_int, c_uint, c_void};

const TM_SYSMAP_PAGE_BYTES: usize = 4096;
const QSOE_SYSMAP_MAGIC: u32 = 0x5053_5953;
const QSOE_SYSMAP_VERSION: u16 = 1;

const QSOE_SYSMAP_TAG_END: u16 = 0;
const QSOE_SYSMAP_TAG_PLIC: u16 = 2;
const QSOE_SYSMAP_TAG_PCI_ECAM: u16 = 3;
const QSOE_SYSMAP_TAG_MTIME_FREQ: u16 = 5;

const TM_SYSCFG_TAG_END: u16 = 0;
const TM_SYSCFG_TAG_TIMEBASE_HZ: c_uint = 4;
const TM_SYSCFG_TAG_NUM_CPUS: c_uint = 5;
const TM_SYSCFG_TAG_PCI_ECAM: c_uint = 8;
const TM_SYSCFG_TAG_PCI_WINDOW: u16 = 10;
const TM_SYSCFG_TAG_DW_MSI: c_uint = 11;
const TM_SYSCFG_PCI_WINDOW_MEM: u32 = 0x2;
const TM_SYSCFG_PCI_WINDOW_PREFETCH: u32 = 0x4;

const SYSMAP_HDR_BYTES: c_uint = 16;
const SYSMAP_TLV_HDR_BYTES: c_uint = 4;
const SYSMAP_MTIME_FREQ_BYTES: c_uint = 8;
const SYSMAP_PLIC_BYTES: c_uint = 56;
const SYSMAP_PCI_ECAM_BYTES: c_uint = 64;

static mut S_PAGE: [u8; TM_SYSMAP_PAGE_BYTES] = [0; TM_SYSMAP_PAGE_BYTES];
static mut S_LEN: c_uint = 0;
static mut S_READY: c_int = 0;

unsafe extern "C" {
    fn tm_syscfg_get(out_blob: *mut *const c_void, out_len: *mut c_uint) -> c_int;
    fn tm_syscfg_find(tag_id: c_uint, out_ptr: *mut *const c_void, out_len: *mut c_uint) -> c_int;
    fn tm_syscfg_find_u64(tag_id: c_uint, out: *mut u64) -> c_int;
    fn tm_syscfg_find_u32(tag_id: c_uint, out: *mut u32) -> c_int;
}

unsafe fn page_ptr() -> *mut u8 {
    core::ptr::addr_of_mut!(S_PAGE).cast::<u8>()
}

unsafe fn page_const_ptr() -> *const u8 {
    core::ptr::addr_of!(S_PAGE).cast::<u8>()
}

unsafe fn read_u8(base: *const u8, off: c_uint) -> u8 {
    *base.add(off as usize)
}

unsafe fn read_le16(base: *const u8, off: c_uint) -> u16 {
    u16::from(read_u8(base, off)) | (u16::from(read_u8(base, off.wrapping_add(1))) << 8)
}

unsafe fn read_le32(base: *const u8, off: c_uint) -> u32 {
    u32::from(read_u8(base, off))
        | (u32::from(read_u8(base, off.wrapping_add(1))) << 8)
        | (u32::from(read_u8(base, off.wrapping_add(2))) << 16)
        | (u32::from(read_u8(base, off.wrapping_add(3))) << 24)
}

unsafe fn read_le64(base: *const u8, off: c_uint) -> u64 {
    let mut v = 0u64;
    let mut i = 8u32;
    while i > 0 {
        i -= 1;
        v = (v << 8) | u64::from(read_u8(base, off.wrapping_add(i)));
    }
    v
}

unsafe fn write_le16(base: *mut u8, off: c_uint, value: u16) {
    *base.add(off as usize) = (value & 0xff) as u8;
    *base.add(off.wrapping_add(1) as usize) = ((value >> 8) & 0xff) as u8;
}

unsafe fn write_le32(base: *mut u8, off: c_uint, value: u32) {
    *base.add(off as usize) = (value & 0xff) as u8;
    *base.add(off.wrapping_add(1) as usize) = ((value >> 8) & 0xff) as u8;
    *base.add(off.wrapping_add(2) as usize) = ((value >> 16) & 0xff) as u8;
    *base.add(off.wrapping_add(3) as usize) = ((value >> 24) & 0xff) as u8;
}

unsafe fn write_le64(base: *mut u8, off: c_uint, value: u64) {
    let mut i = 0u32;
    while i < 8 {
        *base.add(off.wrapping_add(i) as usize) = ((value >> (i * 8)) & 0xff) as u8;
        i += 1;
    }
}

unsafe fn zero_page() {
    let p = page_ptr();
    let mut i = 0usize;
    while i < TM_SYSMAP_PAGE_BYTES {
        *p.add(i) = 0;
        i += 1;
    }
}

unsafe fn write_header(total_bytes: c_uint) {
    let p = page_ptr();
    write_le32(p, 0, QSOE_SYSMAP_MAGIC);
    write_le16(p, 4, QSOE_SYSMAP_VERSION);
    write_le16(p, 6, SYSMAP_HDR_BYTES as u16);
    write_le32(p, 8, total_bytes);
    write_le32(p, 12, 0);
}

unsafe fn align8(value: c_uint) -> c_uint {
    value.wrapping_add(7) & !7
}

unsafe fn emit(tag: u16, body: *const u8, len: c_uint) {
    let rec = SYSMAP_TLV_HDR_BYTES.wrapping_add(len);
    let pad = align8(rec);
    if S_LEN.wrapping_add(pad) > TM_SYSMAP_PAGE_BYTES as c_uint {
        return;
    }

    let p = page_ptr();
    write_le16(p, S_LEN, tag);
    write_le16(p, S_LEN.wrapping_add(2), len as u16);

    if len != 0 && !body.is_null() {
        let mut i = 0u32;
        while i < len {
            *p.add(S_LEN.wrapping_add(SYSMAP_TLV_HDR_BYTES).wrapping_add(i) as usize) =
                *body.add(i as usize);
            i += 1;
        }
    }

    let mut i = rec;
    while i < pad {
        *p.add(S_LEN.wrapping_add(i) as usize) = 0;
        i += 1;
    }
    S_LEN = S_LEN.wrapping_add(pad);
}

unsafe fn find_pci_mem_window(out_pci: *mut u8) {
    let mut blob: *const c_void = core::ptr::null();
    let mut blen = 0u32;
    if tm_syscfg_get(&mut blob, &mut blen) != 0 || blob.is_null() {
        return;
    }

    let bp = blob.cast::<u8>();
    let mut off = 0u32;
    while off.wrapping_add(4) <= blen {
        let id = read_le16(bp, off);
        let len = u32::from(read_le16(bp, off.wrapping_add(2)));
        if id == TM_SYSCFG_TAG_END {
            break;
        }
        if id == TM_SYSCFG_TAG_PCI_WINDOW && len >= 28 {
            let w = bp.add(off.wrapping_add(4) as usize);
            let flags = read_le32(w, 24);
            if (flags & TM_SYSCFG_PCI_WINDOW_MEM) != 0
                && (flags & TM_SYSCFG_PCI_WINDOW_PREFETCH) == 0
            {
                write_le64(out_pci, 40, read_le64(w, 0));
                write_le64(out_pci, 48, read_le64(w, 8));
                write_le64(out_pci, 56, read_le64(w, 16));
                break;
            }
        }
        off = off.wrapping_add(4).wrapping_add(len);
    }
}

/// Build the cached PSYS sysmap page from the already-built taskman syscfg.
///
/// # Safety
///
/// The linked `tm_syscfg_*` providers must follow the taskman ABI and return
/// pointers readable for their advertised payload lengths.
#[no_mangle]
pub unsafe extern "C" fn tm_sysmap_build() -> c_int {
    S_READY = 0;
    S_LEN = 0;
    zero_page();

    write_header(0);
    S_LEN = SYSMAP_HDR_BYTES;

    let mut hz = 0u64;
    if tm_syscfg_find_u64(TM_SYSCFG_TAG_TIMEBASE_HZ, &mut hz) == 0 && hz != 0 {
        let mut m = [0u8; SYSMAP_MTIME_FREQ_BYTES as usize];
        write_le32(m.as_mut_ptr(), 0, hz as u32);
        write_le32(m.as_mut_ptr(), 4, 0);
        emit(
            QSOE_SYSMAP_TAG_MTIME_FREQ,
            m.as_ptr(),
            SYSMAP_MTIME_FREQ_BYTES,
        );
    }

    let mut ncpu = 0u32;
    if tm_syscfg_find_u32(TM_SYSCFG_TAG_NUM_CPUS, &mut ncpu) == 0 && ncpu != 0 {
        let mut plic = [0u8; SYSMAP_PLIC_BYTES as usize];
        write_le32(plic.as_mut_ptr(), 20, ncpu);
        emit(QSOE_SYSMAP_TAG_PLIC, plic.as_ptr(), SYSMAP_PLIC_BYTES);
    }

    let mut ep: *const c_void = core::ptr::null();
    let mut el = 0u32;
    if tm_syscfg_find(TM_SYSCFG_TAG_PCI_ECAM, &mut ep, &mut el) == 0 && el >= 20 {
        let b = ep.cast::<u8>();
        let mut pci = [0u8; SYSMAP_PCI_ECAM_BYTES as usize];
        write_le64(pci.as_mut_ptr(), 0, read_le64(b, 0));
        write_le64(pci.as_mut_ptr(), 8, read_le64(b, 8));
        *pci.as_mut_ptr().add(32) = 0;
        *pci.as_mut_ptr().add(33) = read_le32(b, 16) as u8;

        find_pci_mem_window(pci.as_mut_ptr());

        let mut dp: *const c_void = core::ptr::null();
        let mut dl = 0u32;
        if tm_syscfg_find(TM_SYSCFG_TAG_DW_MSI, &mut dp, &mut dl) == 0 && dl >= 20 {
            let d = dp.cast::<u8>();
            write_le64(pci.as_mut_ptr(), 16, read_le64(d, 0));
            write_le64(pci.as_mut_ptr(), 24, read_le64(d, 8));
            write_le32(pci.as_mut_ptr(), 36, read_le32(d, 16));
        }

        emit(
            QSOE_SYSMAP_TAG_PCI_ECAM,
            pci.as_ptr(),
            SYSMAP_PCI_ECAM_BYTES,
        );
    }

    emit(QSOE_SYSMAP_TAG_END, core::ptr::null(), 0);
    write_header(S_LEN);

    S_READY = 1;
    0
}

/// Return the cached PSYS sysmap page.
///
/// # Safety
///
/// Non-null output pointers must be writable. The returned page pointer remains
/// valid until the next `tm_sysmap_build` call.
#[no_mangle]
pub unsafe extern "C" fn tm_sysmap_get(
    out_page: *mut *const c_void,
    out_len: *mut c_uint,
) -> c_int {
    if S_READY == 0 {
        return -1;
    }
    if !out_page.is_null() {
        *out_page = page_const_ptr().cast::<c_void>();
    }
    if !out_len.is_null() {
        *out_len = TM_SYSMAP_PAGE_BYTES as c_uint;
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::slice;
    use std::sync::{Mutex, MutexGuard};

    static mut SYSCFG_BUF: [u8; 512] = [0; 512];
    static mut SYSCFG_LEN: c_uint = 0;
    static mut SYSCFG_READY: c_int = 0;
    static TEST_LOCK: Mutex<()> = Mutex::new(());

    fn test_guard() -> MutexGuard<'static, ()> {
        TEST_LOCK.lock().expect("qsoe-tm-sysmap test lock poisoned")
    }

    unsafe fn syscfg_ptr() -> *mut u8 {
        core::ptr::addr_of_mut!(SYSCFG_BUF).cast::<u8>()
    }

    unsafe fn reset_syscfg() {
        let p = syscfg_ptr();
        let mut i = 0usize;
        while i < 512 {
            *p.add(i) = 0;
            i += 1;
        }
        SYSCFG_LEN = 0;
        SYSCFG_READY = 0;
    }

    unsafe fn emit_syscfg(id: u16, payload: &[u8]) {
        let p = syscfg_ptr();
        write_le16(p, SYSCFG_LEN, id);
        write_le16(p, SYSCFG_LEN.wrapping_add(2), payload.len() as u16);
        let mut i = 0usize;
        while i < payload.len() {
            *p.add(SYSCFG_LEN as usize + 4 + i) = payload[i];
            i += 1;
        }
        SYSCFG_LEN = SYSCFG_LEN.wrapping_add(4 + payload.len() as c_uint);
    }

    unsafe fn finish_syscfg() {
        emit_syscfg(TM_SYSCFG_TAG_END, &[]);
        SYSCFG_READY = 1;
    }

    #[no_mangle]
    pub unsafe extern "C" fn tm_syscfg_get(
        out_blob: *mut *const c_void,
        out_len: *mut c_uint,
    ) -> c_int {
        if SYSCFG_READY == 0 {
            return -1;
        }
        if !out_blob.is_null() {
            *out_blob = syscfg_ptr().cast::<c_void>();
        }
        if !out_len.is_null() {
            *out_len = SYSCFG_LEN;
        }
        0
    }

    #[no_mangle]
    pub unsafe extern "C" fn tm_syscfg_find(
        tag_id: c_uint,
        out_ptr: *mut *const c_void,
        out_len: *mut c_uint,
    ) -> c_int {
        if SYSCFG_READY == 0 {
            return -1;
        }
        let p = syscfg_ptr().cast::<u8>();
        let mut off = 0u32;
        while off.wrapping_add(4) <= SYSCFG_LEN {
            let id = read_le16(p, off);
            let len = u32::from(read_le16(p, off.wrapping_add(2)));
            if id == TM_SYSCFG_TAG_END {
                return -1;
            }
            if u32::from(id) == tag_id {
                if !out_ptr.is_null() {
                    *out_ptr = p.add(off.wrapping_add(4) as usize).cast::<c_void>();
                }
                if !out_len.is_null() {
                    *out_len = len;
                }
                return 0;
            }
            off = off.wrapping_add(4).wrapping_add(len);
        }
        -1
    }

    #[no_mangle]
    pub unsafe extern "C" fn tm_syscfg_find_u64(tag_id: c_uint, out: *mut u64) -> c_int {
        let mut ptr: *const c_void = core::ptr::null();
        let mut len = 0u32;
        if tm_syscfg_find(tag_id, &mut ptr, &mut len) != 0 || len != 8 {
            return -1;
        }
        *out = read_le64(ptr.cast::<u8>(), 0);
        0
    }

    #[no_mangle]
    pub unsafe extern "C" fn tm_syscfg_find_u32(tag_id: c_uint, out: *mut u32) -> c_int {
        let mut ptr: *const c_void = core::ptr::null();
        let mut len = 0u32;
        if tm_syscfg_find(tag_id, &mut ptr, &mut len) != 0 || len != 4 {
            return -1;
        }
        *out = read_le32(ptr.cast::<u8>(), 0);
        0
    }

    unsafe fn get_page() -> (&'static [u8], c_uint) {
        let mut ptr: *const c_void = core::ptr::null();
        let mut len = 0u32;
        assert_eq!(tm_sysmap_get(&mut ptr, &mut len), 0);
        (
            slice::from_raw_parts(ptr.cast::<u8>(), TM_SYSMAP_PAGE_BYTES),
            len,
        )
    }

    fn le16(b: &[u8], off: usize) -> u16 {
        u16::from_le_bytes([b[off], b[off + 1]])
    }

    fn le32(b: &[u8], off: usize) -> u32 {
        u32::from_le_bytes([b[off], b[off + 1], b[off + 2], b[off + 3]])
    }

    fn le64(b: &[u8], off: usize) -> u64 {
        u64::from_le_bytes([
            b[off],
            b[off + 1],
            b[off + 2],
            b[off + 3],
            b[off + 4],
            b[off + 5],
            b[off + 6],
            b[off + 7],
        ])
    }

    fn find_tlv(page: &[u8], tag: u16) -> Option<&[u8]> {
        let mut off = le16(page, 6) as usize;
        let end = le32(page, 8) as usize;
        while off + 4 <= end {
            let id = le16(page, off);
            let len = le16(page, off + 2) as usize;
            if id == QSOE_SYSMAP_TAG_END {
                return None;
            }
            if id == tag {
                return Some(&page[off + 4..off + 4 + len]);
            }
            off += (4 + len + 7) & !7;
        }
        None
    }

    #[test]
    fn get_before_build_fails() {
        let _guard = test_guard();
        unsafe {
            S_READY = 0;
            assert_eq!(
                tm_sysmap_get(core::ptr::null_mut(), core::ptr::null_mut()),
                -1
            );
        }
    }

    #[test]
    fn minimal_syscfg_builds_header_and_end() {
        let _guard = test_guard();
        unsafe {
            reset_syscfg();
            finish_syscfg();

            assert_eq!(tm_sysmap_build(), 0);
            let (page, len) = get_page();
            assert_eq!(len, TM_SYSMAP_PAGE_BYTES as c_uint);
            assert_eq!(le32(page, 0), QSOE_SYSMAP_MAGIC);
            assert_eq!(le16(page, 4), QSOE_SYSMAP_VERSION);
            assert_eq!(le16(page, 6), SYSMAP_HDR_BYTES as u16);
            assert_eq!(le32(page, 8), 24);
            assert_eq!(le16(page, SYSMAP_HDR_BYTES as usize), QSOE_SYSMAP_TAG_END);
        }
    }

    #[test]
    fn emits_timebase_plic_pci_and_designware_fields() {
        let _guard = test_guard();
        unsafe {
            reset_syscfg();
            emit_syscfg(
                TM_SYSCFG_TAG_TIMEBASE_HZ as u16,
                &10_000_000u64.to_le_bytes(),
            );
            emit_syscfg(TM_SYSCFG_TAG_NUM_CPUS as u16, &4u32.to_le_bytes());

            let mut ecam = Vec::new();
            ecam.extend_from_slice(&0x3000_0000u64.to_le_bytes());
            ecam.extend_from_slice(&0x1000_0000u64.to_le_bytes());
            ecam.extend_from_slice(&0x7fu32.to_le_bytes());
            emit_syscfg(TM_SYSCFG_TAG_PCI_ECAM as u16, &ecam);

            let mut prefetch_window = Vec::new();
            prefetch_window.extend_from_slice(&0x1111_0000u64.to_le_bytes());
            prefetch_window.extend_from_slice(&0x2222_0000u64.to_le_bytes());
            prefetch_window.extend_from_slice(&0x3333_0000u64.to_le_bytes());
            prefetch_window.extend_from_slice(
                &(TM_SYSCFG_PCI_WINDOW_MEM | TM_SYSCFG_PCI_WINDOW_PREFETCH).to_le_bytes(),
            );
            emit_syscfg(TM_SYSCFG_TAG_PCI_WINDOW, &prefetch_window);

            let mut mem_window = Vec::new();
            mem_window.extend_from_slice(&0x4000_0000u64.to_le_bytes());
            mem_window.extend_from_slice(&0x4000_0000u64.to_le_bytes());
            mem_window.extend_from_slice(&0x0400_0000u64.to_le_bytes());
            mem_window.extend_from_slice(&TM_SYSCFG_PCI_WINDOW_MEM.to_le_bytes());
            emit_syscfg(TM_SYSCFG_TAG_PCI_WINDOW, &mem_window);

            let mut dw = Vec::new();
            dw.extend_from_slice(&0x5000_0000u64.to_le_bytes());
            dw.extend_from_slice(&0x1000u64.to_le_bytes());
            dw.extend_from_slice(&33u32.to_le_bytes());
            emit_syscfg(TM_SYSCFG_TAG_DW_MSI as u16, &dw);
            finish_syscfg();

            assert_eq!(tm_sysmap_build(), 0);
            let (page, _) = get_page();
            assert_eq!(le32(page, 8), 176);

            let mtime = find_tlv(page, QSOE_SYSMAP_TAG_MTIME_FREQ).unwrap();
            assert_eq!(mtime.len(), SYSMAP_MTIME_FREQ_BYTES as usize);
            assert_eq!(le32(mtime, 0), 10_000_000);
            assert_eq!(le32(mtime, 4), 0);

            let plic = find_tlv(page, QSOE_SYSMAP_TAG_PLIC).unwrap();
            assert_eq!(plic.len(), SYSMAP_PLIC_BYTES as usize);
            assert_eq!(le32(plic, 20), 4);

            let pci = find_tlv(page, QSOE_SYSMAP_TAG_PCI_ECAM).unwrap();
            assert_eq!(pci.len(), SYSMAP_PCI_ECAM_BYTES as usize);
            assert_eq!(le64(pci, 0), 0x3000_0000);
            assert_eq!(le64(pci, 8), 0x1000_0000);
            assert_eq!(le64(pci, 16), 0x5000_0000);
            assert_eq!(le64(pci, 24), 0x1000);
            assert_eq!(pci[32], 0);
            assert_eq!(pci[33], 0x7f);
            assert_eq!(le32(pci, 36), 33);
            assert_eq!(le64(pci, 40), 0x4000_0000);
            assert_eq!(le64(pci, 48), 0x4000_0000);
            assert_eq!(le64(pci, 56), 0x0400_0000);
        }
    }
}
