#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

use core::ffi::{c_char, c_int, c_ulong};

#[cfg(not(any(test, feature = "host-tests")))]
use core::panic::PanicInfo;

pub const TM_PROCFS_NAME_MAX: usize = 32;
pub const TM_PROCFS_INFO_MAX: u32 = 160;
pub const TM_PROCFS_DT_DIR: c_int = 4;
pub const TM_PROCFS_DT_REG: c_int = 8;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TmProcfsProc {
    pub pid: c_int,
    pub ppid: c_int,
    pub state: c_int,
    pub name: [c_char; TM_PROCFS_NAME_MAX],
}

impl TmProcfsProc {
    const fn zeroed() -> Self {
        Self {
            pid: 0,
            ppid: 0,
            state: 0,
            name: [0; TM_PROCFS_NAME_MAX],
        }
    }
}

pub type TmProcfsGetFn = unsafe extern "C" fn(c_int, *mut TmProcfsProc) -> c_int;
pub type TmProcfsNextFn = unsafe extern "C" fn(c_int, *mut TmProcfsProc) -> c_int;

static mut S_GET: Option<TmProcfsGetFn> = None;
static mut S_NEXT: Option<TmProcfsNextFn> = None;

#[cfg(not(any(test, feature = "host-tests")))]
#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    loop {
        core::hint::spin_loop();
    }
}

#[no_mangle]
pub extern "C" fn tm_procfs_init(get: Option<TmProcfsGetFn>, next: Option<TmProcfsNextFn>) {
    unsafe {
        S_GET = get;
        S_NEXT = next;
    }
}

unsafe fn call_get(pid: c_int, out: *mut TmProcfsProc) -> bool {
    let get = S_GET;
    match get {
        Some(f) => f(pid, out) != 0,
        None => false,
    }
}

unsafe fn call_next(from: c_int, out: *mut TmProcfsProc) -> c_int {
    let next = S_NEXT;
    match next {
        Some(f) => f(from, out),
        None => 0,
    }
}

unsafe fn byte_at(path: *const c_char, idx: usize) -> u8 {
    *path.add(idx) as u8
}

/// Resolve a `/proc` path using the registered process lookup callback.
///
/// # Safety
///
/// `path` must point to a valid NUL-terminated C string. `pid_out` may be null;
/// if non-null, it must be valid for one `c_int` write.
#[no_mangle]
pub unsafe extern "C" fn tm_procfs_resolve(path: *const c_char, pid_out: *mut c_int) -> c_int {
    if byte_at(path, 0) != b'/'
        || byte_at(path, 1) != b'p'
        || byte_at(path, 2) != b'r'
        || byte_at(path, 3) != b'o'
        || byte_at(path, 4) != b'c'
    {
        return 0;
    }
    if byte_at(path, 5) == 0 {
        return 1;
    }
    if byte_at(path, 5) != b'/' {
        return 0;
    }
    if byte_at(path, 6) == 0 {
        return 1;
    }

    let mut i = 6usize;
    let mut pid: i64 = 0;
    let first = byte_at(path, i);
    if !first.is_ascii_digit() {
        return 0;
    }
    loop {
        let b = byte_at(path, i);
        if !b.is_ascii_digit() {
            break;
        }
        pid = pid * 10 + i64::from(b - b'0');
        if pid > i64::from(c_int::MAX) {
            return 0;
        }
        i += 1;
    }

    let mut tmp = TmProcfsProc::zeroed();
    if !call_get(pid as c_int, &mut tmp) {
        return 0;
    }
    if !pid_out.is_null() {
        *pid_out = pid as c_int;
    }

    if byte_at(path, i) == 0 {
        return 2;
    }
    if byte_at(path, i) != b'/' {
        return 0;
    }
    i += 1;
    if byte_at(path, i) == 0 {
        return 2;
    }

    if byte_at(path, i) == b'i'
        && byte_at(path, i + 1) == b'n'
        && byte_at(path, i + 2) == b'f'
        && byte_at(path, i + 3) == b'o'
        && byte_at(path, i + 4) == 0
    {
        return 3;
    }
    0
}

/// Return non-zero when a `/proc` path resolves to an existing node.
///
/// # Safety
///
/// `path` must point to a valid NUL-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn tm_procfs_path_exists(path: *const c_char) -> c_int {
    let mut pid = 0;
    (tm_procfs_resolve(path, &mut pid) != 0) as c_int
}

unsafe fn put_byte(dst: *mut c_char, pos: &mut usize, b: u8) {
    *dst.add(*pos) = b as c_char;
    *pos += 1;
}

unsafe fn put_bytes(dst: *mut c_char, pos: &mut usize, bytes: &[u8]) {
    let mut i = 0;
    while i < bytes.len() {
        put_byte(dst, pos, bytes[i]);
        i += 1;
    }
}

unsafe fn put_dec(dst: *mut c_char, pos: &mut usize, value: c_int) {
    let mut v = i64::from(value);
    let mut tmp = [0u8; 24];
    let mut n = 0usize;

    if v < 0 {
        put_byte(dst, pos, b'-');
        v = -v;
    }

    loop {
        tmp[n] = b'0' + (v % 10) as u8;
        n += 1;
        v /= 10;
        if v == 0 {
            break;
        }
    }

    while n > 0 {
        n -= 1;
        put_byte(dst, pos, tmp[n]);
    }
}

unsafe fn put_c_name(dst: *mut c_char, pos: &mut usize, name: &[c_char; TM_PROCFS_NAME_MAX]) {
    let mut i = 0usize;
    while i < TM_PROCFS_NAME_MAX {
        let b = name[i] as u8;
        if b == 0 {
            break;
        }
        put_byte(dst, pos, b);
        i += 1;
    }
}

/// Render `/proc/<pid>/info` into the caller-provided buffer.
///
/// # Safety
///
/// `dst` must be valid for `cap` bytes when `cap >= TM_PROCFS_INFO_MAX`.
#[no_mangle]
pub unsafe extern "C" fn tm_procfs_info(pid: c_int, dst: *mut c_char, cap: u32) -> u32 {
    let mut proc = TmProcfsProc::zeroed();
    if cap < TM_PROCFS_INFO_MAX || !call_get(pid, &mut proc) {
        return 0;
    }

    let mut n = 0usize;
    put_bytes(dst, &mut n, b"pid: ");
    put_dec(dst, &mut n, proc.pid);
    put_bytes(dst, &mut n, b"\nppid: ");
    put_dec(dst, &mut n, proc.ppid);
    put_bytes(dst, &mut n, b"\nstate: ");
    put_bytes(
        dst,
        &mut n,
        if proc.state != 0 { b"zombie" } else { b"alive" },
    );
    put_bytes(dst, &mut n, b"\nname: ");
    put_c_name(dst, &mut n, &proc.name);
    put_bytes(dst, &mut n, b"\n");
    n as u32
}

/// Emit the next root `/proc` directory entry.
///
/// # Safety
///
/// All output pointers must be non-null and valid for their documented writes.
#[no_mangle]
pub unsafe extern "C" fn tm_procfs_readdir_root(
    cursor: *mut c_ulong,
    name_out: *mut c_char,
    namelen_out: *mut u32,
    d_type_out: *mut c_int,
) -> c_int {
    let mut proc = TmProcfsProc::zeroed();
    let pid = call_next(*cursor as c_int, &mut proc);
    if pid <= 0 {
        return 0;
    }

    *cursor = (pid as c_ulong) + 1;
    let mut n = 0usize;
    put_dec(name_out, &mut n, pid);
    *name_out.add(n) = 0;
    *namelen_out = n as u32;
    *d_type_out = TM_PROCFS_DT_DIR;
    1
}

/// Emit the single `info` entry for a `/proc/<pid>` directory.
///
/// # Safety
///
/// All output pointers must be non-null and valid for their documented writes.
#[no_mangle]
pub unsafe extern "C" fn tm_procfs_readdir_piddir(
    cursor: c_ulong,
    name_out: *mut c_char,
    namelen_out: *mut u32,
    d_type_out: *mut c_int,
) -> c_int {
    if cursor >= 1 {
        return 0;
    }
    let mut n = 0usize;
    put_bytes(name_out, &mut n, b"info");
    *name_out.add(4) = 0;
    *namelen_out = 4;
    *d_type_out = TM_PROCFS_DT_REG;
    1
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::ffi::c_char;

    const PROCS: [TmProcfsProc; 3] = [
        proc(1, 0, 0, b"init"),
        proc(7, 1, 1, b"worker-z"),
        proc(42, 1, 0, b"1234567890123456789012345678901"),
    ];

    static mut DROPPED_PID: c_int = 0;

    const fn proc(pid: c_int, ppid: c_int, state: c_int, name: &[u8]) -> TmProcfsProc {
        let mut out = TmProcfsProc {
            pid,
            ppid,
            state,
            name: [0; TM_PROCFS_NAME_MAX],
        };
        let mut i = 0usize;
        while i < name.len() && i + 1 < TM_PROCFS_NAME_MAX {
            out.name[i] = name[i] as c_char;
            i += 1;
        }
        out
    }

    unsafe extern "C" fn fixture_get(pid: c_int, out: *mut TmProcfsProc) -> c_int {
        if pid == DROPPED_PID {
            return 0;
        }
        let mut i = 0usize;
        while i < PROCS.len() {
            if PROCS[i].pid == pid {
                *out = PROCS[i];
                return 1;
            }
            i += 1;
        }
        0
    }

    unsafe extern "C" fn fixture_next(from: c_int, out: *mut TmProcfsProc) -> c_int {
        let mut i = 0usize;
        while i < PROCS.len() {
            let proc = PROCS[i];
            if proc.pid != DROPPED_PID && proc.pid >= from {
                *out = proc;
                return proc.pid;
            }
            i += 1;
        }
        0
    }

    fn reset() {
        unsafe {
            DROPPED_PID = 0;
        }
        tm_procfs_init(Some(fixture_get), Some(fixture_next));
    }

    fn c_buf(bytes: &[u8]) -> [c_char; 64] {
        let mut out = [0 as c_char; 64];
        let mut i = 0usize;
        while i < bytes.len() {
            out[i] = bytes[i] as c_char;
            i += 1;
        }
        out
    }

    unsafe fn expect_resolve(path: &[u8], kind: c_int, expected_pid: c_int) {
        let path = c_buf(path);
        let mut pid = -99;
        assert_eq!(tm_procfs_resolve(path.as_ptr(), &mut pid), kind);
        if kind == 2 || kind == 3 {
            assert_eq!(pid, expected_pid);
        }
    }

    unsafe fn info_string(pid: c_int) -> (u32, [u8; TM_PROCFS_INFO_MAX as usize]) {
        let mut buf = [0 as c_char; TM_PROCFS_INFO_MAX as usize];
        let n = tm_procfs_info(pid, buf.as_mut_ptr(), TM_PROCFS_INFO_MAX);
        let mut out = [0u8; TM_PROCFS_INFO_MAX as usize];
        let mut i = 0usize;
        while i < n as usize {
            out[i] = buf[i] as u8;
            i += 1;
        }
        (n, out)
    }

    unsafe fn expect_root_entry(cursor: &mut c_ulong, name: &[u8], next_cursor: c_ulong) {
        let mut out = [0 as c_char; 32];
        let mut namelen = 0u32;
        let mut d_type = 0;
        assert_eq!(
            tm_procfs_readdir_root(cursor, out.as_mut_ptr(), &mut namelen, &mut d_type),
            1
        );
        let mut i = 0usize;
        while i < name.len() {
            assert_eq!(out[i] as u8, name[i]);
            i += 1;
        }
        assert_eq!(out[name.len()], 0);
        assert_eq!(namelen, name.len() as u32);
        assert_eq!(d_type, TM_PROCFS_DT_DIR);
        assert_eq!(*cursor, next_cursor);
    }

    #[test]
    fn c_abi_contract_matches_tm_procfs_model() {
        unsafe {
            assert_eq!(core::mem::size_of::<[c_char; TM_PROCFS_NAME_MAX]>(), 32);
            reset();

            expect_resolve(b"/proc", 1, 0);
            expect_resolve(b"/proc/", 1, 0);
            expect_resolve(b"/proc/1", 2, 1);
            expect_resolve(b"/proc/1/", 2, 1);
            expect_resolve(b"/proc/1/info", 3, 1);
            expect_resolve(b"proc", 0, 0);
            expect_resolve(b"/procx", 0, 0);
            expect_resolve(b"/proc//1", 0, 0);
            expect_resolve(b"/proc/-1", 0, 0);
            expect_resolve(b"/proc/x", 0, 0);
            expect_resolve(b"/proc/1x", 0, 0);
            expect_resolve(b"/proc/2147483648", 0, 0);
            expect_resolve(b"/proc/2", 0, 0);
            expect_resolve(b"/proc/1/stat", 0, 0);
            expect_resolve(b"/proc/1/info/", 0, 0);

            let proc_7_info = c_buf(b"/proc/7/info");
            assert_ne!(tm_procfs_path_exists(proc_7_info.as_ptr()), 0);

            let (n, info) = info_string(1);
            assert_eq!(
                n as usize,
                b"pid: 1\nppid: 0\nstate: alive\nname: init\n".len()
            );
            assert_eq!(
                &info[..n as usize],
                b"pid: 1\nppid: 0\nstate: alive\nname: init\n"
            );

            let (n, info) = info_string(7);
            assert_eq!(
                &info[..n as usize],
                b"pid: 7\nppid: 1\nstate: zombie\nname: worker-z\n"
            );

            let (n, info) = info_string(42);
            assert_eq!(
                &info[..n as usize],
                b"pid: 42\nppid: 1\nstate: alive\nname: 1234567890123456789012345678901\n"
            );

            let mut small = [0 as c_char; TM_PROCFS_INFO_MAX as usize];
            assert_eq!(
                tm_procfs_info(1, small.as_mut_ptr(), TM_PROCFS_INFO_MAX - 1),
                0
            );
            assert_eq!(
                tm_procfs_info(99, small.as_mut_ptr(), TM_PROCFS_INFO_MAX),
                0
            );

            let mut cursor = 0 as c_ulong;
            expect_root_entry(&mut cursor, b"1", 2);
            expect_root_entry(&mut cursor, b"7", 8);
            expect_root_entry(&mut cursor, b"42", 43);
            let mut name = [0 as c_char; 32];
            let mut namelen = 0;
            let mut d_type = 0;
            assert_eq!(
                tm_procfs_readdir_root(&mut cursor, name.as_mut_ptr(), &mut namelen, &mut d_type),
                0
            );

            assert_eq!(
                tm_procfs_readdir_piddir(0, name.as_mut_ptr(), &mut namelen, &mut d_type),
                1
            );
            assert_eq!(
                &[name[0] as u8, name[1] as u8, name[2] as u8, name[3] as u8],
                b"info"
            );
            assert_eq!(name[4], 0);
            assert_eq!(namelen, 4);
            assert_eq!(d_type, TM_PROCFS_DT_REG);
            assert_eq!(
                tm_procfs_readdir_piddir(1, name.as_mut_ptr(), &mut namelen, &mut d_type),
                0
            );

            tm_procfs_init(None, None);
            assert_eq!(
                tm_procfs_resolve(proc_7_info.as_ptr(), core::ptr::null_mut()),
                0
            );
            assert_eq!(tm_procfs_info(7, small.as_mut_ptr(), TM_PROCFS_INFO_MAX), 0);
            cursor = 0;
            assert_eq!(
                tm_procfs_readdir_root(&mut cursor, name.as_mut_ptr(), &mut namelen, &mut d_type),
                0
            );

            tm_procfs_init(None, Some(fixture_next));
            cursor = 0;
            assert_eq!(
                tm_procfs_resolve(proc_7_info.as_ptr(), core::ptr::null_mut()),
                0
            );
            assert_eq!(
                tm_procfs_readdir_root(&mut cursor, name.as_mut_ptr(), &mut namelen, &mut d_type),
                1
            );

            reset();
            DROPPED_PID = 7;
            assert_eq!(tm_procfs_path_exists(proc_7_info.as_ptr()), 0);
            assert_eq!(tm_procfs_info(7, small.as_mut_ptr(), TM_PROCFS_INFO_MAX), 0);
            cursor = 0;
            expect_root_entry(&mut cursor, b"1", 2);
            expect_root_entry(&mut cursor, b"42", 43);
        }
    }
}
