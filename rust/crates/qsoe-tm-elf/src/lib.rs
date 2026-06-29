#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

use core::ffi::{c_char, c_int, c_uint, c_void};

const EI_CLASS: u64 = 4;
const EI_DATA: u64 = 5;
const ELFCLASS64: u8 = 2;
const ELFDATA2LSB: u8 = 1;
const ET_EXEC: u16 = 2;
const ET_DYN: u16 = 3;
const EM_RISCV: u16 = 243;
const PT_LOAD: u32 = 1;
const PT_INTERP: u32 = 3;
const ELF64_EHDR_LEN: u64 = 64;
const ELF64_PHDR_LEN: u16 = 56;
const TM_ELF_MAX_PHDRS: usize = 8;

const ELF_PROT_READ: u32 = 0x4;
const ELF_PROT_WRITE: u32 = 0x2;
const ELF_PROT_EXEC: u32 = 0x1;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct TmElfPhdr {
    pub file_offset: u64,
    pub file_size: u64,
    pub vaddr: u64,
    pub mem_size: u64,
    pub perms: u32,
    pub _pad: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TmElfView {
    pub blob: *const c_void,
    pub blob_size: u64,
    pub entry: u64,
    pub vaddr_lo: u64,
    pub vaddr_hi: u64,
    pub is_dyn: c_int,
    pub n_phdrs: c_uint,
    pub phdrs: [TmElfPhdr; TM_ELF_MAX_PHDRS],
    pub interp_path: *const c_char,
    pub interp_len: u64,
    pub phdr_off: u64,
    pub phdr_entsize: u16,
    pub phdr_count: u16,
}

impl Default for TmElfView {
    fn default() -> Self {
        Self {
            blob: core::ptr::null(),
            blob_size: 0,
            entry: 0,
            vaddr_lo: 0,
            vaddr_hi: 0,
            is_dyn: 0,
            n_phdrs: 0,
            phdrs: [TmElfPhdr::default(); TM_ELF_MAX_PHDRS],
            interp_path: core::ptr::null(),
            interp_len: 0,
            phdr_off: 0,
            phdr_entsize: 0,
            phdr_count: 0,
        }
    }
}

fn span_in_blob(off: u64, span: u64, blob_size: u64) -> bool {
    if span > blob_size {
        return false;
    }
    if off > blob_size - span {
        return false;
    }
    true
}

fn to_usize(value: u64) -> Option<usize> {
    let converted = value as usize;
    if converted as u64 == value {
        Some(converted)
    } else {
        None
    }
}

unsafe fn read_u8(base: *const u8, off: u64) -> Option<u8> {
    Some(*base.add(to_usize(off)?))
}

unsafe fn read_le16(base: *const u8, off: u64) -> Option<u16> {
    let b0 = u16::from(read_u8(base, off)?);
    let b1 = u16::from(read_u8(base, off + 1)?);
    Some(b0 | (b1 << 8))
}

unsafe fn read_le32(base: *const u8, off: u64) -> Option<u32> {
    let mut value = 0u32;
    let mut i = 0u64;
    while i < 4 {
        value |= u32::from(read_u8(base, off + i)?) << (i * 8);
        i += 1;
    }
    Some(value)
}

unsafe fn read_le64(base: *const u8, off: u64) -> Option<u64> {
    let mut value = 0u64;
    let mut i = 0u64;
    while i < 8 {
        value |= u64::from(read_u8(base, off + i)?) << (i * 8);
        i += 1;
    }
    Some(value)
}

/// Parse an ELF64 little-endian RISC-V image into the task-manager view ABI.
///
/// # Safety
///
/// `blob` must be readable for `blob_size` bytes. `out` must be a valid
/// writable `tm_elf_view_t` pointer when non-null. The returned view retains
/// pointers into `blob`, matching the C provider contract.
#[no_mangle]
pub unsafe extern "C" fn tm_elf_parse(
    blob: *const c_void,
    blob_size: u64,
    out: *mut TmElfView,
) -> c_int {
    if blob.is_null() || out.is_null() || blob_size < ELF64_EHDR_LEN {
        return -1;
    }

    let bp = blob.cast::<u8>();
    if read_u8(bp, 0) != Some(0x7f)
        || read_u8(bp, 1) != Some(b'E')
        || read_u8(bp, 2) != Some(b'L')
        || read_u8(bp, 3) != Some(b'F')
    {
        return -1;
    }
    if read_u8(bp, EI_CLASS) != Some(ELFCLASS64) {
        return -1;
    }
    if read_u8(bp, EI_DATA) != Some(ELFDATA2LSB) {
        return -1;
    }

    let Some(e_type) = read_le16(bp, 16) else {
        return -1;
    };
    let Some(e_machine) = read_le16(bp, 18) else {
        return -1;
    };
    let Some(e_entry) = read_le64(bp, 24) else {
        return -1;
    };
    let Some(e_phoff) = read_le64(bp, 32) else {
        return -1;
    };
    let Some(e_phentsize) = read_le16(bp, 54) else {
        return -1;
    };
    let Some(e_phnum) = read_le16(bp, 56) else {
        return -1;
    };

    if e_machine != EM_RISCV {
        return -1;
    }
    if e_type != ET_EXEC && e_type != ET_DYN {
        return -1;
    }
    if e_phentsize < ELF64_PHDR_LEN {
        return -1;
    }

    let pht_bytes = u64::from(e_phnum) * u64::from(e_phentsize);
    if !span_in_blob(e_phoff, pht_bytes, blob_size) {
        return -1;
    }

    (*out).blob = blob;
    (*out).blob_size = blob_size;
    (*out).entry = e_entry;
    (*out).is_dyn = if e_type == ET_DYN { 1 } else { 0 };
    (*out).vaddr_lo = u64::MAX;
    (*out).vaddr_hi = 0;
    (*out).n_phdrs = 0;
    (*out).interp_path = core::ptr::null();
    (*out).interp_len = 0;
    (*out).phdr_off = e_phoff;
    (*out).phdr_entsize = e_phentsize;
    (*out).phdr_count = e_phnum;

    let mut i = 0u16;
    while i < e_phnum {
        let ph = e_phoff + u64::from(i) * u64::from(e_phentsize);
        let Some(p_type) = read_le32(bp, ph) else {
            return -1;
        };
        let Some(p_flags) = read_le32(bp, ph + 4) else {
            return -1;
        };
        let Some(p_offset) = read_le64(bp, ph + 8) else {
            return -1;
        };
        let Some(p_vaddr) = read_le64(bp, ph + 16) else {
            return -1;
        };
        let Some(p_filesz) = read_le64(bp, ph + 32) else {
            return -1;
        };
        let Some(p_memsz) = read_le64(bp, ph + 40) else {
            return -1;
        };

        if p_type == PT_LOAD {
            if p_filesz > p_memsz {
                return -1;
            }
            if p_filesz != 0 && !span_in_blob(p_offset, p_filesz, blob_size) {
                return -1;
            }
            if (*out).n_phdrs as usize >= TM_ELF_MAX_PHDRS {
                return -1;
            }

            let slot = &mut (*out).phdrs[(*out).n_phdrs as usize];
            (*out).n_phdrs += 1;
            slot.file_offset = p_offset;
            slot.file_size = p_filesz;
            slot.vaddr = p_vaddr;
            slot.mem_size = p_memsz;
            slot.perms = p_flags & (ELF_PROT_READ | ELF_PROT_WRITE | ELF_PROT_EXEC);
            slot._pad = 0;

            let seg_lo = p_vaddr;
            let seg_hi = p_vaddr.wrapping_add(p_memsz);
            if seg_lo < (*out).vaddr_lo {
                (*out).vaddr_lo = seg_lo;
            }
            if seg_hi > (*out).vaddr_hi {
                (*out).vaddr_hi = seg_hi;
            }
        } else if p_type == PT_INTERP {
            if p_filesz == 0 {
                return -1;
            }
            if !span_in_blob(p_offset, p_filesz, blob_size) {
                return -1;
            }
            let Some(path_off) = to_usize(p_offset) else {
                return -1;
            };
            let s = bp.add(path_off).cast::<c_char>();
            let mut n = 0u64;
            while n < p_filesz && read_u8(bp, p_offset + n) != Some(0) {
                n += 1;
            }
            if n == p_filesz {
                return -1;
            }
            (*out).interp_path = s;
            (*out).interp_len = n;
        }

        i += 1;
    }

    if (*out).n_phdrs == 0 {
        return -1;
    }
    if (*out).vaddr_hi <= (*out).vaddr_lo {
        return -1;
    }
    0
}

#[cfg(test)]
mod tests {
    extern crate std;

    use super::*;
    use core::mem::{align_of, size_of, MaybeUninit};
    use core::ptr::addr_of;
    use std::vec::Vec;

    const PHDR_OFF: usize = 64;

    #[derive(Clone, Copy)]
    struct PhdrSpec {
        p_type: u32,
        p_flags: u32,
        p_offset: u64,
        p_vaddr: u64,
        p_filesz: u64,
        p_memsz: u64,
    }

    fn put_u16(bytes: &mut [u8], off: usize, value: u16) {
        bytes[off..off + 2].copy_from_slice(&value.to_le_bytes());
    }

    fn put_u32(bytes: &mut [u8], off: usize, value: u32) {
        bytes[off..off + 4].copy_from_slice(&value.to_le_bytes());
    }

    fn put_u64(bytes: &mut [u8], off: usize, value: u64) {
        bytes[off..off + 8].copy_from_slice(&value.to_le_bytes());
    }

    fn synthetic_elf(e_type: u16, phdrs: &[PhdrSpec]) -> Vec<u8> {
        let phdr_bytes = PHDR_OFF + phdrs.len() * ELF64_PHDR_LEN as usize;
        let mut len = phdr_bytes.max(0x300);
        for ph in phdrs {
            len = len.max((ph.p_offset + ph.p_filesz) as usize);
        }

        let mut bytes = vec![0u8; len];
        bytes[0..4].copy_from_slice(b"\x7fELF");
        bytes[EI_CLASS as usize] = ELFCLASS64;
        bytes[EI_DATA as usize] = ELFDATA2LSB;
        put_u16(&mut bytes, 16, e_type);
        put_u16(&mut bytes, 18, EM_RISCV);
        put_u32(&mut bytes, 20, 1);
        put_u64(&mut bytes, 24, 0x401000);
        put_u64(&mut bytes, 32, PHDR_OFF as u64);
        put_u16(&mut bytes, 52, ELF64_EHDR_LEN as u16);
        put_u16(&mut bytes, 54, ELF64_PHDR_LEN);
        put_u16(&mut bytes, 56, phdrs.len() as u16);

        for (idx, ph) in phdrs.iter().enumerate() {
            let off = PHDR_OFF + idx * ELF64_PHDR_LEN as usize;
            put_u32(&mut bytes, off, ph.p_type);
            put_u32(&mut bytes, off + 4, ph.p_flags);
            put_u64(&mut bytes, off + 8, ph.p_offset);
            put_u64(&mut bytes, off + 16, ph.p_vaddr);
            put_u64(&mut bytes, off + 32, ph.p_filesz);
            put_u64(&mut bytes, off + 40, ph.p_memsz);
            put_u64(&mut bytes, off + 48, 0x1000);
        }
        bytes
    }

    fn load_segment(vaddr: u64, filesz: u64, memsz: u64, flags: u32) -> PhdrSpec {
        PhdrSpec {
            p_type: PT_LOAD,
            p_flags: flags,
            p_offset: 0x200,
            p_vaddr: vaddr,
            p_filesz: filesz,
            p_memsz: memsz,
        }
    }

    fn parse(bytes: &[u8]) -> Result<TmElfView, c_int> {
        let mut out = TmElfView::default();
        let rc = unsafe {
            tm_elf_parse(
                bytes.as_ptr().cast::<c_void>(),
                bytes.len() as u64,
                &mut out,
            )
        };
        if rc == 0 {
            Ok(out)
        } else {
            Err(rc)
        }
    }

    fn field_offset<T>(f: unsafe fn(*const T) -> *const u8) -> usize {
        let uninit = MaybeUninit::<T>::uninit();
        let base = uninit.as_ptr() as usize;
        unsafe { f(uninit.as_ptr()) as usize - base }
    }

    unsafe fn view_blob(p: *const TmElfView) -> *const u8 {
        addr_of!((*p).blob).cast()
    }

    unsafe fn view_blob_size(p: *const TmElfView) -> *const u8 {
        addr_of!((*p).blob_size).cast()
    }

    unsafe fn view_entry(p: *const TmElfView) -> *const u8 {
        addr_of!((*p).entry).cast()
    }

    unsafe fn view_vaddr_lo(p: *const TmElfView) -> *const u8 {
        addr_of!((*p).vaddr_lo).cast()
    }

    unsafe fn view_vaddr_hi(p: *const TmElfView) -> *const u8 {
        addr_of!((*p).vaddr_hi).cast()
    }

    unsafe fn view_is_dyn(p: *const TmElfView) -> *const u8 {
        addr_of!((*p).is_dyn).cast()
    }

    unsafe fn view_n_phdrs(p: *const TmElfView) -> *const u8 {
        addr_of!((*p).n_phdrs).cast()
    }

    unsafe fn view_phdrs(p: *const TmElfView) -> *const u8 {
        addr_of!((*p).phdrs).cast()
    }

    unsafe fn view_interp_path(p: *const TmElfView) -> *const u8 {
        addr_of!((*p).interp_path).cast()
    }

    unsafe fn view_phdr_count(p: *const TmElfView) -> *const u8 {
        addr_of!((*p).phdr_count).cast()
    }

    #[test]
    fn c_abi_layout_matches_header_on_64_bit() {
        assert_eq!(size_of::<TmElfPhdr>(), 40);
        assert_eq!(align_of::<TmElfPhdr>(), 8);
        assert_eq!(size_of::<TmElfView>(), 400);
        assert_eq!(align_of::<TmElfView>(), 8);

        assert_eq!(field_offset::<TmElfView>(view_blob), 0);
        assert_eq!(field_offset::<TmElfView>(view_blob_size), 8);
        assert_eq!(field_offset::<TmElfView>(view_entry), 16);
        assert_eq!(field_offset::<TmElfView>(view_vaddr_lo), 24);
        assert_eq!(field_offset::<TmElfView>(view_vaddr_hi), 32);
        assert_eq!(field_offset::<TmElfView>(view_is_dyn), 40);
        assert_eq!(field_offset::<TmElfView>(view_n_phdrs), 44);
        assert_eq!(field_offset::<TmElfView>(view_phdrs), 48);
        assert_eq!(field_offset::<TmElfView>(view_interp_path), 368);
        assert_eq!(field_offset::<TmElfView>(view_phdr_count), 394);
    }

    #[test]
    fn parses_loads_interp_range_and_entry() {
        let mut bytes = synthetic_elf(
            ET_DYN,
            &[
                PhdrSpec {
                    p_type: PT_INTERP,
                    p_flags: 0,
                    p_offset: 0x180,
                    p_vaddr: 0,
                    p_filesz: 14,
                    p_memsz: 14,
                },
                load_segment(0x1000, 0x20, 0x40, ELF_PROT_READ | ELF_PROT_EXEC),
                load_segment(0x3000, 0x10, 0x80, ELF_PROT_READ | ELF_PROT_WRITE),
            ],
        );
        bytes[0x180..0x18d].copy_from_slice(b"/lib/ld.so.1\0");

        let view = parse(&bytes).expect("parse");
        assert_eq!(view.blob, bytes.as_ptr().cast::<c_void>());
        assert_eq!(view.blob_size, bytes.len() as u64);
        assert_eq!(view.entry, 0x401000);
        assert_eq!(view.is_dyn, 1);
        assert_eq!(view.n_phdrs, 2);
        assert_eq!(view.vaddr_lo, 0x1000);
        assert_eq!(view.vaddr_hi, 0x3080);
        assert_eq!(view.phdr_off, PHDR_OFF as u64);
        assert_eq!(view.phdr_entsize, ELF64_PHDR_LEN);
        assert_eq!(view.phdr_count, 3);
        assert_eq!(view.interp_len, 12);
        assert_eq!(view.interp_path, unsafe {
            bytes.as_ptr().add(0x180).cast::<c_char>()
        });
        assert_eq!(view.phdrs[0].file_offset, 0x200);
        assert_eq!(view.phdrs[0].file_size, 0x20);
        assert_eq!(view.phdrs[0].vaddr, 0x1000);
        assert_eq!(view.phdrs[0].mem_size, 0x40);
        assert_eq!(view.phdrs[0].perms, ELF_PROT_READ | ELF_PROT_EXEC);
        assert_eq!(view.phdrs[1].perms, ELF_PROT_READ | ELF_PROT_WRITE);
    }

    #[test]
    fn accepts_zero_file_size_load_without_file_span() {
        let bytes = synthetic_elf(
            ET_EXEC,
            &[PhdrSpec {
                p_type: PT_LOAD,
                p_flags: ELF_PROT_READ | ELF_PROT_WRITE,
                p_offset: 0xffff_ffff,
                p_vaddr: 0x8000,
                p_filesz: 0,
                p_memsz: 0x20,
            }],
        );
        let view = parse(&bytes).expect("parse");
        assert_eq!(view.is_dyn, 0);
        assert_eq!(view.n_phdrs, 1);
        assert_eq!(view.phdrs[0].file_offset, 0xffff_ffff);
    }

    #[test]
    fn rejects_malformed_inputs_like_c_provider() {
        let good = synthetic_elf(ET_EXEC, &[load_segment(0x1000, 0x10, 0x20, ELF_PROT_READ)]);

        let mut bad = good.clone();
        bad[0] = 0;
        assert!(matches!(parse(&bad), Err(-1)));

        let mut bad = good.clone();
        put_u16(&mut bad, 18, 62);
        assert!(matches!(parse(&bad), Err(-1)));

        let mut bad = good.clone();
        put_u16(&mut bad, 16, 1);
        assert!(matches!(parse(&bad), Err(-1)));

        let mut bad = good.clone();
        put_u16(&mut bad, 54, ELF64_PHDR_LEN - 1);
        assert!(matches!(parse(&bad), Err(-1)));

        let mut bad = good.clone();
        put_u64(&mut bad, 32, (good.len() + 1) as u64);
        assert!(matches!(parse(&bad), Err(-1)));

        let bad = synthetic_elf(ET_EXEC, &[load_segment(0x1000, 0x30, 0x20, ELF_PROT_READ)]);
        assert!(matches!(parse(&bad), Err(-1)));

        let bad = synthetic_elf(
            ET_EXEC,
            &[PhdrSpec {
                p_type: PT_INTERP,
                p_flags: 0,
                p_offset: 0x200,
                p_vaddr: 0,
                p_filesz: 4,
                p_memsz: 4,
            }],
        );
        assert!(matches!(parse(&bad), Err(-1)));
    }

    #[test]
    fn rejects_missing_load_and_too_many_loads() {
        let only_unknown = synthetic_elf(
            ET_EXEC,
            &[PhdrSpec {
                p_type: 0x6474_e550,
                p_flags: 0,
                p_offset: 0,
                p_vaddr: 0,
                p_filesz: 0,
                p_memsz: 0,
            }],
        );
        assert!(matches!(parse(&only_unknown), Err(-1)));

        let phdrs = [load_segment(0x1000, 1, 1, ELF_PROT_READ); TM_ELF_MAX_PHDRS + 1];
        assert!(matches!(parse(&synthetic_elf(ET_EXEC, &phdrs)), Err(-1)));
    }

    #[test]
    fn wrapped_segment_end_is_rejected_by_final_span_check() {
        let bytes = synthetic_elf(
            ET_EXEC,
            &[load_segment(u64::MAX - 0x10, 1, 0x40, ELF_PROT_READ)],
        );
        assert!(matches!(parse(&bytes), Err(-1)));
    }
}
