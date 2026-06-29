#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

use core::ffi::{c_int, c_long, c_uint, c_ulong};

const EINVAL: c_int = 21;

const TM_S_IFCHR: c_uint = 0o020000;
const TM_DEVZERO_MAX_READ: usize = (QSOE_MSG_MAX_LENGTH - 4) * core::mem::size_of::<c_ulong>();
const QSOE_MSG_MAX_LENGTH: usize = 120;
const QSOE_MSG_MAX_EXTRA_CAPS: usize = 3;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TmStat {
    pub st_dev: c_ulong,
    pub st_ino: c_ulong,
    pub st_mode: c_uint,
    pub st_nlink: c_uint,
    pub st_uid: c_uint,
    pub st_gid: c_uint,
    pub st_rdev: c_ulong,
    pub __pad: c_ulong,
    pub st_size: c_long,
    pub st_blksize: c_int,
    pub __pad2: c_int,
    pub st_blocks: c_long,
    pub st_atim_sec: c_long,
    pub st_atim_nsec: c_long,
    pub st_mtim_sec: c_long,
    pub st_mtim_nsec: c_long,
    pub st_ctim_sec: c_long,
    pub st_ctim_nsec: c_long,
    pub __pad_unused: [c_uint; 2],
}

impl TmStat {
    const fn zeroed() -> Self {
        Self {
            st_dev: 0,
            st_ino: 0,
            st_mode: 0,
            st_nlink: 0,
            st_uid: 0,
            st_gid: 0,
            st_rdev: 0,
            __pad: 0,
            st_size: 0,
            st_blksize: 0,
            __pad2: 0,
            st_blocks: 0,
            st_atim_sec: 0,
            st_atim_nsec: 0,
            st_mtim_sec: 0,
            st_mtim_nsec: 0,
            st_ctim_sec: 0,
            st_ctim_nsec: 0,
            __pad_unused: [0; 2],
        }
    }
}

#[repr(C)]
struct QsoeIpcbuf {
    tag: c_ulong,
    msg: [c_ulong; QSOE_MSG_MAX_LENGTH],
    user_data: c_ulong,
    caps_or_badges: [c_ulong; QSOE_MSG_MAX_EXTRA_CAPS],
    receive_cnode: c_ulong,
    receive_index: c_ulong,
    receive_depth: c_ulong,
}

#[cfg(any(test, feature = "host-tests"))]
impl QsoeIpcbuf {
    const fn zeroed() -> Self {
        Self {
            tag: 0,
            msg: [0; QSOE_MSG_MAX_LENGTH],
            user_data: 0,
            caps_or_badges: [0; QSOE_MSG_MAX_EXTRA_CAPS],
            receive_cnode: 0,
            receive_index: 0,
            receive_depth: 0,
        }
    }
}

#[repr(C)]
#[allow(dead_code)]
struct QsoeTcbPrefix {
    tid: c_int,
    qerrno: c_int,
    cancel_pending: c_int,
    detached: c_int,
    exited: c_int,
    reaped: c_int,
    self_pid: c_int,
    ipcbuf: *mut QsoeIpcbuf,
}

#[cfg(any(test, feature = "host-tests"))]
static mut HOST_IPCBUF: QsoeIpcbuf = QsoeIpcbuf::zeroed();

#[cfg(any(test, feature = "host-tests"))]
unsafe fn ipc_payload_ptr() -> *mut u8 {
    let ipc = core::ptr::addr_of_mut!(HOST_IPCBUF);
    let msg = core::ptr::addr_of_mut!((*ipc).msg) as *mut c_ulong;
    msg.add(4) as *mut u8
}

#[cfg(all(not(any(test, feature = "host-tests")), target_arch = "riscv64"))]
unsafe fn ipc_payload_ptr() -> *mut u8 {
    let tcb: *mut QsoeTcbPrefix;
    core::arch::asm!("mv {}, tp", out(reg) tcb);
    if tcb.is_null() || (*tcb).ipcbuf.is_null() {
        return core::ptr::null_mut();
    }
    let msg = core::ptr::addr_of_mut!((*(*tcb).ipcbuf).msg) as *mut c_ulong;
    msg.add(4) as *mut u8
}

#[cfg(all(not(any(test, feature = "host-tests")), not(target_arch = "riscv64")))]
unsafe fn ipc_payload_ptr() -> *mut u8 {
    core::ptr::null_mut()
}

#[no_mangle]
pub extern "C" fn tm_devnull_write(nbytes: c_uint) -> c_uint {
    nbytes
}

/// Read from `/dev/null`, returning immediate EOF.
///
/// # Safety
///
/// `out_got` may be null. If non-null, it must be valid for one `unsigned`
/// write.
#[no_mangle]
pub unsafe extern "C" fn tm_devnull_read(_want: c_uint, out_got: *mut c_uint) -> c_int {
    if out_got.is_null() {
        return -EINVAL;
    }
    *out_got = 0;
    0
}

/// Fill a caller-provided stat record for `/dev/null`.
///
/// # Safety
///
/// `out` may be null. If non-null, it must point to a writable
/// `tm_stat_t`-compatible record.
#[no_mangle]
pub unsafe extern "C" fn tm_devnull_stat(out: *mut TmStat) -> c_int {
    if out.is_null() {
        return -EINVAL;
    }
    *out = TmStat::zeroed();
    (*out).st_dev = 1;
    (*out).st_ino = 3;
    (*out).st_mode = TM_S_IFCHR | 0o666;
    (*out).st_nlink = 1;
    (*out).st_rdev = (1 << 8) | 3;
    (*out).st_blksize = 4096;
    0
}

#[no_mangle]
pub extern "C" fn tm_devzero_write(nbytes: c_uint) -> c_uint {
    nbytes
}

/// Read zero-filled bytes from `/dev/zero` into taskman's IPC payload.
///
/// # Safety
///
/// `out_got` may be null. If non-null, it must be valid for one `unsigned`
/// write. On target, the current thread's QSOE TCB must expose a valid IPC
/// buffer pointer through the `tp` register.
#[no_mangle]
pub unsafe extern "C" fn tm_devzero_read(want: c_uint, out_got: *mut c_uint) -> c_int {
    if out_got.is_null() {
        return -EINVAL;
    }

    let got = core::cmp::min(want as usize, TM_DEVZERO_MAX_READ);
    let payload = ipc_payload_ptr();
    if payload.is_null() {
        return -EINVAL;
    }
    core::ptr::write_bytes(payload, 0, got);
    *out_got = got as c_uint;
    0
}

/// Fill a caller-provided stat record for `/dev/zero`.
///
/// # Safety
///
/// `out` may be null. If non-null, it must point to a writable
/// `tm_stat_t`-compatible record.
#[no_mangle]
pub unsafe extern "C" fn tm_devzero_stat(out: *mut TmStat) -> c_int {
    if out.is_null() {
        return -EINVAL;
    }
    *out = TmStat::zeroed();
    (*out).st_dev = 1;
    (*out).st_ino = 5;
    (*out).st_mode = TM_S_IFCHR | 0o666;
    (*out).st_nlink = 1;
    (*out).st_rdev = (1 << 8) | 5;
    (*out).st_blksize = 4096;
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::{offset_of, size_of};

    unsafe fn payload_bytes(len: usize) -> &'static mut [u8] {
        core::slice::from_raw_parts_mut(ipc_payload_ptr(), len)
    }

    #[test]
    fn c_abi_layouts_match_headers() {
        assert_eq!(size_of::<c_ulong>(), 8);
        assert_eq!(size_of::<TmStat>(), 128);
        assert_eq!(offset_of!(TmStat, st_dev), 0);
        assert_eq!(offset_of!(TmStat, st_mode), 16);
        assert_eq!(offset_of!(TmStat, st_size), 48);
        assert_eq!(offset_of!(TmStat, st_blksize), 56);
        assert_eq!(offset_of!(QsoeTcbPrefix, ipcbuf), 32);
        assert_eq!(TM_DEVZERO_MAX_READ, 928);
    }

    #[test]
    fn devnull_discards_writes_and_reads_eof() {
        let mut got = 99;
        assert_eq!(tm_devnull_write(123), 123);
        assert_eq!(unsafe { tm_devnull_read(64, &mut got) }, 0);
        assert_eq!(got, 0);
        assert_eq!(
            unsafe { tm_devnull_read(64, core::ptr::null_mut()) },
            -EINVAL
        );
    }

    #[test]
    fn devzero_discards_writes_and_zero_fills_ipc_payload() {
        unsafe {
            let bytes = payload_bytes(TM_DEVZERO_MAX_READ);
            bytes.fill(0xaa);
        }

        let mut got = 0;
        assert_eq!(tm_devzero_write(55), 55);
        assert_eq!(unsafe { tm_devzero_read(16, &mut got) }, 0);
        assert_eq!(got, 16);

        unsafe {
            let bytes = payload_bytes(32);
            assert!(bytes[..16].iter().all(|b| *b == 0));
            assert!(bytes[16..].iter().all(|b| *b == 0xaa));
        }

        assert_eq!(unsafe { tm_devzero_read(4096, &mut got) }, 0);
        assert_eq!(got as usize, TM_DEVZERO_MAX_READ);
        assert_eq!(
            unsafe { tm_devzero_read(1, core::ptr::null_mut()) },
            -EINVAL
        );
    }

    #[test]
    fn stat_records_match_c_devices() {
        let mut st = TmStat::zeroed();
        assert_eq!(unsafe { tm_devnull_stat(&mut st) }, 0);
        assert_eq!(st.st_dev, 1);
        assert_eq!(st.st_ino, 3);
        assert_eq!(st.st_mode, TM_S_IFCHR | 0o666);
        assert_eq!(st.st_nlink, 1);
        assert_eq!(st.st_rdev, (1 << 8) | 3);
        assert_eq!(st.st_blksize, 4096);
        assert_eq!(st.st_size, 0);

        assert_eq!(unsafe { tm_devzero_stat(&mut st) }, 0);
        assert_eq!(st.st_dev, 1);
        assert_eq!(st.st_ino, 5);
        assert_eq!(st.st_mode, TM_S_IFCHR | 0o666);
        assert_eq!(st.st_nlink, 1);
        assert_eq!(st.st_rdev, (1 << 8) | 5);
        assert_eq!(st.st_blksize, 4096);
        assert_eq!(unsafe { tm_devzero_stat(core::ptr::null_mut()) }, -EINVAL);
    }
}
