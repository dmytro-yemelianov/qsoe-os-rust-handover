#![no_std]

use core::convert::TryFrom;
use core::ffi::{c_char, c_int, c_uint, c_void, CStr};
use core::mem::size_of;
use core::ptr;
use core::slice;

pub use qsoe_abi::{
    GidT, ModeT, OffT, QsoeMsgInfo, QsoeTimeT, SizeT, SsizeT, TmStat, UidT, IO_CLOSE, IO_CONNECT,
    IO_DUP, IO_FSTAT, IO_READ, IO_READDIR, IO_WRITE, QSOE_MI_PULSE, TM_IO_MAX, TM_REQ_CLOSE,
    TM_REQ_FSTAT, TM_REQ_IO_READ, TM_REQ_IO_WRITE, TM_S_IFCHR, TM_WIRE_BASE_BYTES,
};

pub const QSOE_ATTR_MODE: c_uint = 0x01;
pub const QSOE_ATTR_UID: c_uint = 0x02;
pub const QSOE_ATTR_GID: c_uint = 0x04;
pub const QSOE_ATTR_SIZE: c_uint = 0x08;
pub const QSOE_ATTR_TIME: c_uint = 0x10;

pub const QSOE_POLLIN: c_uint = 0x01;
pub const QSOE_POLLOUT: c_uint = 0x02;
pub const QSOE_POLLERR: c_uint = 0x04;
pub const QSOE_POLLHUP: c_uint = 0x08;

pub const QSOE_PROV_PARALLEL: c_uint = 0x01;
pub const QSOE_PROV_NOATIME: c_uint = 0x02;

pub const QSOE_ERRNO_MAX: c_int = 1023;
pub const QSOE_DEFER: c_int = -(QSOE_ERRNO_MAX + 1);
pub const QSOE_MAX_PROVIDERS: usize = 32;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Attr {
    pub mode: ModeT,
    pub uid: UidT,
    pub gid: GidT,
    pub size: OffT,
    pub ino: u64,
    pub rdev: u64,
    pub nlink: c_uint,
    pub atime: QsoeTimeT,
    pub mtime: QsoeTimeT,
    pub ctime: QsoeTimeT,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Open {
    pub subpath: *const c_char,
    pub oflags: c_uint,
    pub mode: ModeT,
    pub uid: UidT,
    pub gid: GidT,
}

#[repr(C)]
pub struct Handle {
    prov: *mut Provider,
    pos: OffT,
    oflags: c_uint,
    udata: *mut c_void,
    fw: *mut c_void,
}

impl Handle {
    pub fn provider(&self) -> *mut Provider {
        self.prov
    }

    pub fn pos(&self) -> OffT {
        self.pos
    }

    pub fn oflags(&self) -> c_uint {
        self.oflags
    }

    pub fn udata(&self) -> *mut c_void {
        self.udata
    }

    pub fn set_udata(&mut self, value: *mut c_void) {
        self.udata = value;
    }
}

pub type AcquireFn = unsafe extern "C" fn(*mut Provider, *mut Handle, *const Open) -> c_int;
pub type ReleaseFn = unsafe extern "C" fn(*mut Provider, *mut Handle);
pub type PullFn =
    unsafe extern "C" fn(*mut Provider, *mut Handle, *mut c_void, SizeT, OffT) -> SsizeT;
pub type PushFn =
    unsafe extern "C" fn(*mut Provider, *mut Handle, *const c_void, SizeT, OffT) -> SsizeT;
pub type SeekFn = unsafe extern "C" fn(*mut Provider, *mut Handle, OffT, c_int) -> OffT;
pub type QueryFn = unsafe extern "C" fn(*mut Provider, *mut Handle, *mut Attr) -> c_int;
pub type AdjustFn = unsafe extern "C" fn(*mut Provider, *mut Handle, *const Attr, c_uint) -> c_int;
pub type ControlFn =
    unsafe extern "C" fn(*mut Provider, *mut Handle, c_uint, *mut c_void, SizeT, SizeT) -> SsizeT;
pub type ReadyFn = unsafe extern "C" fn(*mut Provider, *mut Handle, c_uint) -> c_int;
pub type ServiceFn = unsafe extern "C" fn(*mut Provider);
pub type CancelFn = unsafe extern "C" fn(*mut Provider, *mut Handle);
pub type LookupFn = unsafe extern "C" fn(*mut Provider, *const c_char, *mut *mut Provider) -> c_int;
pub type ListFn =
    unsafe extern "C" fn(*mut Provider, *mut Handle, *mut c_void, SizeT, OffT) -> SsizeT;
pub type MakeFn =
    unsafe extern "C" fn(*mut Provider, *const c_char, ModeT, *mut *mut Provider) -> c_int;
pub type UnlinkFn = unsafe extern "C" fn(*mut Provider, *const c_char) -> c_int;
pub type DupFn = unsafe extern "C" fn(*mut Provider, *mut Handle, *const Handle) -> c_int;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct ProviderVtable {
    pub acquire: Option<AcquireFn>,
    pub release: Option<ReleaseFn>,
    pub pull: Option<PullFn>,
    pub push: Option<PushFn>,
    pub seek: Option<SeekFn>,
    pub query: Option<QueryFn>,
    pub adjust: Option<AdjustFn>,
    pub control: Option<ControlFn>,
    pub ready: Option<ReadyFn>,
    pub service: Option<ServiceFn>,
    pub cancel: Option<CancelFn>,
    pub lookup: Option<LookupFn>,
    pub list: Option<ListFn>,
    pub make: Option<MakeFn>,
    pub unlink: Option<UnlinkFn>,
    pub dup: Option<DupFn>,
}

#[repr(C)]
pub struct Provider {
    pub cls: *const ProviderVtable,
    pub attr: Attr,
    pub path: *const c_char,
    pub flags: c_uint,
    fw_chid: c_int,
    fw_refs: c_uint,
}

impl Provider {
    pub const fn zeroed() -> Self {
        Self {
            cls: core::ptr::null(),
            attr: Attr {
                mode: 0,
                uid: 0,
                gid: 0,
                size: 0,
                ino: 0,
                rdev: 0,
                nlink: 0,
                atime: 0,
                mtime: 0,
                ctime: 0,
            },
            path: core::ptr::null(),
            flags: 0,
            fw_chid: -1,
            fw_refs: 0,
        }
    }

    /// Initialize provider storage through the C framework.
    ///
    /// # Safety
    ///
    /// `vtbl` and `path` must remain valid for at least as long as the
    /// provider can be reached from the QSOE path manager or dispatch loop.
    pub unsafe fn init(&mut self, vtbl: *const ProviderVtable, path: *const c_char, mode: ModeT) {
        // SAFETY: the caller promises that `vtbl` and `path` satisfy the C
        // framework lifetime contract described above.
        unsafe { qsoe_provider_init(self, vtbl, path, mode) };
    }

    pub fn listen(&mut self) -> Result<(), c_int> {
        // SAFETY: `self` is valid provider storage; the C framework validates
        // whether it was initialized enough to publish.
        let rc = unsafe { qsoe_provider_listen(self) };
        if rc == 0 {
            Ok(())
        } else {
            Err(-rc)
        }
    }

    pub fn dispatch_run(&mut self) -> c_int {
        // SAFETY: The C dispatcher owns the receive loop after this call.
        unsafe { qsoe_dispatch_run(self) }
    }
}

#[repr(C)]
pub struct Server {
    pub chid: c_int,
    pub nprovs: c_uint,
    pub provs: [*mut Provider; QSOE_MAX_PROVIDERS],
}

impl Server {
    pub const fn zeroed() -> Self {
        Self {
            chid: -1,
            nprovs: 0,
            provs: [core::ptr::null_mut(); QSOE_MAX_PROVIDERS],
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DirectError {
    ChannelCreateFailed(c_int),
    ChannelDestroyFailed(c_int),
    PathRegisterFailed(c_int),
    DetachFailed(c_int),
    ReceiveFailed(c_int),
    ReplyFailed(c_int),
    MessageTooLarge(usize),
    ReplyPrefixTooLarge { requested: usize, max: usize },
}

pub type DirectResult<T> = Result<T, DirectError>;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ReplyStatus(c_int);

impl ReplyStatus {
    pub const OK: Self = Self(0);

    pub const fn from_raw(status: c_int) -> Self {
        Self(status)
    }

    pub const fn from_errno(errno: c_int) -> Self {
        Self(errno)
    }

    pub const fn raw(self) -> c_int {
        self.0
    }
}

pub struct Channel {
    chid: c_int,
}

impl Channel {
    pub fn create(flags: c_uint) -> DirectResult<Self> {
        // SAFETY: `ChannelCreate` takes a scalar flag word and returns a
        // process-local channel id or -1 with qsoe_errno set.
        let chid = unsafe { qsoe_ffi::channel_create(flags) };
        if chid >= 0 {
            Ok(Self { chid })
        } else {
            Err(DirectError::ChannelCreateFailed(chid))
        }
    }

    /// Take ownership of an already-created QSOE channel id.
    ///
    /// # Safety
    ///
    /// `chid` must be a live channel owned by this process, and no other Rust
    /// value may destroy it while the returned `Channel` exists.
    pub unsafe fn from_raw(chid: c_int) -> Self {
        Self { chid }
    }

    pub const fn id(&self) -> c_int {
        self.chid
    }

    pub fn register_path(&self, path: &CStr) -> DirectResult<()> {
        // SAFETY: `CStr` guarantees a non-null, NUL-terminated path pointer for
        // the duration of this call; `self.chid` is owned by this wrapper.
        let rc = unsafe { qsoe_ffi::pathmgr_register(path.as_ptr(), self.chid) };
        if rc == 0 {
            Ok(())
        } else {
            Err(DirectError::PathRegisterFailed(rc))
        }
    }

    pub fn receive_bytes(&self, buf: &mut [u8]) -> DirectResult<Receive> {
        let len = usize_to_c_int(buf.len())?;
        let mut info = QsoeMsgInfo::zeroed();
        // SAFETY: `buf` is valid writable storage of `len` bytes and `info`
        // points to valid message-info storage for the duration of the call.
        let rcvid = unsafe {
            qsoe_ffi::msg_receive(self.chid, buf.as_mut_ptr().cast::<c_void>(), len, &mut info)
        };

        if rcvid < 0 {
            return Err(DirectError::ReceiveFailed(rcvid));
        }
        if rcvid == 0 || (info.flags as u32 & QSOE_MI_PULSE) != 0 {
            return Ok(Receive::Pulse(info));
        }

        Ok(Receive::Message(ReceivedMessage { rcvid, info }))
    }

    pub fn receive_request(&self, req: &mut IoRequest) -> DirectResult<Receive> {
        // SAFETY: `IoRequest` is a plain `repr(C)` integer/byte buffer with no
        // padding, verified by layout tests below.
        let buf = unsafe {
            slice::from_raw_parts_mut((req as *mut IoRequest).cast::<u8>(), size_of::<IoRequest>())
        };
        self.receive_bytes(buf)
    }

    pub fn destroy(mut self) -> DirectResult<()> {
        let rc = self.destroy_inner();
        if rc == 0 {
            Ok(())
        } else {
            Err(DirectError::ChannelDestroyFailed(rc))
        }
    }

    fn destroy_inner(&mut self) -> c_int {
        if self.chid < 0 {
            return 0;
        }
        let chid = self.chid;
        // SAFETY: this wrapper owns `chid`; after a successful destroy it marks
        // the channel as retired so Drop will not destroy it again.
        let rc = unsafe { qsoe_ffi::channel_destroy(chid) };
        if rc == 0 {
            self.chid = -1;
        }
        rc
    }
}

impl Drop for Channel {
    fn drop(&mut self) {
        let _ = self.destroy_inner();
    }
}

pub struct DirectService {
    channel: Channel,
}

impl DirectService {
    pub fn register(path: &CStr) -> DirectResult<Self> {
        let channel = Channel::create(0)?;
        channel.register_path(path)?;
        Ok(Self { channel })
    }

    pub const fn from_channel(channel: Channel) -> Self {
        Self { channel }
    }

    pub const fn channel_id(&self) -> c_int {
        self.channel.id()
    }

    pub fn detach_ready(&self, status: c_int) -> DirectResult<()> {
        // SAFETY: `procmgr_detach` takes a scalar status value and does not
        // retain borrowed Rust state.
        let rc = unsafe { qsoe_ffi::procmgr_detach(status) };
        if rc == 0 {
            Ok(())
        } else {
            Err(DirectError::DetachFailed(rc))
        }
    }

    pub fn receive_bytes(&self, buf: &mut [u8]) -> DirectResult<Receive> {
        self.channel.receive_bytes(buf)
    }

    pub fn receive_request(&self, req: &mut IoRequest) -> DirectResult<Receive> {
        self.channel.receive_request(req)
    }

    pub fn shutdown(self) -> DirectResult<()> {
        self.channel.destroy()
    }
}

pub enum Receive {
    Message(ReceivedMessage),
    Pulse(QsoeMsgInfo),
}

#[derive(Debug, Eq, PartialEq)]
pub struct ReceivedMessage {
    rcvid: c_int,
    info: QsoeMsgInfo,
}

impl ReceivedMessage {
    pub const fn rcvid(&self) -> c_int {
        self.rcvid
    }

    pub const fn info(&self) -> &QsoeMsgInfo {
        &self.info
    }

    pub fn reply_empty(self, status: ReplyStatus) -> DirectResult<()> {
        self.reply_raw(status, ptr::null(), 0)
    }

    pub fn reply_word(self, status: ReplyStatus, word: u64) -> DirectResult<()> {
        self.reply_raw(
            status,
            (&word as *const u64).cast::<c_void>(),
            size_of::<u64>(),
        )
    }

    pub fn reply_bytes(self, status: ReplyStatus, bytes: &[u8]) -> DirectResult<()> {
        let ptr = if bytes.is_empty() {
            ptr::null()
        } else {
            bytes.as_ptr().cast::<c_void>()
        };
        self.reply_raw(status, ptr, bytes.len())
    }

    fn reply_raw(self, status: ReplyStatus, msg: *const c_void, bytes: usize) -> DirectResult<()> {
        let len = usize_to_c_int(bytes)?;
        // SAFETY: `rcvid` came from a successful `MsgReceive` call. `msg` is
        // either null for an empty reply or points to `len` readable bytes for
        // the duration of the synchronous `MsgReply` call.
        let rc = unsafe { qsoe_ffi::msg_reply(self.rcvid, status.raw(), msg, len) };
        if rc == 0 {
            Ok(())
        } else {
            Err(DirectError::ReplyFailed(rc))
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct IoRequest {
    pub type_: u64,
    pub count: u64,
    pub reserved: [u64; 3],
    pub data: [u8; TM_IO_MAX],
}

impl IoRequest {
    pub const fn zeroed() -> Self {
        Self {
            type_: 0,
            count: 0,
            reserved: [0; 3],
            data: [0; TM_IO_MAX],
        }
    }

    pub const fn opcode(&self) -> u64 {
        self.type_
    }

    pub const fn requested_count(&self) -> u64 {
        self.count
    }

    pub fn payload_prefix(&self) -> &[u8] {
        let len = core::cmp::min(self.count as usize, TM_IO_MAX);
        &self.data[..len]
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct IoReply {
    pub count: u64,
    pub reserved: [u64; 3],
    pub data: [u8; TM_IO_MAX],
}

impl IoReply {
    pub const HEADER_BYTES: usize = 4 * size_of::<u64>();

    pub const fn zeroed() -> Self {
        Self {
            count: 0,
            reserved: [0; 3],
            data: [0; TM_IO_MAX],
        }
    }

    pub fn data_mut(&mut self) -> &mut [u8; TM_IO_MAX] {
        &mut self.data
    }

    pub fn bytes_with_payload(&self, payload_len: usize) -> DirectResult<&[u8]> {
        if payload_len > TM_IO_MAX {
            return Err(DirectError::ReplyPrefixTooLarge {
                requested: payload_len,
                max: TM_IO_MAX,
            });
        }

        let total = Self::HEADER_BYTES + payload_len;
        // SAFETY: `IoReply` is a `repr(C)` integer/byte buffer with no padding,
        // verified by layout tests below. `total` is bounded to the initialized
        // header plus initialized `data` bytes.
        Ok(unsafe { slice::from_raw_parts((self as *const IoReply).cast::<u8>(), total) })
    }
}

fn usize_to_c_int(value: usize) -> DirectResult<c_int> {
    c_int::try_from(value).map_err(|_| DirectError::MessageTooLarge(value))
}

#[repr(C)]
pub struct Call {
    _private: [u8; 0],
}

unsafe extern "C" {
    pub fn qsoe_default_acquire(self_: *mut Provider, h: *mut Handle, req: *const Open) -> c_int;
    pub fn qsoe_default_release(self_: *mut Provider, h: *mut Handle);
    pub fn qsoe_default_seek(
        self_: *mut Provider,
        h: *mut Handle,
        off: OffT,
        whence: c_int,
    ) -> OffT;
    pub fn qsoe_default_query(self_: *mut Provider, h: *mut Handle, out: *mut Attr) -> c_int;
    pub fn qsoe_default_adjust(
        self_: *mut Provider,
        h: *mut Handle,
        set: *const Attr,
        which: c_uint,
    ) -> c_int;

    pub fn qsoe_provider_init(
        p: *mut Provider,
        vtbl: *const ProviderVtable,
        path: *const c_char,
        mode: ModeT,
    );
    pub fn qsoe_provider_listen(p: *mut Provider) -> c_int;
    pub fn qsoe_provider_retire(p: *mut Provider) -> c_int;
    pub fn qsoe_dispatch_run(p: *mut Provider) -> c_int;

    pub fn qsoe_server_init(s: *mut Server) -> c_int;
    pub fn qsoe_server_publish(s: *mut Server, p: *mut Provider) -> c_int;
    pub fn qsoe_server_run(s: *mut Server) -> c_int;

    pub fn qsoe_defer() -> *mut Call;
    pub fn qsoe_done(call: *mut Call, status: SsizeT);
    pub fn qsoe_reply(call: *mut Call, buf: *const c_void, n: SizeT);
    pub fn qsoe_fail(call: *mut Call, err: c_int);
}

#[cfg(test)]
extern crate std;

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::{align_of, size_of};

    #[test]
    fn resource_server_layouts_match_rv64_c_abi() {
        assert_eq!(size_of::<Attr>(), 72);
        assert_eq!(align_of::<Attr>(), 8);
        assert_eq!(size_of::<Open>(), 24);
        assert_eq!(align_of::<Open>(), 8);
        assert_eq!(size_of::<Handle>(), 40);
        assert_eq!(align_of::<Handle>(), 8);
        assert_eq!(size_of::<ProviderVtable>(), 128);
        assert_eq!(align_of::<ProviderVtable>(), 8);
        assert_eq!(size_of::<Provider>(), 104);
        assert_eq!(align_of::<Provider>(), 8);
        assert_eq!(size_of::<Server>(), 264);
        assert_eq!(align_of::<Server>(), 8);
    }

    #[test]
    fn direct_io_layouts_match_slogger_wire_shapes() {
        assert_eq!(TM_WIRE_BASE_BYTES, 40);
        assert_eq!(TM_IO_MAX, 896);
        assert_eq!(size_of::<IoRequest>(), 936);
        assert_eq!(align_of::<IoRequest>(), 8);
        assert_eq!(size_of::<IoReply>(), 928);
        assert_eq!(align_of::<IoReply>(), 8);
        assert_eq!(IoReply::HEADER_BYTES, 32);
    }

    #[test]
    fn io_request_payload_is_capped_to_inline_payload() {
        let mut req = IoRequest::zeroed();
        req.count = (TM_IO_MAX as u64) + 128;
        assert_eq!(req.payload_prefix().len(), TM_IO_MAX);
    }

    #[test]
    fn io_reply_exposes_only_requested_prefix() {
        let reply = IoReply::zeroed();
        assert_eq!(reply.bytes_with_payload(0).unwrap().len(), 32);
        assert_eq!(reply.bytes_with_payload(17).unwrap().len(), 49);
        assert_eq!(
            reply.bytes_with_payload(TM_IO_MAX + 1),
            Err(DirectError::ReplyPrefixTooLarge {
                requested: TM_IO_MAX + 1,
                max: TM_IO_MAX,
            })
        );
    }
}
