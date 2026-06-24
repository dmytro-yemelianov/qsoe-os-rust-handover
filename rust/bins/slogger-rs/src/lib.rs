#![no_std]

use core::cell::UnsafeCell;
use core::ffi::{c_char, CStr};
use core::mem::size_of;
use core::panic::PanicInfo;
use core::slice;

use qsoe_ressrv::{
    DirectRequestHandler, DirectServer, IoReply, IoRequest, ReceivedMessage, ReplyStatus, TmStat,
    ENOSYS, IO_CONNECT, IO_DUP, TM_IO_MAX, TM_REQ_CLOSE, TM_REQ_FSTAT, TM_REQ_IO_READ,
    TM_REQ_IO_WRITE, TM_S_IFCHR,
};
use qsoe_slogger::SlogRing;

const SLOG_PATH: &[u8] = b"/dev/slog\0";
const DEFAULT_READ_BYTES: usize = 928;

struct RingCell(UnsafeCell<SlogRing>);

// SAFETY: `slogger-rs` is a single-threaded resource-server pilot. The receive
// loop below takes the only mutable reference to this process-global ring.
unsafe impl Sync for RingCell {}

impl RingCell {
    const fn new() -> Self {
        Self(UnsafeCell::new(SlogRing::new()))
    }

    fn get(&self) -> *mut SlogRing {
        self.0.get()
    }
}

static RING: RingCell = RingCell::new();

struct Slogger {
    ring: &'static mut SlogRing,
}

impl DirectRequestHandler for Slogger {
    fn handle_message(&mut self, message: ReceivedMessage, req: &IoRequest) {
        handle_message(message, req, self.ring);
    }
}

#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    debug_write(b"[slogger-rs] panic\n");
    loop {
        core::hint::spin_loop();
    }
}

#[no_mangle]
pub extern "C" fn qsoe_slogger_rust_marker() -> u64 {
    0x5153_4f45_534c_4f47
}

#[no_mangle]
pub extern "C" fn main(_argc: isize, _argv: *const *const u8, _envp: *const *const u8) -> i32 {
    debug_write(b"[slogger-rs] alive\n");

    // SAFETY: see `RingCell`'s `Sync` safety note. This function never returns,
    // so no second mutable borrow is created.
    let ring = unsafe { &mut *RING.get() };
    let mut server = match DirectServer::register(slog_path(), Slogger { ring }) {
        Ok(server) => server,
        Err(_) => {
            debug_write(b"[slogger-rs] register failed\n");
            return 1;
        }
    };

    debug_write(b"[slogger-rs] /dev/slog registered\n");

    if server.detach_ready(0).is_err() {
        debug_write(b"[slogger-rs] procmgr_detach failed\n");
    }

    debug_write(b"[slogger-rs] entering MsgReceive loop\n");
    server.run()
}

fn slog_path() -> &'static CStr {
    // SAFETY: `SLOG_PATH` is a static byte string with exactly one trailing NUL
    // and no interior NUL bytes.
    unsafe { CStr::from_bytes_with_nul_unchecked(SLOG_PATH) }
}

fn handle_message(message: ReceivedMessage, req: &IoRequest, ring: &mut SlogRing) {
    match req.opcode() {
        TM_REQ_IO_WRITE => reply_to_write(message, req, ring),
        TM_REQ_IO_READ => reply_to_read(message, req, ring),
        TM_REQ_FSTAT => reply_to_fstat(message),
        IO_CONNECT | IO_DUP | TM_REQ_CLOSE => {
            let _ = message.reply_empty(ReplyStatus::OK);
        }
        _ => {
            let _ = message.reply_empty(ReplyStatus::from_errno(ENOSYS));
        }
    }
}

fn reply_to_write(message: ReceivedMessage, req: &IoRequest, ring: &mut SlogRing) {
    let payload = req.payload_prefix();
    let consumed = payload.len() as u64;
    let _ = ring.append(payload);
    let _ = message.reply_word(ReplyStatus::OK, consumed);
}

fn reply_to_read(message: ReceivedMessage, req: &IoRequest, ring: &mut SlogRing) {
    let want = requested_read_len(req);
    let mut reply = IoReply::zeroed();
    let got = ring.drain(&mut reply.data_mut()[..want]);
    reply.count = got as u64;
    reply_with_payload(message, &reply, got);
}

fn reply_to_fstat(message: ReceivedMessage) {
    let mut reply = IoReply::zeroed();
    let mut stat = TmStat::zeroed();
    stat.st_dev = 7;
    stat.st_ino = 1;
    stat.st_mode = TM_S_IFCHR | 0o666;
    stat.st_nlink = 1;
    stat.st_rdev = (10_u64 << 8) | 100;
    stat.st_blksize = 256;

    let stat_len = size_of::<TmStat>();
    // SAFETY: `TmStat` is a `repr(C)` integer-only layout with all fields
    // initialized above or by `zeroed`.
    let stat_bytes =
        unsafe { slice::from_raw_parts((&stat as *const TmStat).cast::<u8>(), stat_len) };
    reply.data_mut()[..stat_len].copy_from_slice(stat_bytes);
    reply.count = stat_len as u64;
    reply_with_payload(message, &reply, stat_len);
}

fn reply_with_payload(message: ReceivedMessage, reply: &IoReply, payload_len: usize) {
    match reply.bytes_with_payload(payload_len) {
        Ok(bytes) => {
            let _ = message.reply_bytes(ReplyStatus::OK, bytes);
        }
        Err(_) => {
            let _ = message.reply_empty(ReplyStatus::from_errno(ENOSYS));
        }
    }
}

fn requested_read_len(req: &IoRequest) -> usize {
    let requested = if req.requested_count() == 0 {
        DEFAULT_READ_BYTES
    } else if req.requested_count() > TM_IO_MAX as u64 {
        TM_IO_MAX
    } else {
        req.requested_count() as usize
    };

    core::cmp::min(requested, TM_IO_MAX)
}

fn debug_write(bytes: &[u8]) {
    // SAFETY: `bytes` points to readable memory for this synchronous debug
    // write call; QSOE does not retain the pointer.
    unsafe { qsoe_ffi::dbg_write(bytes.as_ptr().cast::<c_char>(), bytes.len()) };
}
