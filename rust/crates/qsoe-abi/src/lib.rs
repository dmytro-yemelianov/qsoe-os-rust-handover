#![no_std]

use core::ffi::c_void;

pub type PidT = i32;
pub type ModeT = u32;
pub type UidT = u32;
pub type GidT = u32;
pub type OffT = i64;
pub type SizeT = usize;
pub type SsizeT = isize;
pub type QsoeTimeT = u64;

pub const EOK: i32 = 0;
pub const EIO: i32 = 5;
pub const EBUSY: i32 = 15;
pub const ENODEV: i32 = 18;
pub const EINVAL: i32 = 21;
pub const ENOSYS: i32 = 37;

pub const TASKMAN_PID: i32 = 1;
pub const QSOE_SIDE_CHANNEL: u32 = 0x4000_0000;
pub const TASKMAN_COID: i32 = QSOE_SIDE_CHANNEL as i32;
pub const TASKMAN_CHID: u32 = (1 << 16) | 1;
pub const QSOE_MSG_MAX_LENGTH: usize = 120;
pub const QSOE_MSG_MAX_EXTRA_CAPS: usize = 3;
pub const ND_LOCAL_NODE: u32 = 0;
pub const QSOE_MI_PULSE: u32 = 0x0000_0010;
pub const QSOE_RCVID_SAVED: u32 = 0x8000_0000;
pub const PULSE_TYPE: u16 = 0;

pub const IO_CONNECT: u64 = 0x302;
pub const IO_CLOSE: u64 = 0x303;
pub const IO_WRITE: u64 = 0x304;
pub const IO_READ: u64 = 0x305;
pub const IO_FSTAT: u64 = 0x307;
pub const IO_LSEEK: u64 = 0x309;
pub const IO_READDIR: u64 = 0x30a;
pub const IO_DUP: u64 = 0x30e;

pub const TM_REQ_OPEN: u64 = IO_CONNECT;
pub const TM_REQ_CLOSE: u64 = IO_CLOSE;
pub const TM_REQ_IO_WRITE: u64 = IO_WRITE;
pub const TM_REQ_IO_READ: u64 = IO_READ;
pub const TM_REQ_FSTAT: u64 = IO_FSTAT;
pub const TM_REQ_LSEEK: u64 = IO_LSEEK;
pub const TM_REQ_READDIR: u64 = IO_READDIR;

pub const TM_WIRE_HDR_BYTES: usize = 8;
pub const TM_WIRE_SCALARS: usize = 4;
pub const TM_WIRE_BASE_BYTES: usize = TM_WIRE_HDR_BYTES + TM_WIRE_SCALARS * 8;
pub const TM_IO_MAX: usize = 896;

pub const TM_S_IFMT: ModeT = 0o170000;
pub const TM_S_IFREG: ModeT = 0o100000;
pub const TM_S_IFCHR: ModeT = 0o020000;
pub const TM_S_IFBLK: ModeT = 0o060000;
pub const TM_S_IFDIR: ModeT = 0o040000;

pub const QSOE_RUST_SPIKE_MARKER: u64 = 0x5153_4f45_5255_5354;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct QsoeMsgInfo {
    pub nd: u32,
    pub pid: PidT,
    pub chid: i32,
    pub scoid: i32,
    pub coid: i32,
    pub msglen: i32,
    pub srcmsglen: i32,
    pub dstmsglen: i32,
    pub priority: i32,
    pub flags: i32,
    pub label: u32,
}

impl QsoeMsgInfo {
    pub const fn zeroed() -> Self {
        Self {
            nd: 0,
            pid: 0,
            chid: 0,
            scoid: 0,
            coid: 0,
            msglen: 0,
            srcmsglen: 0,
            dstmsglen: 0,
            priority: 0,
            flags: 0,
            label: 0,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct QsoeCredInfo {
    pub ruid: UidT,
    pub euid: UidT,
    pub suid: UidT,
    pub rgid: GidT,
    pub egid: GidT,
    pub sgid: GidT,
    pub ngroups: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct QsoeClientInfo {
    pub nd: u32,
    pub pid: PidT,
    pub sid: PidT,
    pub flags: u32,
    pub cred: QsoeCredInfo,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union QsoePulseValue {
    pub sival_int: i32,
    pub sival_ptr: *mut c_void,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct QsoePulse {
    pub type_: u16,
    pub subtype: u16,
    pub code: i8,
    pub reserved: [u8; 3],
    pub value: QsoePulseValue,
    pub scoid: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TmStat {
    pub st_dev: u64,
    pub st_ino: u64,
    pub st_mode: u32,
    pub st_nlink: u32,
    pub st_uid: u32,
    pub st_gid: u32,
    pub st_rdev: u64,
    pub pad: u64,
    pub st_size: i64,
    pub st_blksize: i32,
    pub pad2: i32,
    pub st_blocks: i64,
    pub st_atim_sec: i64,
    pub st_atim_nsec: i64,
    pub st_mtim_sec: i64,
    pub st_mtim_nsec: i64,
    pub st_ctim_sec: i64,
    pub st_ctim_nsec: i64,
    pub pad_unused: [u32; 2],
}

impl TmStat {
    pub const fn zeroed() -> Self {
        Self {
            st_dev: 0,
            st_ino: 0,
            st_mode: 0,
            st_nlink: 0,
            st_uid: 0,
            st_gid: 0,
            st_rdev: 0,
            pad: 0,
            st_size: 0,
            st_blksize: 0,
            pad2: 0,
            st_blocks: 0,
            st_atim_sec: 0,
            st_atim_nsec: 0,
            st_mtim_sec: 0,
            st_mtim_nsec: 0,
            st_ctim_sec: 0,
            st_ctim_nsec: 0,
            pad_unused: [0; 2],
        }
    }
}

#[cfg(test)]
extern crate std;

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::{align_of, size_of};

    #[test]
    fn qsoe_message_layouts_match_rv64_c_abi() {
        assert_eq!(size_of::<QsoeMsgInfo>(), 44);
        assert_eq!(align_of::<QsoeMsgInfo>(), 4);
        assert_eq!(size_of::<QsoeCredInfo>(), 28);
        assert_eq!(align_of::<QsoeCredInfo>(), 4);
        assert_eq!(size_of::<QsoeClientInfo>(), 44);
        assert_eq!(align_of::<QsoeClientInfo>(), 4);
        assert_eq!(size_of::<QsoePulse>(), 24);
        assert_eq!(align_of::<QsoePulse>(), 8);
        assert_eq!(size_of::<TmStat>(), 128);
        assert_eq!(align_of::<TmStat>(), 8);
    }

    #[test]
    fn qsoe_io_constants_match_c_headers() {
        assert_eq!(EOK, 0);
        assert_eq!(EIO, 5);
        assert_eq!(EBUSY, 15);
        assert_eq!(ENODEV, 18);
        assert_eq!(EINVAL, 21);
        assert_eq!(ENOSYS, 37);
        assert_eq!(TM_WIRE_BASE_BYTES, 40);
        assert_eq!(TM_IO_MAX, 896);
        assert_eq!(TM_REQ_IO_WRITE, 0x304);
        assert_eq!(TM_REQ_IO_READ, 0x305);
        assert_eq!(TM_REQ_FSTAT, 0x307);
        assert_eq!(TM_REQ_CLOSE, 0x303);
        assert_eq!(TM_S_IFCHR, 0o020000);
        assert_eq!(TM_S_IFBLK, 0o060000);
    }
}
