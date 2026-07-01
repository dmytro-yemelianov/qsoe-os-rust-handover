#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

use core::ffi::{c_char, c_int, c_uint, c_ulong, c_void};
use core::mem::size_of;

const TM_ELF_MAX_PHDRS: usize = 8;

const PT_DYNAMIC: u32 = 2;
const DT_NULL: i64 = 0;
const DT_HASH: i64 = 4;
const DT_STRTAB: i64 = 5;
const DT_SYMTAB: i64 = 6;
const DT_RELA: i64 = 7;
const DT_RELASZ: i64 = 8;
const DT_RELAENT: i64 = 9;
const DT_PLTRELSZ: i64 = 2;
const DT_JMPREL: i64 = 23;
const DT_GNU_HASH: i64 = 0x6fff_fef5;

const R_RISCV_64: u32 = 2;
const R_RISCV_RELATIVE: u32 = 3;
const R_RISCV_JUMP_SLOT: u32 = 5;

const MAX_DYN_ENTRIES: usize = 4096;

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

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TmRelocResolver {
    pub base: c_ulong,
    pub symtab: *const c_void,
    pub strtab: *const c_char,
    pub nsyms: c_ulong,
}

impl Default for TmRelocResolver {
    fn default() -> Self {
        Self {
            base: 0,
            symtab: core::ptr::null(),
            strtab: core::ptr::null(),
            nsyms: 0,
        }
    }
}

pub type TmRelocWriteQFn =
    Option<unsafe extern "C" fn(user: *mut c_void, vaddr: u64, value: u64) -> c_int>;
pub type TmRelocSkipLogFn = Option<unsafe extern "C" fn(user: *mut c_void, name: *const c_char)>;

#[repr(C)]
#[derive(Clone, Copy)]
struct Elf64Dyn {
    d_tag: i64,
    d_val: u64,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct Elf64Rela {
    r_offset: u64,
    r_info: u64,
    r_addend: i64,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct Elf64Sym {
    st_name: u32,
    st_info: u8,
    st_other: u8,
    st_shndx: u16,
    st_value: u64,
    st_size: u64,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct Elf64FilePhdr {
    p_type: u32,
    p_flags: u32,
    p_offset: u64,
    p_vaddr: u64,
    p_paddr: u64,
    p_filesz: u64,
    p_memsz: u64,
    p_align: u64,
}

fn to_usize(value: u64) -> Option<usize> {
    let converted = value as usize;
    if converted as u64 == value {
        Some(converted)
    } else {
        None
    }
}

fn span_in_blob(off: u64, span: u64, blob_size: u64) -> bool {
    span <= blob_size && off <= blob_size - span
}

unsafe fn read_unaligned<T: Copy>(ptr: *const T) -> T {
    core::ptr::read_unaligned(ptr)
}

unsafe fn va_to_blob(view: &TmElfView, bias: u64, vaddr: u64) -> Option<*const u8> {
    if view.blob.is_null() {
        return None;
    }

    let rel = vaddr.wrapping_sub(bias);
    let n_phdrs = (view.n_phdrs as usize).min(TM_ELF_MAX_PHDRS);
    let mut i = 0usize;
    while i < n_phdrs {
        let load = view.phdrs[i];
        let hi = load.vaddr.wrapping_add(load.file_size);
        if rel >= load.vaddr && rel < hi {
            let file_off = rel.wrapping_sub(load.vaddr).wrapping_add(load.file_offset);
            if file_off >= view.blob_size {
                return None;
            }
            return Some(view.blob.cast::<u8>().add(to_usize(file_off)?));
        }
        i += 1;
    }
    None
}

unsafe fn find_dynamic_in_blob(view: &TmElfView) -> Option<*const Elf64Dyn> {
    if view.blob.is_null() {
        return None;
    }
    let phdr_size = size_of::<Elf64FilePhdr>() as u64;
    let phdr_bytes = u64::from(view.phdr_count).checked_mul(phdr_size)?;
    if !span_in_blob(view.phdr_off, phdr_bytes, view.blob_size) {
        return None;
    }

    let base = view.blob.cast::<u8>();
    let phdrs = base.add(to_usize(view.phdr_off)?).cast::<Elf64FilePhdr>();
    let mut i = 0u16;
    while i < view.phdr_count {
        let phdr = read_unaligned(phdrs.add(i as usize));
        if phdr.p_type == PT_DYNAMIC {
            let end = phdr.p_offset.checked_add(phdr.p_filesz)?;
            if end > view.blob_size {
                return None;
            }
            return Some(base.add(to_usize(phdr.p_offset)?).cast::<Elf64Dyn>());
        }
        i += 1;
    }
    None
}

unsafe fn dyn_entry(dynp: *const Elf64Dyn, idx: usize) -> Elf64Dyn {
    read_unaligned(dynp.add(idx))
}

unsafe fn find_dyn_values(dynp: *const Elf64Dyn) -> (u64, u64, u64, u64, u64, u64, u64) {
    let mut rela_va = 0u64;
    let mut rela_sz = 0u64;
    let mut rela_ent = size_of::<Elf64Rela>() as u64;
    let mut jmprel_va = 0u64;
    let mut jmprel_sz = 0u64;
    let mut symtab_va = 0u64;
    let mut strtab_va = 0u64;

    let mut i = 0usize;
    while i < MAX_DYN_ENTRIES {
        let d = dyn_entry(dynp, i);
        if d.d_tag == DT_NULL {
            break;
        }
        match d.d_tag {
            DT_RELA => rela_va = d.d_val,
            DT_RELASZ => rela_sz = d.d_val,
            DT_RELAENT => rela_ent = d.d_val,
            DT_JMPREL => jmprel_va = d.d_val,
            DT_PLTRELSZ => jmprel_sz = d.d_val,
            DT_SYMTAB => symtab_va = d.d_val,
            DT_STRTAB => strtab_va = d.d_val,
            _ => {}
        }
        i += 1;
    }

    (
        rela_va, rela_sz, rela_ent, jmprel_va, jmprel_sz, symtab_va, strtab_va,
    )
}

unsafe fn derive_nsyms(dynp: *const Elf64Dyn, view: &TmElfView, bias: u64) -> c_ulong {
    let mut hash_va = 0u64;
    let mut gnu_hash_va = 0u64;

    let mut i = 0usize;
    while i < MAX_DYN_ENTRIES {
        let d = dyn_entry(dynp, i);
        if d.d_tag == DT_NULL {
            break;
        }
        if d.d_tag == DT_HASH {
            hash_va = d.d_val;
        }
        if d.d_tag == DT_GNU_HASH {
            gnu_hash_va = d.d_val;
        }
        i += 1;
    }

    if hash_va != 0 {
        let Some(h) = va_to_blob(view, bias, hash_va.wrapping_add(bias)) else {
            return 0;
        };
        let h = h.cast::<u32>();
        return read_unaligned(h.add(1)) as c_ulong;
    }

    if gnu_hash_va != 0 {
        let Some(hp) = va_to_blob(view, bias, gnu_hash_va.wrapping_add(bias)) else {
            return 0;
        };
        let h = hp.cast::<u32>();
        let nbuckets = read_unaligned(h.add(0));
        let symoffset = read_unaligned(h.add(1));
        let bloom_size = read_unaligned(h.add(2));
        let Some(bloom_bytes) = u64::from(bloom_size).checked_mul(8) else {
            return 0;
        };
        let buckets = hp.add((16u64 + bloom_bytes) as usize).cast::<u32>();
        let chain = buckets.add(nbuckets as usize);
        let mut max_bucket = 0u32;
        let mut b = 0u32;
        while b < nbuckets {
            let value = read_unaligned(buckets.add(b as usize));
            if value > max_bucket {
                max_bucket = value;
            }
            b += 1;
        }
        if max_bucket < symoffset {
            return symoffset as c_ulong;
        }
        let mut chain_idx = max_bucket - symoffset;
        while read_unaligned(chain.add(chain_idx as usize)) & 1 == 0 {
            chain_idx += 1;
        }
        return (max_bucket + (chain_idx - (max_bucket - symoffset)) + 1) as c_ulong;
    }

    0
}

unsafe fn c_streq(mut a: *const c_char, mut b: *const c_char) -> bool {
    loop {
        let ac = *a;
        let bc = *b;
        if ac == 0 || ac != bc {
            return ac == bc;
        }
        a = a.add(1);
        b = b.add(1);
    }
}

unsafe fn external_lookup(ext: *const TmRelocResolver, name: *const c_char) -> u64 {
    if ext.is_null() || name.is_null() {
        return 0;
    }
    let ext = &*ext;
    if ext.symtab.is_null() || ext.strtab.is_null() {
        return 0;
    }

    let symtab = ext.symtab.cast::<Elf64Sym>();
    let strtab = ext.strtab;
    let mut i = 1usize;
    while i < ext.nsyms as usize {
        let sym = read_unaligned(symtab.add(i));
        if sym.st_value != 0 {
            let sym_name = strtab.add(sym.st_name as usize);
            if c_streq(sym_name, name) {
                let base: u64 = ext.base;
                return base.wrapping_add(sym.st_value);
            }
        }
        i += 1;
    }
    0
}

struct RelaWalk<'a> {
    view: &'a TmElfView,
    bias: u64,
    symtab: *const Elf64Sym,
    strtab: *const c_char,
    ext: *const TmRelocResolver,
    write_cb: TmRelocWriteQFn,
    skip_log: TmRelocSkipLogFn,
    user: *mut c_void,
    applied: &'a mut c_ulong,
    total: &'a mut c_ulong,
    skipped: &'a mut c_ulong,
}

unsafe fn walk_rela(ctx: &mut RelaWalk<'_>, blob_va: u64, blob_sz: u64, entsize: u64) -> c_int {
    if blob_va == 0 || blob_sz == 0 {
        return 0;
    }
    if entsize == 0 {
        return -1;
    }
    let Some(rela_ptr) = va_to_blob(ctx.view, ctx.bias, blob_va.wrapping_add(ctx.bias)) else {
        return -1;
    };
    let rela = rela_ptr.cast::<Elf64Rela>();
    let n = blob_sz / entsize;
    *ctx.total = ctx.total.wrapping_add(n as c_ulong);

    let mut i = 0u64;
    while i < n {
        let r = read_unaligned(rela.add(i as usize));
        let r_type = (r.r_info & 0xffff_ffff) as u32;
        let sidx = (r.r_info >> 32) as usize;
        let loc_va = r.r_offset.wrapping_add(ctx.bias);
        let mut value = 0u64;
        let mut will_apply = true;

        match r_type {
            R_RISCV_RELATIVE => {
                value = (ctx.bias as i64).wrapping_add(r.r_addend) as u64;
            }
            R_RISCV_64 | R_RISCV_JUMP_SLOT => {
                if ctx.symtab.is_null() || ctx.strtab.is_null() {
                    will_apply = false;
                } else {
                    let sym = read_unaligned(ctx.symtab.add(sidx));
                    let name = ctx.strtab.add(sym.st_name as usize);
                    let mut resolved = 0u64;
                    if sym.st_shndx != 0 && sym.st_value != 0 {
                        resolved = sym.st_value.wrapping_add(ctx.bias);
                    } else if !ctx.ext.is_null() {
                        resolved = external_lookup(ctx.ext, name);
                    }
                    if resolved == 0 {
                        if let Some(log) = ctx.skip_log {
                            log(ctx.user, name);
                        }
                    } else {
                        value = resolved.wrapping_add(r.r_addend as u64);
                    }
                }
            }
            _ => {
                will_apply = false;
            }
        }

        if will_apply {
            let Some(write) = ctx.write_cb else {
                return -1;
            };
            if write(ctx.user, loc_va, value) != 0 {
                return -1;
            }
            *ctx.applied = ctx.applied.wrapping_add(1);
        } else {
            *ctx.skipped = ctx.skipped.wrapping_add(1);
        }

        i += 1;
    }

    0
}

/// Initializes a relocation resolver from a loaded ELF view.
///
/// # Safety
/// `view` and `out` must be valid for reads/writes for the duration of the
/// call, and `view` must describe an in-memory ELF image whose mapped bytes
/// remain accessible while the resolver is used.
#[no_mangle]
pub unsafe extern "C" fn tm_reloc_init_resolver(
    view: *const TmElfView,
    bias: c_ulong,
    out: *mut TmRelocResolver,
) -> c_int {
    if view.is_null() || out.is_null() {
        return -1;
    }
    let view = &*view;
    let Some(dynp) = find_dynamic_in_blob(view) else {
        return -1;
    };

    let (_, _, _, _, _, symtab_va, strtab_va) = find_dyn_values(dynp);
    if symtab_va == 0 || strtab_va == 0 {
        return -1;
    }

    let bias_u64: u64 = bias;
    let Some(symtab) = va_to_blob(view, bias_u64, symtab_va.wrapping_add(bias_u64)) else {
        return -1;
    };
    let Some(strtab) = va_to_blob(view, bias_u64, strtab_va.wrapping_add(bias_u64)) else {
        return -1;
    };

    let nsyms = derive_nsyms(dynp, view, bias_u64);
    if nsyms == 0 {
        return -1;
    }

    (*out).base = bias;
    (*out).symtab = symtab.cast::<c_void>();
    (*out).strtab = strtab.cast::<c_char>();
    (*out).nsyms = nsyms;
    0
}

/// Applies supported RISC-V RELA relocations to a loaded ELF view.
///
/// # Safety
/// `view` must be valid for reads, `ext` must either be null or point to a
/// resolver initialized from a compatible image, output counters must be null
/// or valid for writes, and `write_cb`/`skip_log` must uphold their callback
/// contracts for `user`.
#[no_mangle]
pub unsafe extern "C" fn tm_reloc_apply(
    view: *const TmElfView,
    bias: c_ulong,
    ext: *const TmRelocResolver,
    write_cb: TmRelocWriteQFn,
    skip_log: TmRelocSkipLogFn,
    user: *mut c_void,
    out_applied: *mut c_ulong,
    out_total: *mut c_ulong,
    out_skipped: *mut c_ulong,
) -> c_int {
    let mut applied: c_ulong = 0;
    let mut total: c_ulong = 0;
    let mut skipped: c_ulong = 0;
    let mut rc = 0;

    if view.is_null() {
        rc = -1;
    } else {
        let view = &*view;
        let bias_u64: u64 = bias;
        if let Some(dynp) = find_dynamic_in_blob(view) {
            let (rela_va, rela_sz, rela_ent, jmprel_va, jmprel_sz, symtab_va, strtab_va) =
                find_dyn_values(dynp);
            let symtab = if symtab_va != 0 {
                va_to_blob(view, bias_u64, symtab_va.wrapping_add(bias_u64))
                    .map_or(core::ptr::null(), |p| p.cast::<Elf64Sym>())
            } else {
                core::ptr::null()
            };
            let strtab = if strtab_va != 0 {
                va_to_blob(view, bias_u64, strtab_va.wrapping_add(bias_u64))
                    .map_or(core::ptr::null(), |p| p.cast::<c_char>())
            } else {
                core::ptr::null()
            };

            let mut ctx = RelaWalk {
                view,
                bias: bias_u64,
                symtab,
                strtab,
                ext,
                write_cb,
                skip_log,
                user,
                applied: &mut applied,
                total: &mut total,
                skipped: &mut skipped,
            };

            rc = walk_rela(&mut ctx, rela_va, rela_sz, rela_ent);
            if rc == 0 {
                rc = walk_rela(
                    &mut ctx,
                    jmprel_va,
                    jmprel_sz,
                    size_of::<Elf64Rela>() as u64,
                );
            }
        }
    }

    if !out_applied.is_null() {
        *out_applied = applied;
    }
    if !out_total.is_null() {
        *out_total = total;
    }
    if !out_skipped.is_null() {
        *out_skipped = skipped;
    }
    rc
}

#[cfg(test)]
mod tests {
    extern crate std;

    use super::*;
    use core::mem::{align_of, size_of, MaybeUninit};
    use core::ptr::addr_of;
    use std::vec::Vec;

    const ELF_PROT_READ: u32 = 0x4;
    const ELF_PROT_WRITE: u32 = 0x2;
    const BLOB_SIZE: usize = 4096;
    const PHDR_OFF: usize = 0x40;
    const DYN_OFF: usize = 0x200;
    const RELA_OFF: usize = 0x300;
    const JMPREL_OFF: usize = 0x400;
    const SYMTAB_OFF: usize = 0x500;
    const STRTAB_OFF: usize = 0x700;
    const HASH_OFF: usize = 0x900;
    const WRITE_BASE: u64 = 0x0a00;
    const TARGET_BIAS: c_ulong = 0x400000;
    const RESOLVER_BIAS: c_ulong = 0x800000;
    const R_RISCV_UNKNOWN: u32 = 99;

    #[derive(Clone, Copy, Debug, Default)]
    #[repr(C)]
    struct WriteRecord {
        vaddr: u64,
        value: u64,
    }

    #[repr(C)]
    struct FixtureState {
        writes: [WriteRecord; 8],
        write_count: usize,
        skip_name: [u8; 64],
        skip_count: usize,
    }

    impl Default for FixtureState {
        fn default() -> Self {
            Self {
                writes: [WriteRecord::default(); 8],
                write_count: 0,
                skip_name: [0; 64],
                skip_count: 0,
            }
        }
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

    fn put_i64(bytes: &mut [u8], off: usize, value: i64) {
        bytes[off..off + 8].copy_from_slice(&value.to_le_bytes());
    }

    fn put_dyn(bytes: &mut [u8], idx: usize, tag: i64, value: u64) {
        let off = DYN_OFF + idx * size_of::<Elf64Dyn>();
        put_i64(bytes, off, tag);
        put_u64(bytes, off + 8, value);
    }

    fn put_rela(bytes: &mut [u8], base: usize, idx: usize, offset: u64, info: u64, addend: i64) {
        let off = base + idx * size_of::<Elf64Rela>();
        put_u64(bytes, off, offset);
        put_u64(bytes, off + 8, info);
        put_i64(bytes, off + 16, addend);
    }

    fn put_sym(bytes: &mut [u8], idx: usize, name: u32, shndx: u16, value: u64) {
        let off = SYMTAB_OFF + idx * size_of::<Elf64Sym>();
        put_u32(bytes, off, name);
        bytes[off + 4] = 0;
        bytes[off + 5] = 0;
        put_u16(bytes, off + 6, shndx);
        put_u64(bytes, off + 8, value);
        put_u64(bytes, off + 16, 0);
    }

    fn put_string(bytes: &mut [u8], off: &mut u32, s: &[u8]) -> u32 {
        let start = *off;
        let pos = STRTAB_OFF + start as usize;
        bytes[pos..pos + s.len()].copy_from_slice(s);
        bytes[pos + s.len()] = 0;
        *off += s.len() as u32 + 1;
        start
    }

    fn r_info(sym: u32, r_type: u32) -> u64 {
        (u64::from(sym) << 32) | u64::from(r_type)
    }

    fn make_view() -> (Vec<u8>, TmElfView) {
        let mut bytes = vec![0u8; BLOB_SIZE];

        put_u32(&mut bytes, PHDR_OFF, PT_DYNAMIC);
        put_u64(&mut bytes, PHDR_OFF + 8, DYN_OFF as u64);
        put_u64(&mut bytes, PHDR_OFF + 32, 9 * size_of::<Elf64Dyn>() as u64);

        put_dyn(&mut bytes, 0, DT_RELA, RELA_OFF as u64);
        put_dyn(&mut bytes, 1, DT_RELASZ, 5 * size_of::<Elf64Rela>() as u64);
        put_dyn(&mut bytes, 2, DT_RELAENT, size_of::<Elf64Rela>() as u64);
        put_dyn(&mut bytes, 3, DT_JMPREL, JMPREL_OFF as u64);
        put_dyn(&mut bytes, 4, DT_PLTRELSZ, size_of::<Elf64Rela>() as u64);
        put_dyn(&mut bytes, 5, DT_SYMTAB, SYMTAB_OFF as u64);
        put_dyn(&mut bytes, 6, DT_STRTAB, STRTAB_OFF as u64);
        put_dyn(&mut bytes, 7, DT_HASH, HASH_OFF as u64);
        put_dyn(&mut bytes, 8, DT_NULL, 0);

        let mut str_off = 1u32;
        let local_name = put_string(&mut bytes, &mut str_off, b"local_func");
        let puts_name = put_string(&mut bytes, &mut str_off, b"puts");
        let missing_name = put_string(&mut bytes, &mut str_off, b"missing_symbol");

        put_sym(&mut bytes, 1, local_name, 1, 0x1234);
        put_sym(&mut bytes, 2, puts_name, 0, 0x5678);
        put_sym(&mut bytes, 3, missing_name, 0, 0);

        put_u32(&mut bytes, HASH_OFF, 1);
        put_u32(&mut bytes, HASH_OFF + 4, 4);

        put_rela(
            &mut bytes,
            RELA_OFF,
            0,
            WRITE_BASE,
            r_info(0, R_RISCV_RELATIVE),
            0x33,
        );
        put_rela(
            &mut bytes,
            RELA_OFF,
            1,
            WRITE_BASE + 0x08,
            r_info(1, R_RISCV_64),
            7,
        );
        put_rela(
            &mut bytes,
            RELA_OFF,
            2,
            WRITE_BASE + 0x10,
            r_info(2, R_RISCV_64),
            9,
        );
        put_rela(
            &mut bytes,
            RELA_OFF,
            3,
            WRITE_BASE + 0x18,
            r_info(3, R_RISCV_64),
            0,
        );
        put_rela(
            &mut bytes,
            RELA_OFF,
            4,
            WRITE_BASE + 0x20,
            r_info(0, R_RISCV_UNKNOWN),
            0,
        );
        put_rela(
            &mut bytes,
            JMPREL_OFF,
            0,
            WRITE_BASE + 0x28,
            r_info(2, R_RISCV_JUMP_SLOT),
            11,
        );

        let view = TmElfView {
            blob: bytes.as_ptr().cast::<c_void>(),
            blob_size: bytes.len() as u64,
            entry: 0,
            vaddr_lo: 0,
            vaddr_hi: bytes.len() as u64,
            is_dyn: 1,
            n_phdrs: 1,
            phdrs: {
                let mut phdrs = [TmElfPhdr::default(); TM_ELF_MAX_PHDRS];
                phdrs[0] = TmElfPhdr {
                    file_offset: 0,
                    file_size: bytes.len() as u64,
                    vaddr: 0,
                    mem_size: bytes.len() as u64,
                    perms: ELF_PROT_READ | ELF_PROT_WRITE,
                    _pad: 0,
                };
                phdrs
            },
            interp_path: core::ptr::null(),
            interp_len: 0,
            phdr_off: PHDR_OFF as u64,
            phdr_entsize: size_of::<Elf64FilePhdr>() as u16,
            phdr_count: 1,
        };
        (bytes, view)
    }

    unsafe extern "C" fn write_q(user: *mut c_void, vaddr: u64, value: u64) -> c_int {
        let state = &mut *(user.cast::<FixtureState>());
        assert!(state.write_count < state.writes.len());
        state.writes[state.write_count] = WriteRecord { vaddr, value };
        state.write_count += 1;
        0
    }

    unsafe extern "C" fn skip_log(user: *mut c_void, name: *const c_char) {
        let state = &mut *(user.cast::<FixtureState>());
        state.skip_count += 1;
        let mut i = 0usize;
        while i + 1 < state.skip_name.len() {
            let b = *(name.cast::<u8>().add(i));
            state.skip_name[i] = b;
            if b == 0 {
                return;
            }
            i += 1;
        }
        state.skip_name[state.skip_name.len() - 1] = 0;
    }

    fn find_write(state: &FixtureState, vaddr: u64) -> Option<u64> {
        let mut i = 0usize;
        while i < state.write_count {
            if state.writes[i].vaddr == vaddr {
                return Some(state.writes[i].value);
            }
            i += 1;
        }
        None
    }

    fn expect_write(state: &FixtureState, off: u64, expected: u64) {
        assert_eq!(find_write(state, TARGET_BIAS as u64 + off), Some(expected));
    }

    fn field_offset<T>(f: unsafe fn(*const T) -> *const u8) -> usize {
        let uninit = MaybeUninit::<T>::uninit();
        let base = uninit.as_ptr() as usize;
        unsafe { f(uninit.as_ptr()) as usize - base }
    }

    unsafe fn resolver_base(p: *const TmRelocResolver) -> *const u8 {
        addr_of!((*p).base).cast()
    }

    unsafe fn resolver_symtab(p: *const TmRelocResolver) -> *const u8 {
        addr_of!((*p).symtab).cast()
    }

    unsafe fn resolver_strtab(p: *const TmRelocResolver) -> *const u8 {
        addr_of!((*p).strtab).cast()
    }

    unsafe fn resolver_nsyms(p: *const TmRelocResolver) -> *const u8 {
        addr_of!((*p).nsyms).cast()
    }

    #[test]
    fn resolver_abi_layout_matches_header_on_64_bit() {
        assert_eq!(size_of::<TmRelocResolver>(), 32);
        assert_eq!(align_of::<TmRelocResolver>(), 8);
        assert_eq!(field_offset::<TmRelocResolver>(resolver_base), 0);
        assert_eq!(field_offset::<TmRelocResolver>(resolver_symtab), 8);
        assert_eq!(field_offset::<TmRelocResolver>(resolver_strtab), 16);
        assert_eq!(field_offset::<TmRelocResolver>(resolver_nsyms), 24);
    }

    #[test]
    fn applies_same_relocations_as_c_fixture() {
        let (_bytes, view) = make_view();
        let mut resolver = TmRelocResolver::default();
        let init_rc = unsafe { tm_reloc_init_resolver(&view, RESOLVER_BIAS, &mut resolver) };
        assert_eq!(init_rc, 0);
        assert_eq!(resolver.base, RESOLVER_BIAS);
        assert_eq!(resolver.nsyms, 4);

        let mut state = FixtureState::default();
        let mut applied = 0 as c_ulong;
        let mut total = 0 as c_ulong;
        let mut skipped = 0 as c_ulong;
        let rc = unsafe {
            tm_reloc_apply(
                &view,
                TARGET_BIAS,
                &resolver,
                Some(write_q),
                Some(skip_log),
                (&mut state as *mut FixtureState).cast::<c_void>(),
                &mut applied,
                &mut total,
                &mut skipped,
            )
        };

        assert_eq!(rc, 0);
        assert_eq!(total, 6);
        assert_eq!(applied, 5);
        assert_eq!(skipped, 1);
        assert_eq!(state.write_count, 5);
        assert_eq!(state.skip_count, 1);
        assert_eq!(&state.skip_name[..15], b"missing_symbol\0");

        expect_write(&state, WRITE_BASE, TARGET_BIAS as u64 + 0x33);
        expect_write(&state, WRITE_BASE + 0x08, TARGET_BIAS as u64 + 0x1234 + 7);
        expect_write(&state, WRITE_BASE + 0x10, RESOLVER_BIAS as u64 + 0x5678 + 9);
        expect_write(&state, WRITE_BASE + 0x18, 0);
        expect_write(
            &state,
            WRITE_BASE + 0x28,
            RESOLVER_BIAS as u64 + 0x5678 + 11,
        );
        assert_eq!(
            find_write(&state, TARGET_BIAS as u64 + WRITE_BASE + 0x20),
            None
        );
    }

    #[test]
    fn missing_dynamic_succeeds_with_zero_counts() {
        let bytes = vec![0u8; 128];
        let view = TmElfView {
            blob: bytes.as_ptr().cast::<c_void>(),
            blob_size: bytes.len() as u64,
            ..TmElfView::default()
        };
        let mut applied = 99 as c_ulong;
        let mut total = 99 as c_ulong;
        let mut skipped = 99 as c_ulong;
        let rc = unsafe {
            tm_reloc_apply(
                &view,
                0,
                core::ptr::null(),
                Some(write_q),
                None,
                core::ptr::null_mut(),
                &mut applied,
                &mut total,
                &mut skipped,
            )
        };
        assert_eq!(rc, 0);
        assert_eq!(applied, 0);
        assert_eq!(total, 0);
        assert_eq!(skipped, 0);
    }
}
