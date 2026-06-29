#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

use core::ffi::{c_char, c_int, c_uint, c_void};

const TM_FDT_MAGIC: u32 = 0xd00dfeed;

const FDT_BEGIN_NODE: u32 = 1;
const FDT_END_NODE: u32 = 2;
const FDT_PROP: u32 = 3;
const FDT_NOP: u32 = 4;
const FDT_END: u32 = 9;

const HEADER_TOTALSIZE: usize = 4;
const HEADER_OFF_DT_STRUCT: usize = 8;
const HEADER_OFF_DT_STRINGS: usize = 12;
const HEADER_LAST_COMP_VERSION: usize = 24;

fn align4(value: c_uint) -> c_uint {
    value.wrapping_add(3) & !3
}

unsafe fn read_u8(base: *const u8, off: usize) -> u8 {
    *base.add(off)
}

unsafe fn read_be32(base: *const u8, off: usize) -> u32 {
    (u32::from(read_u8(base, off)) << 24)
        | (u32::from(read_u8(base, off + 1)) << 16)
        | (u32::from(read_u8(base, off + 2)) << 8)
        | u32::from(read_u8(base, off + 3))
}

unsafe fn header_be32(blob: *const c_void, off: usize) -> u32 {
    read_be32(blob.cast::<u8>(), off)
}

unsafe fn struct_base(blob: *const c_void) -> *const u8 {
    blob.cast::<u8>()
        .add(header_be32(blob, HEADER_OFF_DT_STRUCT) as usize)
}

unsafe fn strings_base(blob: *const c_void) -> *const c_char {
    blob.cast::<u8>()
        .add(header_be32(blob, HEADER_OFF_DT_STRINGS) as usize)
        .cast::<c_char>()
}

unsafe fn struct_be32(blob: *const c_void, off: c_int) -> u32 {
    read_be32(struct_base(blob), off as usize)
}

unsafe fn c_strlen(s: *const c_char) -> c_uint {
    let mut n = 0u32;
    while *s.add(n as usize) != 0 {
        n = n.wrapping_add(1);
    }
    n
}

unsafe fn c_streq(mut a: *const c_char, mut b: *const c_char) -> bool {
    while *a != 0 && *b != 0 {
        if *a != *b {
            return false;
        }
        a = a.add(1);
        b = b.add(1);
    }
    *a == *b
}

unsafe fn c_streqn(a: *const c_char, b: *const c_char, n: c_uint) -> bool {
    let mut i = 0u32;
    while i < n {
        let ai = *a.add(i as usize);
        let bi = *b.add(i as usize);
        if ai != bi {
            return false;
        }
        if ai == 0 {
            return true;
        }
        i += 1;
    }
    true
}

unsafe fn step_token(blob: *const c_void, off: c_int, out_tok: *mut c_int) -> c_int {
    let base = struct_base(blob);
    let tok = struct_be32(blob, off);
    if !out_tok.is_null() {
        *out_tok = tok as c_int;
    }

    match tok {
        FDT_BEGIN_NODE => {
            let name = base.add(off as usize + 4).cast::<c_char>();
            let nlen = c_strlen(name).wrapping_add(1);
            off.wrapping_add(4).wrapping_add(align4(nlen) as c_int)
        }
        FDT_END_NODE | FDT_NOP => off.wrapping_add(4),
        FDT_PROP => {
            let plen = struct_be32(blob, off.wrapping_add(4));
            off.wrapping_add(12).wrapping_add(align4(plen) as c_int)
        }
        FDT_END => -1,
        _ => -1,
    }
}

unsafe fn find_child_node(
    blob: *const c_void,
    parent_off: c_int,
    comp: *const c_char,
    comp_len: c_uint,
) -> c_int {
    let base = struct_base(blob);
    let mut off = step_token(blob, parent_off, core::ptr::null_mut());
    let mut depth = 1;

    while off >= 0 {
        let tok = read_be32(base, off as usize);
        match tok {
            FDT_BEGIN_NODE => {
                if depth == 1 {
                    let name = base.add(off as usize + 4).cast::<c_char>();
                    let next = *name.add(comp_len as usize);
                    if c_streqn(name, comp, comp_len) && (next == 0 || next == b'@' as c_char) {
                        return off;
                    }
                }
                depth += 1;
                let mut stepped = 0;
                off = step_token(blob, off, &mut stepped);
            }
            FDT_END_NODE => {
                depth -= 1;
                if depth == 0 {
                    return -1;
                }
                let mut stepped = 0;
                off = step_token(blob, off, &mut stepped);
            }
            FDT_PROP | FDT_NOP => {
                let mut stepped = 0;
                off = step_token(blob, off, &mut stepped);
            }
            FDT_END => return -1,
            _ => return -1,
        }
    }
    -1
}

/// Validate the minimal FDT header fields consumed by taskman.
///
/// # Safety
///
/// `blob` must be readable as an FDT header when non-null.
#[no_mangle]
pub unsafe extern "C" fn tm_fdt_check(blob: *const c_void) -> c_int {
    if blob.is_null() {
        return -1;
    }
    if header_be32(blob, 0) != TM_FDT_MAGIC {
        return -1;
    }
    if header_be32(blob, HEADER_LAST_COMP_VERSION) > 17 {
        return -1;
    }
    0
}

/// Return the FDT total size header field, or zero for an invalid header.
///
/// # Safety
///
/// `blob` must be readable as an FDT header when non-null.
#[no_mangle]
pub unsafe extern "C" fn tm_fdt_size(blob: *const c_void) -> c_uint {
    if tm_fdt_check(blob) != 0 {
        return 0;
    }
    header_be32(blob, HEADER_TOTALSIZE) as c_uint
}

/// Find a node by absolute path and return its structure-block offset.
///
/// # Safety
///
/// `blob` must point to a readable FDT blob. `path` must point to a readable
/// NUL-terminated C string when non-null.
#[no_mangle]
pub unsafe extern "C" fn tm_fdt_path(blob: *const c_void, path: *const c_char) -> c_int {
    if tm_fdt_check(blob) != 0 {
        return -1;
    }
    if path.is_null() || *path != b'/' as c_char {
        return -1;
    }

    let base = struct_base(blob);
    let mut off = 0;
    while read_be32(base, off as usize) == FDT_NOP {
        off += 4;
    }
    if read_be32(base, off as usize) != FDT_BEGIN_NODE {
        return -1;
    }
    let mut node = off;

    let mut p = path.add(1);
    if *p == 0 {
        return node;
    }

    while *p != 0 {
        let start = p;
        while *p != 0 && *p != b'/' as c_char {
            p = p.add(1);
        }
        let len = p.offset_from(start) as c_uint;
        node = find_child_node(blob, node, start, len);
        if node < 0 {
            return -1;
        }
        if *p == b'/' as c_char {
            p = p.add(1);
        }
    }
    node
}

/// Get a raw property value from a node.
///
/// # Safety
///
/// `blob` must point to a readable FDT blob. `name` must point to a readable
/// NUL-terminated C string. Output pointers may be null; non-null output
/// pointers must be writable.
#[no_mangle]
pub unsafe extern "C" fn tm_fdt_prop(
    blob: *const c_void,
    node: c_int,
    name: *const c_char,
    out_ptr: *mut *const c_void,
    out_len: *mut c_uint,
) -> c_int {
    if tm_fdt_check(blob) != 0 || node < 0 {
        return -1;
    }

    let base = struct_base(blob);
    let strings = strings_base(blob);
    let mut off = step_token(blob, node, core::ptr::null_mut());
    let mut depth = 1;

    while off >= 0 {
        let tok = read_be32(base, off as usize);
        if tok == FDT_PROP && depth == 1 {
            let plen = read_be32(base, off as usize + 4);
            let nameoff = read_be32(base, off as usize + 8);
            let pname = strings.add(nameoff as usize);
            if c_streq(pname, name) {
                if !out_ptr.is_null() {
                    *out_ptr = base.add(off as usize + 12).cast::<c_void>();
                }
                if !out_len.is_null() {
                    *out_len = plen as c_uint;
                }
                return 0;
            }
            off = step_token(blob, off, core::ptr::null_mut());
        } else if tok == FDT_BEGIN_NODE {
            depth += 1;
            off = step_token(blob, off, core::ptr::null_mut());
        } else if tok == FDT_END_NODE {
            depth -= 1;
            if depth == 0 {
                return -1;
            }
            off = step_token(blob, off, core::ptr::null_mut());
        } else if tok == FDT_NOP {
            off += 4;
        } else {
            return -1;
        }
    }
    -1
}

/// Decode a big-endian u32 property.
///
/// # Safety
///
/// Pointer rules match `tm_fdt_prop`. `out` must be writable on success.
#[no_mangle]
pub unsafe extern "C" fn tm_fdt_prop_u32(
    blob: *const c_void,
    node: c_int,
    name: *const c_char,
    out: *mut u32,
) -> c_int {
    let mut ptr: *const c_void = core::ptr::null();
    let mut len = 0;
    if tm_fdt_prop(blob, node, name, &mut ptr, &mut len) != 0 {
        return -1;
    }
    if len != 4 {
        return -1;
    }
    *out = read_be32(ptr.cast::<u8>(), 0);
    0
}

/// Decode a big-endian u64 property.
///
/// # Safety
///
/// Pointer rules match `tm_fdt_prop`. `out` must be writable on success.
#[no_mangle]
pub unsafe extern "C" fn tm_fdt_prop_u64(
    blob: *const c_void,
    node: c_int,
    name: *const c_char,
    out: *mut u64,
) -> c_int {
    let mut ptr: *const c_void = core::ptr::null();
    let mut len = 0;
    if tm_fdt_prop(blob, node, name, &mut ptr, &mut len) != 0 {
        return -1;
    }
    if len != 8 {
        return -1;
    }

    let bp = ptr.cast::<u8>();
    let mut value = 0u64;
    let mut i = 0usize;
    while i < 8 {
        value = (value << 8) | u64::from(read_u8(bp, i));
        i += 1;
    }
    *out = value;
    0
}

/// Return a NUL-terminated string property pointer into the FDT blob.
///
/// # Safety
///
/// Pointer rules match `tm_fdt_prop`. `out_str` must be writable when the
/// property contains a NUL byte.
#[no_mangle]
pub unsafe extern "C" fn tm_fdt_prop_str(
    blob: *const c_void,
    node: c_int,
    name: *const c_char,
    out_str: *mut *const c_char,
) -> c_int {
    let mut ptr: *const c_void = core::ptr::null();
    let mut len = 0;
    if tm_fdt_prop(blob, node, name, &mut ptr, &mut len) != 0 {
        return -1;
    }

    let s = ptr.cast::<c_char>();
    let mut i = 0u32;
    while i < len {
        if *s.add(i as usize) == 0 {
            *out_str = s;
            return 0;
        }
        i += 1;
    }
    -1
}

/// Find the first node with a matching `compatible` string.
///
/// # Safety
///
/// `blob` must point to a readable FDT blob. `compat` must point to a readable
/// NUL-terminated C string when non-null.
#[no_mangle]
pub unsafe extern "C" fn tm_fdt_compatible(blob: *const c_void, compat: *const c_char) -> c_int {
    if tm_fdt_check(blob) != 0 || compat.is_null() {
        return -1;
    }

    let base = struct_base(blob);
    let mut off = 0;
    while read_be32(base, off as usize) == FDT_NOP {
        off += 4;
    }
    if read_be32(base, off as usize) != FDT_BEGIN_NODE {
        return -1;
    }

    let mut depth = 0;
    while off >= 0 {
        let tok = read_be32(base, off as usize);
        if tok == FDT_BEGIN_NODE {
            let node = off;
            depth += 1;
            let mut ptr: *const c_void = core::ptr::null();
            let mut len = 0;
            if tm_fdt_prop(blob, node, c"compatible".as_ptr(), &mut ptr, &mut len) == 0 {
                let s = ptr.cast::<c_char>();
                let mut i = 0u32;
                while i < len {
                    if c_streq(s.add(i as usize), compat) {
                        return node;
                    }
                    while i < len && *s.add(i as usize) != 0 {
                        i += 1;
                    }
                    i += 1;
                }
            }
            off = step_token(blob, off, core::ptr::null_mut());
        } else if tok == FDT_END_NODE {
            depth -= 1;
            off = step_token(blob, off, core::ptr::null_mut());
            if depth == 0 {
                return -1;
            }
        } else if tok == FDT_PROP {
            off = step_token(blob, off, core::ptr::null_mut());
        } else if tok == FDT_NOP {
            off += 4;
        } else {
            return -1;
        }
    }
    -1
}

/// Decode the indexed `(base, size)` tuple from a node's `reg` property.
///
/// # Safety
///
/// Pointer rules match `tm_fdt_prop`. Non-null output pointers must be
/// writable.
#[no_mangle]
pub unsafe extern "C" fn tm_fdt_reg(
    blob: *const c_void,
    node: c_int,
    addr_cells: c_uint,
    size_cells: c_uint,
    idx: c_uint,
    out_base: *mut u64,
    out_size: *mut u64,
) -> c_int {
    let mut ptr: *const c_void = core::ptr::null();
    let mut len = 0;
    if tm_fdt_prop(blob, node, c"reg".as_ptr(), &mut ptr, &mut len) != 0 {
        return -1;
    }

    let tuple_words = addr_cells.wrapping_add(size_cells);
    if tuple_words == 0 {
        return -1;
    }
    let tuple_bytes = tuple_words.wrapping_mul(4);
    if idx.wrapping_add(1).wrapping_mul(tuple_bytes) > len {
        return -1;
    }

    let mut bp = ptr.cast::<u8>().add(idx.wrapping_mul(tuple_bytes) as usize);

    let mut base = 0u64;
    let mut i = 0u32;
    while i < addr_cells.wrapping_mul(4) {
        base = (base << 8) | u64::from(read_u8(bp, i as usize));
        i += 1;
    }

    let mut size = 0u64;
    bp = bp.add(addr_cells.wrapping_mul(4) as usize);
    i = 0;
    while i < size_cells.wrapping_mul(4) {
        size = (size << 8) | u64::from(read_u8(bp, i as usize));
        i += 1;
    }

    if !out_base.is_null() {
        *out_base = base;
    }
    if !out_size.is_null() {
        *out_size = size;
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    fn push_be32(buf: &mut Vec<u8>, value: u32) {
        buf.extend_from_slice(&value.to_be_bytes());
    }

    fn align_vec4(buf: &mut Vec<u8>) {
        while buf.len() % 4 != 0 {
            buf.push(0);
        }
    }

    fn string_off(strings: &mut Vec<u8>, name: &str) -> u32 {
        let off = strings.len() as u32;
        strings.extend_from_slice(name.as_bytes());
        strings.push(0);
        off
    }

    fn begin_node(struc: &mut Vec<u8>, name: &str) {
        push_be32(struc, FDT_BEGIN_NODE);
        struc.extend_from_slice(name.as_bytes());
        struc.push(0);
        align_vec4(struc);
    }

    fn end_node(struc: &mut Vec<u8>) {
        push_be32(struc, FDT_END_NODE);
    }

    fn prop(struc: &mut Vec<u8>, strings: &mut Vec<u8>, name: &str, value: &[u8]) {
        let nameoff = string_off(strings, name);
        push_be32(struc, FDT_PROP);
        push_be32(struc, value.len() as u32);
        push_be32(struc, nameoff);
        struc.extend_from_slice(value);
        align_vec4(struc);
    }

    fn build_blob(last_comp_version: u32) -> Vec<u8> {
        let mut struc = Vec::new();
        let mut strings = Vec::new();

        push_be32(&mut struc, FDT_NOP);
        begin_node(&mut struc, "");
        prop(&mut struc, &mut strings, "model", b"qsoe-model\0");
        prop(
            &mut struc,
            &mut strings,
            "compatible",
            b"qsoe,virt\0riscv-virtio\0",
        );
        prop(&mut struc, &mut strings, "badstr", b"abc");

        begin_node(&mut struc, "chosen");
        prop(&mut struc, &mut strings, "bootargs", b"root=/dev/vda\0");
        prop(&mut struc, &mut strings, "boot-hartid", &2u32.to_be_bytes());
        end_node(&mut struc);

        begin_node(&mut struc, "cpus");
        prop(
            &mut struc,
            &mut strings,
            "timebase-frequency",
            &10_000_000u32.to_be_bytes(),
        );
        begin_node(&mut struc, "cpu@0");
        prop(&mut struc, &mut strings, "device_type", b"cpu\0");
        end_node(&mut struc);
        begin_node(&mut struc, "cpu@1");
        prop(&mut struc, &mut strings, "device_type", b"cpu\0");
        end_node(&mut struc);
        end_node(&mut struc);

        begin_node(&mut struc, "memory@80000000");
        let mut reg = Vec::new();
        reg.extend_from_slice(&0u32.to_be_bytes());
        reg.extend_from_slice(&0x8000_0000u32.to_be_bytes());
        reg.extend_from_slice(&0u32.to_be_bytes());
        reg.extend_from_slice(&0x0800_0000u32.to_be_bytes());
        prop(&mut struc, &mut strings, "reg", &reg);
        end_node(&mut struc);

        begin_node(&mut struc, "soc");
        begin_node(&mut struc, "pci@30000000");
        prop(
            &mut struc,
            &mut strings,
            "compatible",
            b"pci-host-ecam-generic\0other\0",
        );
        end_node(&mut struc);
        end_node(&mut struc);

        end_node(&mut struc);
        push_be32(&mut struc, FDT_END);

        let off_dt_struct = 40u32;
        let off_dt_strings = off_dt_struct + struc.len() as u32;
        let totalsize = off_dt_strings + strings.len() as u32;

        let mut blob = Vec::new();
        push_be32(&mut blob, TM_FDT_MAGIC);
        push_be32(&mut blob, totalsize);
        push_be32(&mut blob, off_dt_struct);
        push_be32(&mut blob, off_dt_strings);
        push_be32(&mut blob, 0);
        push_be32(&mut blob, 17);
        push_be32(&mut blob, last_comp_version);
        push_be32(&mut blob, 0);
        push_be32(&mut blob, strings.len() as u32);
        push_be32(&mut blob, struc.len() as u32);
        blob.extend_from_slice(&struc);
        blob.extend_from_slice(&strings);
        blob
    }

    #[test]
    fn check_size_and_header_rejection() {
        let mut blob = build_blob(16);
        unsafe {
            assert_eq!(tm_fdt_check(blob.as_ptr().cast::<c_void>()), 0);
            assert_eq!(
                tm_fdt_size(blob.as_ptr().cast::<c_void>()),
                blob.len() as c_uint
            );
            assert_eq!(tm_fdt_check(core::ptr::null()), -1);
            blob[0] = 0;
            assert_eq!(tm_fdt_check(blob.as_ptr().cast::<c_void>()), -1);
            assert_eq!(tm_fdt_size(blob.as_ptr().cast::<c_void>()), 0);
        }

        let blob = build_blob(18);
        unsafe {
            assert_eq!(tm_fdt_check(blob.as_ptr().cast::<c_void>()), -1);
        }
    }

    #[test]
    fn paths_and_properties() {
        let blob = build_blob(16);
        let bp = blob.as_ptr().cast::<c_void>();
        unsafe {
            let root = tm_fdt_path(bp, c"/".as_ptr());
            let chosen = tm_fdt_path(bp, c"/chosen".as_ptr());
            let cpu1 = tm_fdt_path(bp, c"/cpus/cpu@1".as_ptr());
            let memory = tm_fdt_path(bp, c"/memory".as_ptr());
            assert_eq!(root, 4);
            assert!(chosen > root);
            assert!(cpu1 > chosen);
            assert!(memory > cpu1);
            assert_eq!(tm_fdt_path(bp, c"chosen".as_ptr()), -1);
            assert_eq!(tm_fdt_path(bp, c"/missing".as_ptr()), -1);

            let mut model: *const c_char = core::ptr::null();
            assert_eq!(tm_fdt_prop_str(bp, root, c"model".as_ptr(), &mut model), 0);
            assert_eq!(CStr::from_ptr(model).to_str().unwrap(), "qsoe-model");

            let mut boot_hart = 0u32;
            assert_eq!(
                tm_fdt_prop_u32(bp, chosen, c"boot-hartid".as_ptr(), &mut boot_hart),
                0
            );
            assert_eq!(boot_hart, 2);

            let mut compat_ptr: *const c_void = core::ptr::null();
            let mut compat_len = 0;
            assert_eq!(
                tm_fdt_prop(
                    bp,
                    root,
                    c"compatible".as_ptr(),
                    &mut compat_ptr,
                    &mut compat_len
                ),
                0
            );
            assert_eq!(compat_len, b"qsoe,virt\0riscv-virtio\0".len() as c_uint);

            assert_eq!(
                tm_fdt_prop_str(bp, root, c"badstr".as_ptr(), &mut model),
                -1
            );
        }
    }

    #[test]
    fn compatible_and_reg_tuple() {
        let blob = build_blob(16);
        let bp = blob.as_ptr().cast::<c_void>();
        unsafe {
            let pci = tm_fdt_compatible(bp, c"pci-host-ecam-generic".as_ptr());
            assert!(pci > 0);
            assert_eq!(tm_fdt_compatible(bp, c"absent".as_ptr()), -1);
            assert_eq!(tm_fdt_compatible(bp, core::ptr::null()), -1);

            let memory = tm_fdt_path(bp, c"/memory@80000000".as_ptr());
            let mut base = 0;
            let mut size = 0;
            assert_eq!(tm_fdt_reg(bp, memory, 2, 2, 0, &mut base, &mut size), 0);
            assert_eq!(base, 0x8000_0000);
            assert_eq!(size, 0x0800_0000);
            assert_eq!(tm_fdt_reg(bp, memory, 2, 2, 1, &mut base, &mut size), -1);
            assert_eq!(tm_fdt_reg(bp, memory, 0, 0, 0, &mut base, &mut size), -1);
        }
    }
}
