#![no_std]

use core::ffi::{c_char, c_int, c_uint, c_void};

pub use qsoe_abi::{
    GidT, ModeT, OffT, PidT, QsoeClientInfo, QsoeCredInfo, QsoeMsgInfo, QsoePulse, SizeT, SsizeT,
    UidT,
};

unsafe extern "C" {
    #[link_name = "ChannelCreate"]
    pub fn channel_create(flags: c_uint) -> c_int;
    #[link_name = "ChannelDestroy"]
    pub fn channel_destroy(chid: c_int) -> c_int;

    #[link_name = "ConnectAttach"]
    pub fn connect_attach(nd: u32, pid: PidT, chid: c_int, index: c_uint, flags: c_int) -> c_int;
    #[link_name = "ConnectDetach"]
    pub fn connect_detach(coid: c_int) -> c_int;
    #[link_name = "ConnectAttach_r"]
    pub fn connect_attach_r(nd: u32, pid: PidT, chid: c_int, index: c_uint, flags: c_int) -> isize;
    #[link_name = "ConnectDetach_r"]
    pub fn connect_detach_r(coid: c_int) -> isize;

    #[link_name = "MsgSend"]
    pub fn msg_send(
        coid: c_int,
        smsg: *const c_void,
        sbytes: c_int,
        rmsg: *mut c_void,
        rbytes: c_int,
    ) -> c_int;
    #[link_name = "MsgReceive"]
    pub fn msg_receive(
        chid: c_int,
        msg: *mut c_void,
        bytes: c_int,
        info: *mut QsoeMsgInfo,
    ) -> c_int;
    #[link_name = "MsgReply"]
    pub fn msg_reply(rcvid: c_int, status: c_int, msg: *const c_void, bytes: c_int) -> c_int;
    #[link_name = "MsgSavereply"]
    pub fn msg_save_reply(rcvid: c_int) -> c_int;
    #[link_name = "MsgSendPulse"]
    pub fn msg_send_pulse(coid: c_int, priority: c_int, code: c_int, value: c_int) -> c_int;

    #[link_name = "MsgSend_r"]
    pub fn msg_send_r(
        coid: c_int,
        smsg: *const c_void,
        sbytes: c_int,
        rmsg: *mut c_void,
        rbytes: c_int,
    ) -> isize;
    #[link_name = "MsgReceive_r"]
    pub fn msg_receive_r(
        chid: c_int,
        msg: *mut c_void,
        bytes: c_int,
        info: *mut QsoeMsgInfo,
    ) -> isize;
    #[link_name = "MsgReply_r"]
    pub fn msg_reply_r(rcvid: c_int, status: c_int, msg: *const c_void, bytes: c_int) -> isize;
    #[link_name = "MsgSendPulse_r"]
    pub fn msg_send_pulse_r(coid: c_int, priority: c_int, code: c_int, value: c_int) -> isize;

    #[link_name = "procmgr_detach"]
    pub fn procmgr_detach(status: c_int) -> c_int;

    #[link_name = "qsoe_pathmgr_register"]
    pub fn pathmgr_register(path: *const c_char, chid: c_int) -> c_int;
    #[link_name = "qsoe_pathmgr_resolve"]
    pub fn pathmgr_resolve(
        path: *const c_char,
        out_pid: *mut PidT,
        out_chid: *mut c_int,
        out_kind: *mut c_uint,
    ) -> c_int;

    #[link_name = "qsoe_dbg_write"]
    pub fn dbg_write(buf: *const c_char, len: usize);

    #[link_name = "qsoe_mmap"]
    pub fn qsoe_mmap(
        addr: *mut c_void,
        length: usize,
        prot: c_int,
        flags: c_int,
        fd: c_int,
        off: OffT,
    ) -> *mut c_void;
    #[link_name = "qsoe_alloc_phys"]
    pub fn qsoe_alloc_phys(length: usize, prot: c_int, pa_out: *mut u64) -> *mut c_void;

    #[link_name = "munmap"]
    pub fn munmap(addr: *mut c_void, length: usize) -> c_int;

    #[link_name = "sched_yield"]
    pub fn sched_yield() -> c_int;
}
