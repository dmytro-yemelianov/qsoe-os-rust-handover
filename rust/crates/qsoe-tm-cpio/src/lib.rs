#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

use core::ffi::{c_char, c_int, c_uint, c_void};

const NEWC_MAGIC: &[u8; 6] = b"070701";
const HEADER_LEN: usize = 110;
const FIELD_MODE: usize = 14;
const FIELD_FILESIZE: usize = 54;
const FIELD_NAMESIZE: usize = 94;
const FILENAME_MAX: usize = 64;
const MAX_SYMLINKS: usize = 8;
const S_IFMT: u32 = 0xF000;
const S_IFLNK: u32 = 0xA000;
const DT_DIR: c_uint = 4;
const DT_REG: c_uint = 8;
const DT_LNK: c_uint = 10;
const DIRENT_MAX: usize = 16;
const DIRENT_NAME_MAX: usize = 32;

type TmCpioCallback = Option<unsafe extern "C" fn(*const TmCpioFileInfo, *mut c_void)>;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TmCpioFileInfo {
    pub filename: [c_char; FILENAME_MAX],
    pub filesize: u32,
    pub mode: u32,
    pub data: *const u8,
}

#[derive(Clone, Copy)]
struct Entry {
    name_offset: usize,
    data_offset: usize,
    filesize: u32,
    mode: u32,
}

const fn align_4(value: usize) -> usize {
    (value + 3) & !3
}

fn align_4_offset(base: *const u8, offset: usize) -> Option<usize> {
    let base_addr = base as usize;
    base_addr
        .checked_add(offset)
        .map(align_4)
        .and_then(|aligned| aligned.checked_sub(base_addr))
}

unsafe fn byte_at(data: *const u8, offset: usize) -> u8 {
    *data.add(offset)
}

unsafe fn check_magic(data: *const u8, offset: usize) -> bool {
    let mut i = 0usize;
    while i < NEWC_MAGIC.len() {
        if byte_at(data, offset + i) != NEWC_MAGIC[i] {
            return false;
        }
        i += 1;
    }
    true
}

unsafe fn parse_hex8(data: *const u8, offset: usize) -> u32 {
    let mut value = 0u32;
    let mut i = 0usize;
    while i < 8 {
        value <<= 4;
        let b = byte_at(data, offset + i);
        value |= match b {
            b'0'..=b'9' => u32::from(b - b'0'),
            b'a'..=b'f' => u32::from(b - b'a' + 10),
            b'A'..=b'F' => u32::from(b - b'A' + 10),
            _ => return 0,
        };
        i += 1;
    }
    value
}

unsafe fn c_strlen(mut s: *const c_char) -> usize {
    let mut n = 0usize;
    while *s != 0 {
        n += 1;
        s = s.add(1);
    }
    n
}

fn copy_bytes_to_c_buf(dst: *mut c_char, cap: c_uint, src: &[u8]) -> bool {
    if dst.is_null() || src.len() + 1 > cap as usize {
        unsafe {
            if !dst.is_null() && cap != 0 {
                *dst = 0;
            }
        }
        return false;
    }
    let mut i = 0usize;
    while i < src.len() {
        unsafe {
            *dst.add(i) = src[i] as c_char;
        }
        i += 1;
    }
    unsafe {
        *dst.add(src.len()) = 0;
    }
    true
}

fn c_name_bytes(name: &[c_char; FILENAME_MAX]) -> &[u8] {
    let mut len = 0usize;
    while len < name.len() && name[len] != 0 {
        len += 1;
    }
    unsafe { core::slice::from_raw_parts(name.as_ptr().cast::<u8>(), len) }
}

unsafe fn name_starts_with(data: *const u8, name_offset: usize, prefix: &[u8]) -> bool {
    let mut i = 0usize;
    while i < prefix.len() {
        if byte_at(data, name_offset + i) != prefix[i] {
            return false;
        }
        i += 1;
    }
    true
}

unsafe fn fill_info(data: *const u8, entry: Entry) -> TmCpioFileInfo {
    let mut filename = [0 as c_char; FILENAME_MAX];
    let mut i = 0usize;
    while i + 1 < FILENAME_MAX {
        let b = byte_at(data, entry.name_offset + i);
        if b == 0 {
            break;
        }
        filename[i] = b as c_char;
        i += 1;
    }
    filename[i] = 0;

    TmCpioFileInfo {
        filename,
        filesize: entry.filesize,
        mode: entry.mode,
        data: data.add(entry.data_offset),
    }
}

unsafe fn iterate_entries(data: *const u8, size: usize, mut on_entry: impl FnMut(TmCpioFileInfo)) {
    if data.is_null() {
        return;
    }

    let mut offset = 0usize;
    while offset < size {
        if offset.checked_add(HEADER_LEN).is_none_or(|end| end > size) {
            break;
        }
        if !check_magic(data, offset) {
            break;
        }

        let namesize = parse_hex8(data, offset + FIELD_NAMESIZE) as usize;
        let filesize = parse_hex8(data, offset + FIELD_FILESIZE);
        let mode = parse_hex8(data, offset + FIELD_MODE);

        let name_offset = offset + HEADER_LEN;
        if name_offset
            .checked_add(namesize)
            .is_none_or(|end| end > size)
        {
            break;
        }
        let Some(data_offset) = align_4_offset(data, name_offset + namesize) else {
            break;
        };
        offset = data_offset;

        if name_starts_with(data, name_offset, b"TRAILER!!!") {
            break;
        }

        let filesize_usize = filesize as usize;
        if offset
            .checked_add(filesize_usize)
            .is_none_or(|end| end > size)
        {
            break;
        }

        let entry = Entry {
            name_offset,
            data_offset: offset,
            filesize,
            mode,
        };
        on_entry(fill_info(data, entry));

        let Some(next_offset) = align_4_offset(data, offset + filesize_usize) else {
            break;
        };
        offset = next_offset;
    }
}

fn info_name_eq(info: &TmCpioFileInfo, target: &[u8]) -> bool {
    c_name_bytes(&info.filename) == target
}

unsafe fn target_bytes<'a>(filename: *const c_char) -> Option<&'a [u8]> {
    if filename.is_null() {
        return None;
    }
    Some(core::slice::from_raw_parts(
        filename.cast::<u8>(),
        c_strlen(filename),
    ))
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ResolveError {
    Missing,
    Invalid,
}

unsafe fn find_info(data: *const u8, size: usize, target: &[u8]) -> Option<TmCpioFileInfo> {
    let mut result = None;
    iterate_entries(data, size, |info| {
        if result.is_none() && info_name_eq(&info, target) {
            result = Some(info);
        }
    });
    result
}

fn strip_leading_slash(path: &[u8]) -> &[u8] {
    if path.first() == Some(&b'/') {
        &path[1..]
    } else {
        path
    }
}

fn copy_slice_to_fixed<const N: usize>(dst: &mut [u8; N], src: &[u8]) -> bool {
    if src.len() + 1 > N {
        dst[0] = 0;
        return false;
    }
    let mut i = 0usize;
    while i < src.len() {
        dst[i] = src[i];
        i += 1;
    }
    dst[src.len()] = 0;
    true
}

fn fixed_bytes(buf: &[u8; FILENAME_MAX]) -> &[u8] {
    let mut len = 0usize;
    while len < buf.len() && buf[len] != 0 {
        len += 1;
    }
    &buf[..len]
}

unsafe fn resolve_path(
    data: *const u8,
    size: usize,
    path: &[u8],
) -> Result<([u8; FILENAME_MAX], TmCpioFileInfo), ResolveError> {
    let clean = strip_leading_slash(path);
    let mut cur = [0u8; FILENAME_MAX];
    if !copy_slice_to_fixed(&mut cur, clean) {
        return Err(ResolveError::Invalid);
    }

    let mut hop = 0usize;
    while hop < MAX_SYMLINKS {
        let cur_bytes = fixed_bytes(&cur);
        let info = match find_info(data, size, cur_bytes) {
            Some(info) => info,
            None => return Err(ResolveError::Missing),
        };
        if (info.mode & S_IFMT) != S_IFLNK {
            return Ok((cur, info));
        }

        let target_len = info.filesize as usize;
        if target_len == 0 || target_len >= FILENAME_MAX {
            return Err(ResolveError::Invalid);
        }
        let target = core::slice::from_raw_parts(info.data, target_len);
        let mut next = [0u8; FILENAME_MAX];
        if target[0] == b'/' {
            if !copy_slice_to_fixed(&mut next, &target[1..]) {
                return Err(ResolveError::Invalid);
            }
        } else {
            let mut dir_keep = 0usize;
            let mut i = 0usize;
            while i < cur_bytes.len() {
                if cur_bytes[i] == b'/' {
                    dir_keep = i + 1;
                }
                i += 1;
            }
            if dir_keep + target_len >= FILENAME_MAX {
                return Err(ResolveError::Invalid);
            }
            next[..dir_keep].copy_from_slice(&cur_bytes[..dir_keep]);
            next[dir_keep..dir_keep + target_len].copy_from_slice(target);
            next[dir_keep + target_len] = 0;
        }
        cur = next;
        hop += 1;
    }
    Err(ResolveError::Invalid)
}

fn child_of<'a>(name: &'a [u8], prefix: &[u8], mode: u32) -> Option<(&'a [u8], c_uint)> {
    if !name.starts_with(prefix) {
        return None;
    }
    let tail = &name[prefix.len()..];
    if tail.is_empty() {
        return None;
    }
    let mut len = 0usize;
    while len < tail.len() && tail[len] != b'/' {
        len += 1;
    }
    let dtype = if len < tail.len() && tail[len] == b'/' {
        DT_DIR
    } else if (mode & S_IFMT) == S_IFLNK {
        DT_LNK
    } else {
        DT_REG
    };
    Some((&tail[..len], dtype))
}

fn emitted_contains(
    emitted: &[[u8; DIRENT_NAME_MAX]; DIRENT_MAX],
    count: usize,
    name: &[u8],
) -> bool {
    let mut i = 0usize;
    while i < count {
        let mut len = 0usize;
        while len < DIRENT_NAME_MAX && emitted[i][len] != 0 {
            len += 1;
        }
        if &emitted[i][..len] == name {
            return true;
        }
        i += 1;
    }
    false
}

fn emitted_push(emitted: &mut [[u8; DIRENT_NAME_MAX]; DIRENT_MAX], count: &mut usize, name: &[u8]) {
    if *count >= DIRENT_MAX || name.len() + 1 > DIRENT_NAME_MAX {
        return;
    }
    emitted[*count][..name.len()].copy_from_slice(name);
    emitted[*count][name.len()] = 0;
    *count += 1;
}

/// Quick CPIO newc magic check.
///
/// # Safety
///
/// `data`, when non-null and `size >= 110`, must be readable for `size` bytes.
#[no_mangle]
pub unsafe extern "C" fn tm_cpio_check_valid(data: *const u8, size: u64) -> c_int {
    if data.is_null() || size < HEADER_LEN as u64 {
        return 0;
    }
    check_magic(data, 0) as c_int
}

/// Iterate non-TRAILER records in a CPIO newc archive.
///
/// # Safety
///
/// `data` must be readable for `size` bytes. `user` is passed through to the
/// callback. The callback must not retain the temporary `tm_cpio_file_info_t`
/// pointer past the call.
#[no_mangle]
pub unsafe extern "C" fn tm_cpio_iterate(
    data: *const u8,
    size: u64,
    cb: TmCpioCallback,
    user: *mut c_void,
) {
    iterate_entries(data, size as usize, |info| {
        if let Some(callback) = cb {
            callback(&info, user);
        }
    });
}

/// Find an archive entry by exact CPIO-relative name.
///
/// # Safety
///
/// `data` must be readable for `size` bytes. `filename` must be a
/// NUL-terminated string. `info`, when non-null, must be writable.
#[no_mangle]
pub unsafe extern "C" fn tm_cpio_find_file(
    data: *const u8,
    size: u64,
    filename: *const c_char,
    info: *mut TmCpioFileInfo,
) -> c_int {
    let target = match target_bytes(filename) {
        Some(target) => target,
        None => return 0,
    };
    match find_info(data, size as usize, target) {
        Some(found) => {
            if !info.is_null() {
                *info = found;
            }
            1
        }
        None => 0,
    }
}

/// Resolve a path through symlinks in the archive.
///
/// # Safety
///
/// `path` must be a NUL-terminated string. `out_path` must be writable for
/// `out_cap` bytes and `out_info` must be writable on success.
#[no_mangle]
pub unsafe extern "C" fn tm_cpio_resolve_path(
    data: *const u8,
    size: u64,
    path: *const c_char,
    out_path: *mut c_char,
    out_cap: c_uint,
    out_info: *mut TmCpioFileInfo,
) -> c_int {
    let path = match target_bytes(path) {
        Some(path) => path,
        None => return -1,
    };
    let (resolved, info) = match resolve_path(data, size as usize, path) {
        Ok(result) => result,
        Err(ResolveError::Missing) => return 0,
        Err(ResolveError::Invalid) => return -1,
    };
    let resolved = fixed_bytes(&resolved);
    if !copy_bytes_to_c_buf(out_path, out_cap, resolved) {
        return -1;
    }
    if out_info.is_null() {
        return -1;
    }
    *out_info = info;
    1
}

/// Return the immediate child at `index` under `prefix`.
///
/// # Safety
///
/// `prefix` must be NUL-terminated. Output pointers must be writable when
/// non-null as required by the C ABI.
#[no_mangle]
pub unsafe extern "C" fn tm_cpio_dirent_at(
    data: *const u8,
    size: u64,
    prefix: *const c_char,
    index: u32,
    out_type: *mut c_uint,
    out_name_buf: *mut c_char,
    out_name_cap: c_uint,
    out_namelen: *mut c_uint,
) -> c_int {
    let prefix = match target_bytes(prefix) {
        Some(prefix) => prefix,
        None => return 0,
    };
    let mut emitted = [[0u8; DIRENT_NAME_MAX]; DIRENT_MAX];
    let mut emitted_count = 0usize;
    let mut seen = 0u32;
    let mut found = 0 as c_int;

    iterate_entries(data, size as usize, |info| {
        if found != 0 {
            return;
        }
        let name = c_name_bytes(&info.filename);
        let (comp, dtype) = match child_of(name, prefix, info.mode) {
            Some(child) => child,
            None => return,
        };
        if emitted_contains(&emitted, emitted_count, comp) {
            return;
        }
        emitted_push(&mut emitted, &mut emitted_count, comp);
        if seen == index {
            if !copy_bytes_to_c_buf(out_name_buf, out_name_cap, comp) {
                found = -1;
                return;
            }
            if !out_namelen.is_null() {
                *out_namelen = comp.len() as c_uint;
            }
            if !out_type.is_null() {
                *out_type = dtype;
            }
            found = 1;
            return;
        }
        seen += 1;
    });

    found
}

/// Probe whether any archive entry exists below `prefix`.
///
/// # Safety
///
/// `prefix` must be a NUL-terminated string. `data` must be readable for
/// `size` bytes.
#[no_mangle]
pub unsafe extern "C" fn tm_cpio_dir_exists(
    data: *const u8,
    size: u64,
    prefix: *const c_char,
) -> c_int {
    let prefix = match target_bytes(prefix) {
        Some(prefix) => prefix,
        None => return 0,
    };
    let mut hit = false;
    iterate_entries(data, size as usize, |info| {
        if hit {
            return;
        }
        let name = c_name_bytes(&info.filename);
        if name.starts_with(prefix) && name.len() > prefix.len() {
            hit = true;
        }
    });
    hit as c_int
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::ffi::CStr;
    use std::vec::Vec;

    const REG: u32 = 0o100644;
    const LNK: u32 = 0o120777;

    fn fixture_archive() -> Vec<u8> {
        let mut archive = Vec::new();
        push_entry(&mut archive, "bin/qsh", REG, b"elf");
        push_entry(&mut archive, "bin/sh", LNK, b"qsh");
        push_entry(&mut archive, "etc/init", LNK, b"/bin/qsh");
        push_entry(&mut archive, "usr/conf/passwd", REG, b"root\n");
        push_entry(&mut archive, "usr/conf/shadow", REG, b"shadow\n");
        push_entry(&mut archive, "TRAILER!!!", REG, b"");
        archive
    }

    fn cstr(bytes: &'static [u8]) -> *const c_char {
        bytes.as_ptr() as *const c_char
    }

    fn name(info: &TmCpioFileInfo) -> &str {
        unsafe { CStr::from_ptr(info.filename.as_ptr()).to_str().unwrap() }
    }

    unsafe extern "C" fn collect_names(info: *const TmCpioFileInfo, user: *mut c_void) {
        let names = &mut *(user as *mut Vec<&'static str>);
        let n = name(&*info);
        names.push(match n {
            "bin/qsh" => "bin/qsh",
            "bin/sh" => "bin/sh",
            "etc/init" => "etc/init",
            "usr/conf/passwd" => "usr/conf/passwd",
            "usr/conf/shadow" => "usr/conf/shadow",
            other => panic!("unexpected name {other}"),
        });
    }

    #[test]
    fn iterates_and_finds_entries() {
        let archive = fixture_archive();
        assert_eq!(
            unsafe { tm_cpio_check_valid(archive.as_ptr(), archive.len() as u64) },
            1
        );

        let mut names = Vec::new();
        unsafe {
            tm_cpio_iterate(
                archive.as_ptr(),
                archive.len() as u64,
                Some(collect_names),
                (&mut names as *mut Vec<&'static str>).cast(),
            );
        }
        assert_eq!(
            names,
            [
                "bin/qsh",
                "bin/sh",
                "etc/init",
                "usr/conf/passwd",
                "usr/conf/shadow"
            ]
        );

        let mut info = empty_info();
        assert_eq!(
            unsafe {
                tm_cpio_find_file(
                    archive.as_ptr(),
                    archive.len() as u64,
                    cstr(b"usr/conf/passwd\0"),
                    &mut info,
                )
            },
            1
        );
        assert_eq!(name(&info), "usr/conf/passwd");
        assert_eq!(info.filesize, 5);
        assert_eq!(
            unsafe { core::slice::from_raw_parts(info.data, 5) },
            b"root\n"
        );
    }

    #[test]
    fn resolves_relative_and_absolute_symlinks() {
        let archive = fixture_archive();
        let mut info = empty_info();
        let mut out = [0 as c_char; FILENAME_MAX];

        assert_eq!(
            unsafe {
                tm_cpio_resolve_path(
                    archive.as_ptr(),
                    archive.len() as u64,
                    cstr(b"/bin/sh\0"),
                    out.as_mut_ptr(),
                    out.len() as c_uint,
                    &mut info,
                )
            },
            1
        );
        assert_eq!(
            unsafe { CStr::from_ptr(out.as_ptr()).to_str().unwrap() },
            "bin/qsh"
        );
        assert_eq!(name(&info), "bin/qsh");

        assert_eq!(
            unsafe {
                tm_cpio_resolve_path(
                    archive.as_ptr(),
                    archive.len() as u64,
                    cstr(b"/etc/init\0"),
                    out.as_mut_ptr(),
                    out.len() as c_uint,
                    &mut info,
                )
            },
            1
        );
        assert_eq!(
            unsafe { CStr::from_ptr(out.as_ptr()).to_str().unwrap() },
            "bin/qsh"
        );
    }

    #[test]
    fn reports_directory_entries_and_existence() {
        let archive = fixture_archive();
        assert_eq!(
            unsafe { tm_cpio_dir_exists(archive.as_ptr(), archive.len() as u64, cstr(b"usr/\0")) },
            1
        );
        assert_eq!(
            unsafe {
                tm_cpio_dir_exists(archive.as_ptr(), archive.len() as u64, cstr(b"missing/\0"))
            },
            0
        );

        let mut name_buf = [0 as c_char; 32];
        let mut namelen = 0;
        let mut dtype = 0;
        assert_eq!(
            unsafe {
                tm_cpio_dirent_at(
                    archive.as_ptr(),
                    archive.len() as u64,
                    cstr(b"\0"),
                    0,
                    &mut dtype,
                    name_buf.as_mut_ptr(),
                    name_buf.len() as c_uint,
                    &mut namelen,
                )
            },
            1
        );
        assert_eq!(
            unsafe { CStr::from_ptr(name_buf.as_ptr()).to_str().unwrap() },
            "bin"
        );
        assert_eq!(namelen, 3);
        assert_eq!(dtype, DT_DIR);

        assert_eq!(
            unsafe {
                tm_cpio_dirent_at(
                    archive.as_ptr(),
                    archive.len() as u64,
                    cstr(b"bin/\0"),
                    1,
                    &mut dtype,
                    name_buf.as_mut_ptr(),
                    name_buf.len() as c_uint,
                    &mut namelen,
                )
            },
            1
        );
        assert_eq!(
            unsafe { CStr::from_ptr(name_buf.as_ptr()).to_str().unwrap() },
            "sh"
        );
        assert_eq!(dtype, DT_LNK);
    }

    #[test]
    fn stops_on_malformed_entry_like_c_walker() {
        let mut archive = fixture_archive();
        let second_header = align_4(align_4(HEADER_LEN + "bin/qsh".len() + 1) + 3);
        archive[second_header] = b'x';

        let mut names = Vec::new();
        unsafe {
            tm_cpio_iterate(
                archive.as_ptr(),
                archive.len() as u64,
                Some(collect_names),
                (&mut names as *mut Vec<&'static str>).cast(),
            );
        }
        assert_eq!(names, ["bin/qsh"]);

        archive[0] = b'x';
        assert_eq!(
            unsafe {
                tm_cpio_find_file(
                    archive.as_ptr(),
                    archive.len() as u64,
                    cstr(b"bin/sh\0"),
                    core::ptr::null_mut(),
                )
            },
            0
        );
    }

    #[test]
    fn aligns_entries_from_archive_pointer_like_c_walker() {
        let archive = fixture_archive();
        let mut storage = Vec::new();
        storage.resize(archive.len() + 4, 0);
        let pad = if (storage.as_ptr() as usize) & 3 == 0 {
            1
        } else {
            0
        };
        storage[pad..pad + archive.len()].copy_from_slice(&archive);
        let ptr = unsafe { storage.as_ptr().add(pad) };
        assert_ne!((ptr as usize) & 3, 0);

        let mut names = Vec::new();
        unsafe {
            tm_cpio_iterate(
                ptr,
                archive.len() as u64,
                Some(collect_names),
                (&mut names as *mut Vec<&'static str>).cast(),
            );
        }
        assert_eq!(names, ["bin/qsh"]);
    }

    fn empty_info() -> TmCpioFileInfo {
        TmCpioFileInfo {
            filename: [0; FILENAME_MAX],
            filesize: 0,
            mode: 0,
            data: core::ptr::null(),
        }
    }

    fn push_entry(archive: &mut Vec<u8>, name: &str, mode: u32, data: &[u8]) {
        let namesize = name.len() + 1;
        archive.extend_from_slice(b"070701");
        push_hex(archive, 1);
        push_hex(archive, mode);
        push_hex(archive, 0);
        push_hex(archive, 0);
        push_hex(archive, 1);
        push_hex(archive, 0);
        push_hex(archive, data.len() as u32);
        push_hex(archive, 0);
        push_hex(archive, 0);
        push_hex(archive, 0);
        push_hex(archive, 0);
        push_hex(archive, namesize as u32);
        push_hex(archive, 0);
        archive.extend_from_slice(name.as_bytes());
        archive.push(0);
        pad_to_alignment(archive);
        archive.extend_from_slice(data);
        pad_to_alignment(archive);
    }

    fn push_hex(archive: &mut Vec<u8>, value: u32) {
        use std::format;

        archive.extend_from_slice(format!("{value:08x}").as_bytes());
    }

    fn pad_to_alignment(archive: &mut Vec<u8>) {
        let padding = (4 - archive.len() % 4) % 4;
        archive.resize(archive.len() + padding, 0);
    }
}
