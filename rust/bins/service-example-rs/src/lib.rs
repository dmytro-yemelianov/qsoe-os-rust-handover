#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]
#![cfg_attr(all(feature = "host-tests", not(test)), allow(dead_code))]

#[cfg(not(any(test, feature = "host-tests")))]
use core::ffi::c_char;
#[cfg(not(any(test, feature = "host-tests")))]
use core::ffi::CStr;
#[cfg(not(any(test, feature = "host-tests")))]
use core::panic::PanicInfo;

#[cfg(not(any(test, feature = "host-tests")))]
use qsoe_ressrv::{
    DirectRequestHandler, DirectServer, IoReply, ReceivedMessage, ReplyStatus, ENOSYS,
};
use qsoe_ressrv::{
    IoRequest, IO_CONNECT, IO_DUP, TM_IO_MAX, TM_REQ_CLOSE, TM_REQ_IO_READ, TM_REQ_IO_WRITE,
};

#[cfg(not(any(test, feature = "host-tests")))]
const EXAMPLE_PATH: &[u8] = b"/dev/rust-example\0";
const EXAMPLE_REPLY: &[u8] = b"qsoe-rs\n";

#[cfg(not(any(test, feature = "host-tests")))]
struct ExampleService {
    writes: u64,
}

#[cfg(not(any(test, feature = "host-tests")))]
impl DirectRequestHandler for ExampleService {
    fn handle_message(&mut self, message: ReceivedMessage, req: &IoRequest) {
        match classify_request(req) {
            ExampleRequest::Ack => {
                let _ = message.reply_empty(ReplyStatus::OK);
            }
            ExampleRequest::Write { bytes } => {
                let written = bytes as u64;
                self.writes = self.writes.wrapping_add(written);
                let _ = message.reply_word(ReplyStatus::OK, written);
            }
            ExampleRequest::Read { bytes } => reply_to_read(message, bytes),
            ExampleRequest::Unsupported => {
                let _ = message.reply_empty(ReplyStatus::from_errno(ENOSYS));
            }
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ExampleRequest {
    Ack,
    Write { bytes: usize },
    Read { bytes: usize },
    Unsupported,
}

fn classify_request(req: &IoRequest) -> ExampleRequest {
    match req.opcode() {
        IO_CONNECT | IO_DUP | TM_REQ_CLOSE => ExampleRequest::Ack,
        TM_REQ_IO_WRITE => ExampleRequest::Write {
            bytes: req.payload_prefix().len(),
        },
        TM_REQ_IO_READ => ExampleRequest::Read {
            bytes: read_reply_len(req),
        },
        _ => ExampleRequest::Unsupported,
    }
}

fn read_reply_len(req: &IoRequest) -> usize {
    let want = if req.requested_count() == 0 || req.requested_count() > TM_IO_MAX as u64 {
        TM_IO_MAX
    } else {
        req.requested_count() as usize
    };

    core::cmp::min(want, EXAMPLE_REPLY.len())
}

#[cfg(not(any(test, feature = "host-tests")))]
#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    debug_write(b"[service-example-rs] panic\n");
    loop {
        core::hint::spin_loop();
    }
}

#[no_mangle]
pub extern "C" fn qsoe_service_example_rust_marker() -> u64 {
    0x5153_4f45_4558_414d
}

#[cfg(not(any(test, feature = "host-tests")))]
#[no_mangle]
pub extern "C" fn main(_argc: isize, _argv: *const *const u8, _envp: *const *const u8) -> i32 {
    debug_write(b"[service-example-rs] alive\n");

    let mut server = match DirectServer::register(example_path(), ExampleService { writes: 0 }) {
        Ok(server) => server,
        Err(_) => {
            debug_write(b"[service-example-rs] register failed\n");
            return 1;
        }
    };

    debug_write(b"[service-example-rs] /dev/rust-example registered\n");
    if server.detach_ready(0).is_err() {
        debug_write(b"[service-example-rs] procmgr_detach failed\n");
    }

    debug_write(b"[service-example-rs] entering MsgReceive loop\n");
    server.run()
}

#[cfg(not(any(test, feature = "host-tests")))]
fn example_path() -> &'static CStr {
    // SAFETY: `EXAMPLE_PATH` is a static byte string with exactly one trailing
    // NUL and no interior NUL bytes.
    unsafe { CStr::from_bytes_with_nul_unchecked(EXAMPLE_PATH) }
}

#[cfg(not(any(test, feature = "host-tests")))]
fn reply_to_read(message: ReceivedMessage, n: usize) {
    let mut reply = IoReply::zeroed();
    reply.data_mut()[..n].copy_from_slice(&EXAMPLE_REPLY[..n]);
    reply.count = n as u64;

    match reply.bytes_with_payload(n) {
        Ok(bytes) => {
            let _ = message.reply_bytes(ReplyStatus::OK, bytes);
        }
        Err(_) => {
            let _ = message.reply_empty(ReplyStatus::from_errno(ENOSYS));
        }
    }
}

#[cfg(not(any(test, feature = "host-tests")))]
fn debug_write(bytes: &[u8]) {
    // SAFETY: `bytes` points to readable memory for this synchronous debug
    // write call; QSOE does not retain the pointer.
    unsafe { qsoe_ffi::dbg_write(bytes.as_ptr().cast::<c_char>(), bytes.len()) };
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(opcode: u64, count: u64) -> IoRequest {
        let mut req = IoRequest::zeroed();
        req.type_ = opcode;
        req.count = count;
        req
    }

    #[test]
    fn acknowledges_lifecycle_requests() {
        assert_eq!(
            classify_request(&request(IO_CONNECT, 0)),
            ExampleRequest::Ack
        );
        assert_eq!(classify_request(&request(IO_DUP, 0)), ExampleRequest::Ack);
        assert_eq!(
            classify_request(&request(TM_REQ_CLOSE, 0)),
            ExampleRequest::Ack
        );
    }

    #[test]
    fn reports_write_payload_prefix_len() {
        assert_eq!(
            classify_request(&request(TM_REQ_IO_WRITE, 7)),
            ExampleRequest::Write { bytes: 7 }
        );
        assert_eq!(
            classify_request(&request(TM_REQ_IO_WRITE, (TM_IO_MAX as u64) + 1)),
            ExampleRequest::Write { bytes: TM_IO_MAX }
        );
    }

    #[test]
    fn caps_read_reply_to_sample_payload() {
        assert_eq!(
            classify_request(&request(TM_REQ_IO_READ, 4)),
            ExampleRequest::Read { bytes: 4 }
        );
        assert_eq!(
            classify_request(&request(TM_REQ_IO_READ, 0)),
            ExampleRequest::Read {
                bytes: EXAMPLE_REPLY.len()
            }
        );
        assert_eq!(
            classify_request(&request(TM_REQ_IO_READ, TM_IO_MAX as u64)),
            ExampleRequest::Read {
                bytes: EXAMPLE_REPLY.len()
            }
        );
    }

    #[test]
    fn rejects_unknown_requests() {
        assert_eq!(
            classify_request(&request(0xfeed_beef, 0)),
            ExampleRequest::Unsupported
        );
    }
}
