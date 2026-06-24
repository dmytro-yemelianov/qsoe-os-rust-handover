#![no_std]

use core::cell::UnsafeCell;
use core::ffi::{c_char, c_void, CStr};
use core::mem::size_of;
use core::panic::PanicInfo;
use core::ptr;

use qsoe_pipe::{PipeManager, PipeReplies, PipeReply};
use qsoe_ressrv::{
    DirectRequestHandler, DirectServer, IoReply, IoRequest, ENOSYS, IO_CONNECT, IO_DUP,
    TM_REQ_CLOSE, TM_REQ_IO_READ, TM_REQ_IO_WRITE,
};

const PIPE_PATH: &[u8] = b"/dev/pipe\0";

struct ManagerCell(UnsafeCell<PipeManager>);

// SAFETY: `pipe-rs` runs one direct resource-server receive loop. The loop owns
// the only mutable borrow of this process-global pipe manager.
unsafe impl Sync for ManagerCell {}

impl ManagerCell {
    const fn new() -> Self {
        Self(UnsafeCell::new(PipeManager::new()))
    }

    fn get(&self) -> *mut PipeManager {
        self.0.get()
    }
}

static MANAGER: ManagerCell = ManagerCell::new();

struct PipeService {
    manager: &'static mut PipeManager,
}

impl DirectRequestHandler for PipeService {
    fn handle_message(&mut self, message: qsoe_ressrv::ReceivedMessage, req: &IoRequest) {
        handle_message(message, req, self.manager);
    }
}

#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    debug_write(b"[pipe-rs] panic\n");
    loop {
        core::hint::spin_loop();
    }
}

#[no_mangle]
pub extern "C" fn qsoe_pipe_rust_marker() -> u64 {
    0x5153_4f45_5049_5045
}

#[no_mangle]
pub extern "C" fn main(_argc: isize, _argv: *const *const u8, _envp: *const *const u8) -> i32 {
    debug_write(b"[pipe-rs] alive\n");

    // SAFETY: see `ManagerCell`'s `Sync` safety note. This function never
    // returns, so no second mutable borrow is created.
    let manager = unsafe { &mut *MANAGER.get() };
    let mut server = match DirectServer::register(pipe_path(), PipeService { manager }) {
        Ok(server) => server,
        Err(_) => {
            debug_write(b"[pipe-rs] register failed\n");
            return 1;
        }
    };

    debug_write(b"[pipe-rs] /dev/pipe registered\n");

    if server.detach_ready(0).is_err() {
        debug_write(b"[pipe-rs] procmgr_detach failed\n");
    }

    debug_write(b"[pipe-rs] entering MsgReceive loop\n");
    server.run()
}

fn pipe_path() -> &'static CStr {
    // SAFETY: `PIPE_PATH` is a static byte string with exactly one trailing NUL
    // and no interior NUL bytes.
    unsafe { CStr::from_bytes_with_nul_unchecked(PIPE_PATH) }
}

fn handle_message(
    message: qsoe_ressrv::ReceivedMessage,
    req: &IoRequest,
    manager: &mut PipeManager,
) {
    let rcvid = message.rcvid();
    let badge = message.info().scoid as u64;
    let replies = match req.opcode() {
        TM_REQ_IO_READ => manager.handle_read(badge, req.requested_count() as usize, rcvid),
        TM_REQ_IO_WRITE => manager.handle_write(badge, req.payload_prefix(), rcvid),
        TM_REQ_CLOSE => manager.handle_close(badge, rcvid),
        IO_CONNECT | IO_DUP => PipeReplies::single(PipeReply::Empty {
            rcvid,
            status: qsoe_pipe::PipeStatus::Ok,
        }),
        _ => PipeReplies::single(PipeReply::Empty {
            rcvid,
            status: qsoe_pipe::PipeStatus::Unsupported,
        }),
    };
    reply_all(manager, replies);
}

fn reply_all(manager: &PipeManager, replies: PipeReplies) {
    for entry in replies.entries().iter().flatten().copied() {
        match entry {
            PipeReply::Empty { rcvid, status } => {
                raw_reply(rcvid, status.errno(), ptr::null(), 0);
            }
            PipeReply::Word {
                rcvid,
                status,
                value,
            } => {
                raw_reply(
                    rcvid,
                    status.errno(),
                    (&value as *const u64).cast::<c_void>(),
                    size_of::<u64>(),
                );
            }
            PipeReply::ReadPayload { rcvid, status, len } => {
                let payload = manager.reply_payload(len);
                let mut reply = IoReply::zeroed();
                reply.count = payload.len() as u64;
                reply.data_mut()[..payload.len()].copy_from_slice(payload);
                match reply.bytes_with_payload(payload.len()) {
                    Ok(bytes) => raw_reply(
                        rcvid,
                        status.errno(),
                        bytes.as_ptr().cast::<c_void>(),
                        bytes.len(),
                    ),
                    Err(_) => raw_reply(rcvid, ENOSYS, ptr::null(), 0),
                }
            }
        }
    }
}

fn raw_reply(rcvid: i32, status: i32, msg: *const c_void, bytes: usize) {
    // SAFETY: every `rcvid` comes from a successful `MsgReceive` call and
    // `msg` either is null for an empty reply or points at synchronous reply
    // storage valid for `bytes` bytes.
    let _ = unsafe { qsoe_ffi::msg_reply(rcvid, status, msg, bytes as i32) };
}

fn debug_write(bytes: &[u8]) {
    // SAFETY: `bytes` points to readable memory for this synchronous debug
    // write call; QSOE does not retain the pointer.
    unsafe { qsoe_ffi::dbg_write(bytes.as_ptr().cast::<c_char>(), bytes.len()) };
}
