#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

use core::ffi::{c_char, c_int, c_uint};

const SYSFS_CMDLINE_BUFSZ: usize = 258;
const SYSFS_BOARD_BUFSZ: usize = 130;
const SYSFS_VERSION_BUFSZ: usize = 64;
const SYSFS_BUILDDATE_BUFSZ: usize = 64;
const SYSFS_OSNAME_BUFSZ: usize = 32;

const SYSFS_NENTRIES: c_uint = 5;

const NAME_BOARD: &[u8; 6] = b"board\0";
const NAME_BUILDDATE: &[u8; 10] = b"builddate\0";
const NAME_CMDLINE: &[u8; 8] = b"cmdline\0";
const NAME_OSNAME: &[u8; 7] = b"osname\0";
const NAME_VERSION: &[u8; 8] = b"version\0";

static mut S_BOARD: [c_char; SYSFS_BOARD_BUFSZ] = [0; SYSFS_BOARD_BUFSZ];
static mut S_BUILDDATE: [c_char; SYSFS_BUILDDATE_BUFSZ] = [0; SYSFS_BUILDDATE_BUFSZ];
static mut S_CMDLINE: [c_char; SYSFS_CMDLINE_BUFSZ] = [0; SYSFS_CMDLINE_BUFSZ];
static mut S_OSNAME: [c_char; SYSFS_OSNAME_BUFSZ] = [0; SYSFS_OSNAME_BUFSZ];
static mut S_VERSION: [c_char; SYSFS_VERSION_BUFSZ] = [0; SYSFS_VERSION_BUFSZ];

static mut S_BOARD_LEN: c_uint = 0;
static mut S_BUILDDATE_LEN: c_uint = 0;
static mut S_CMDLINE_LEN: c_uint = 0;
static mut S_OSNAME_LEN: c_uint = 0;
static mut S_VERSION_LEN: c_uint = 0;

unsafe fn snap<const N: usize>(dst: *mut c_char, len_out: *mut c_uint, src: *const c_char) {
    let mut n = 0usize;
    if !src.is_null() {
        while n + 2 < N && *src.add(n) != 0 {
            *dst.add(n) = *src.add(n);
            n += 1;
        }
    }
    *dst.add(n) = b'\n' as c_char;
    *dst.add(n + 1) = 0;
    *len_out = (n + 1) as c_uint;
}

unsafe fn byte_at(path: *const c_char, idx: usize) -> u8 {
    *path.add(idx) as u8
}

unsafe fn streq(mut path: *const c_char, name: &[u8]) -> bool {
    let mut i = 0usize;
    loop {
        let a = *path as u8;
        let b = name[i];
        if a != b {
            return false;
        }
        if a == 0 {
            return true;
        }
        path = path.add(1);
        i += 1;
    }
}

fn name_for_idx(idx: c_uint) -> *const c_char {
    match idx {
        0 => NAME_BOARD.as_ptr() as *const c_char,
        1 => NAME_BUILDDATE.as_ptr() as *const c_char,
        2 => NAME_CMDLINE.as_ptr() as *const c_char,
        3 => NAME_OSNAME.as_ptr() as *const c_char,
        4 => NAME_VERSION.as_ptr() as *const c_char,
        _ => core::ptr::null(),
    }
}

unsafe fn content_for_idx(idx: c_uint) -> (*const c_char, c_uint) {
    match idx {
        0 => (core::ptr::addr_of!(S_BOARD).cast::<c_char>(), S_BOARD_LEN),
        1 => (
            core::ptr::addr_of!(S_BUILDDATE).cast::<c_char>(),
            S_BUILDDATE_LEN,
        ),
        2 => (
            core::ptr::addr_of!(S_CMDLINE).cast::<c_char>(),
            S_CMDLINE_LEN,
        ),
        3 => (core::ptr::addr_of!(S_OSNAME).cast::<c_char>(), S_OSNAME_LEN),
        4 => (
            core::ptr::addr_of!(S_VERSION).cast::<c_char>(),
            S_VERSION_LEN,
        ),
        _ => (core::ptr::null(), 0),
    }
}

/// Snapshot `/sys` entry content into owned buffers.
///
/// # Safety
///
/// Input pointers may be null. If non-null, they must point to NUL-terminated C
/// strings readable until the first NUL byte or until the destination entry
/// truncation limit is reached.
#[no_mangle]
pub unsafe extern "C" fn tm_sysfs_init(
    osname: *const c_char,
    board: *const c_char,
    cmdline: *const c_char,
    version: *const c_char,
    builddate: *const c_char,
) {
    snap::<SYSFS_OSNAME_BUFSZ>(
        core::ptr::addr_of_mut!(S_OSNAME).cast::<c_char>(),
        core::ptr::addr_of_mut!(S_OSNAME_LEN),
        osname,
    );
    snap::<SYSFS_BOARD_BUFSZ>(
        core::ptr::addr_of_mut!(S_BOARD).cast::<c_char>(),
        core::ptr::addr_of_mut!(S_BOARD_LEN),
        board,
    );
    snap::<SYSFS_CMDLINE_BUFSZ>(
        core::ptr::addr_of_mut!(S_CMDLINE).cast::<c_char>(),
        core::ptr::addr_of_mut!(S_CMDLINE_LEN),
        cmdline,
    );
    snap::<SYSFS_VERSION_BUFSZ>(
        core::ptr::addr_of_mut!(S_VERSION).cast::<c_char>(),
        core::ptr::addr_of_mut!(S_VERSION_LEN),
        version,
    );
    snap::<SYSFS_BUILDDATE_BUFSZ>(
        core::ptr::addr_of_mut!(S_BUILDDATE).cast::<c_char>(),
        core::ptr::addr_of_mut!(S_BUILDDATE_LEN),
        builddate,
    );
}

/// Resolve an absolute path against the `/sys` tree.
///
/// # Safety
///
/// `path` may be null. If non-null, it must point to a NUL-terminated C
/// string. `idx_out` may be null; if non-null, it must be valid for one
/// `unsigned` write.
#[no_mangle]
pub unsafe extern "C" fn tm_sysfs_resolve(path: *const c_char, idx_out: *mut c_uint) -> c_int {
    if path.is_null()
        || byte_at(path, 0) != b'/'
        || byte_at(path, 1) != b's'
        || byte_at(path, 2) != b'y'
        || byte_at(path, 3) != b's'
    {
        return 0;
    }

    if byte_at(path, 4) == 0 {
        return 1;
    }
    if byte_at(path, 4) != b'/' {
        return 0;
    }
    if byte_at(path, 5) == 0 {
        return 1;
    }

    let name = path.add(5);
    let mut i = 0;
    while i < SYSFS_NENTRIES {
        let entry_name = match i {
            0 => NAME_BOARD.as_slice(),
            1 => NAME_BUILDDATE.as_slice(),
            2 => NAME_CMDLINE.as_slice(),
            3 => NAME_OSNAME.as_slice(),
            _ => NAME_VERSION.as_slice(),
        };
        if streq(name, entry_name) {
            if !idx_out.is_null() {
                *idx_out = i;
            }
            return 2;
        }
        i += 1;
    }
    0
}

/// Return non-zero when a path resolves to the `/sys` root or a known entry.
///
/// # Safety
///
/// `path` may be null. If non-null, it must point to a NUL-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn tm_sysfs_path_exists(path: *const c_char) -> c_int {
    let mut idx = 0;
    let kind = tm_sysfs_resolve(path, &mut idx);
    (kind == 1 || kind == 2) as c_int
}

/// Return the content pointer and length for a `/sys` entry index.
///
/// # Safety
///
/// `len_out` may be null. If non-null, it must be valid for one `unsigned`
/// write. The returned pointer, when non-null, points to static provider-owned
/// storage that remains valid until the next `tm_sysfs_init` call.
#[no_mangle]
pub unsafe extern "C" fn tm_sysfs_content(idx: c_uint, len_out: *mut c_uint) -> *const c_char {
    let (ptr, len) = content_for_idx(idx);
    if !len_out.is_null() {
        *len_out = len;
    }
    ptr
}

#[no_mangle]
pub extern "C" fn tm_sysfs_nentries() -> c_uint {
    SYSFS_NENTRIES
}

#[no_mangle]
pub extern "C" fn tm_sysfs_entry_name(idx: c_uint) -> *const c_char {
    name_for_idx(idx)
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::{ffi::CStr, slice};
    use std::sync::{Mutex, MutexGuard};

    static SYSFS_TEST_LOCK: Mutex<()> = Mutex::new(());

    fn sysfs_test_lock() -> MutexGuard<'static, ()> {
        SYSFS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn cstr(bytes: &'static [u8]) -> *const c_char {
        bytes.as_ptr() as *const c_char
    }

    unsafe fn content(idx: c_uint) -> (&'static [u8], c_uint) {
        let mut len = 999;
        let ptr = tm_sysfs_content(idx, &mut len);
        assert!(!ptr.is_null());
        (slice::from_raw_parts(ptr.cast::<u8>(), len as usize), len)
    }

    fn entry_name(idx: c_uint) -> Option<&'static str> {
        let ptr = tm_sysfs_entry_name(idx);
        if ptr.is_null() {
            return None;
        }
        Some(unsafe { CStr::from_ptr(ptr).to_str().unwrap() })
    }

    #[test]
    fn snapshots_content_with_newline_and_empty_fallback() {
        let _guard = sysfs_test_lock();
        unsafe {
            tm_sysfs_init(
                cstr(b"QSOE/L\0"),
                cstr(b"qemu,virt\0"),
                core::ptr::null(),
                cstr(b"1.2.3\0"),
                cstr(b"\0"),
            );

            assert_eq!(content(0).0, b"qemu,virt\n");
            assert_eq!(content(1).0, b"\n");
            assert_eq!(content(2).0, b"\n");
            assert_eq!(content(3).0, b"QSOE/L\n");
            assert_eq!(content(4).0, b"1.2.3\n");
        }
    }

    #[test]
    fn truncates_to_leave_newline_and_nul() {
        let _guard = sysfs_test_lock();
        let long_board = [b'a'; SYSFS_BOARD_BUFSZ + 10];
        let mut nul_terminated = [0u8; SYSFS_BOARD_BUFSZ + 11];
        nul_terminated[..long_board.len()].copy_from_slice(&long_board);

        unsafe {
            tm_sysfs_init(
                cstr(b"os\0"),
                nul_terminated.as_ptr() as *const c_char,
                cstr(b"cmd\0"),
                cstr(b"ver\0"),
                cstr(b"date\0"),
            );
            let (bytes, len) = content(0);
            assert_eq!(len as usize, SYSFS_BOARD_BUFSZ - 1);
            assert!(bytes[..SYSFS_BOARD_BUFSZ - 2].iter().all(|b| *b == b'a'));
            assert_eq!(bytes[SYSFS_BOARD_BUFSZ - 2], b'\n');
        }
    }

    #[test]
    fn resolves_sys_paths_and_entries() {
        unsafe {
            let mut idx = 99;
            assert_eq!(tm_sysfs_resolve(cstr(b"/sys\0"), &mut idx), 1);
            assert_eq!(idx, 99);
            assert_eq!(tm_sysfs_resolve(cstr(b"/sys/\0"), &mut idx), 1);
            assert_eq!(tm_sysfs_resolve(cstr(b"/sys/board\0"), &mut idx), 2);
            assert_eq!(idx, 0);
            assert_eq!(tm_sysfs_resolve(cstr(b"/sys/builddate\0"), &mut idx), 2);
            assert_eq!(idx, 1);
            assert_eq!(tm_sysfs_resolve(cstr(b"/sys/cmdline\0"), &mut idx), 2);
            assert_eq!(idx, 2);
            assert_eq!(tm_sysfs_resolve(cstr(b"/sys/osname\0"), &mut idx), 2);
            assert_eq!(idx, 3);
            assert_eq!(tm_sysfs_resolve(cstr(b"/sys/version\0"), &mut idx), 2);
            assert_eq!(idx, 4);
            assert_eq!(tm_sysfs_resolve(cstr(b"sys\0"), &mut idx), 0);
            assert_eq!(tm_sysfs_resolve(cstr(b"/sysx\0"), &mut idx), 0);
            assert_eq!(tm_sysfs_resolve(cstr(b"/sys/unknown\0"), &mut idx), 0);
            assert_eq!(tm_sysfs_resolve(cstr(b"/sys/board/\0"), &mut idx), 0);
            assert_eq!(tm_sysfs_path_exists(cstr(b"/sys/version\0")), 1);
            assert_eq!(tm_sysfs_path_exists(cstr(b"/sys/missing\0")), 0);
            assert_eq!(tm_sysfs_path_exists(core::ptr::null()), 0);
        }
    }

    #[test]
    fn exposes_entry_names_and_invalid_content_contract() {
        assert_eq!(tm_sysfs_nentries(), 5);
        assert_eq!(entry_name(0), Some("board"));
        assert_eq!(entry_name(1), Some("builddate"));
        assert_eq!(entry_name(2), Some("cmdline"));
        assert_eq!(entry_name(3), Some("osname"));
        assert_eq!(entry_name(4), Some("version"));
        assert_eq!(entry_name(5), None);

        unsafe {
            let mut len = 123;
            assert!(tm_sysfs_content(99, &mut len).is_null());
            assert_eq!(len, 0);
        }
    }
}
