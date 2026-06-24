#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

#[cfg(not(any(test, feature = "host-tests")))]
use core::ffi::{c_char, c_void, CStr};
#[cfg(not(any(test, feature = "host-tests")))]
use core::mem;
#[cfg(not(any(test, feature = "host-tests")))]
use core::panic::PanicInfo;
#[cfg(not(any(test, feature = "host-tests")))]
use core::ptr::NonNull;
#[cfg(not(any(test, feature = "host-tests")))]
use core::slice;

#[cfg(not(any(test, feature = "host-tests")))]
use qsoe_ressrv::{Channel, DirectService, Receive, ReplyStatus};

#[cfg(not(any(test, feature = "host-tests")))]
const MSGPASS_PATH: &[u8] = b"/dev/msgpass\0";
#[cfg(not(any(test, feature = "host-tests")))]
const MSGPASS_MAX_BYTES: usize = 4 * 1024 * 1024;
#[cfg(not(any(test, feature = "host-tests")))]
const MSGPASS_REGISTER_RETRIES: usize = 100_000;

pub fn swap_halfwords_in_place(bytes: &mut [u8]) {
    for pair in bytes.chunks_exact_mut(2) {
        pair.swap(0, 1);
    }
}

#[cfg(not(any(test, feature = "host-tests")))]
struct MessageBuffer {
    ptr: NonNull<u8>,
    len: usize,
}

#[cfg(not(any(test, feature = "host-tests")))]
impl MessageBuffer {
    fn new(len: usize) -> Option<Self> {
        // SAFETY: libc returns either a null pointer or a live allocation of at
        // least `len` bytes. Ownership is stored in `MessageBuffer` and released
        // in `Drop`.
        let ptr = unsafe { malloc(len) }.cast::<u8>();
        NonNull::new(ptr).map(|ptr| Self { ptr, len })
    }

    fn as_mut_slice(&mut self) -> &mut [u8] {
        // SAFETY: `ptr` is live for `len` bytes and this method requires
        // `&mut self`, so no aliasing mutable slice can exist.
        unsafe { slice::from_raw_parts_mut(self.ptr.as_ptr(), self.len) }
    }
}

#[cfg(not(any(test, feature = "host-tests")))]
impl Drop for MessageBuffer {
    fn drop(&mut self) {
        // SAFETY: `ptr` came from `malloc` and has not been freed yet.
        unsafe { free(self.ptr.as_ptr().cast::<c_void>()) };
    }
}

#[cfg(not(any(test, feature = "host-tests")))]
unsafe extern "C" {
    fn malloc(size: usize) -> *mut c_void;
    fn free(ptr: *mut c_void);
}

#[cfg(not(any(test, feature = "host-tests")))]
#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    debug_write(b"[test_msgpass-rs] panic\n");
    loop {
        core::hint::spin_loop();
    }
}

#[no_mangle]
pub extern "C" fn qsoe_test_msgpass_rust_marker() -> u64 {
    0x5153_4f45_4d53_4750
}

#[cfg(not(any(test, feature = "host-tests")))]
#[no_mangle]
pub extern "C" fn main(argc: isize, argv: *const *const u8, _envp: *const *const u8) -> i32 {
    debug_write(b"[test_msgpass-rs] alive\n");

    let mut buffer = match MessageBuffer::new(MSGPASS_MAX_BYTES) {
        Some(buffer) => buffer,
        None => {
            debug_write(b"[test_msgpass-rs] malloc failed\n");
            return 1;
        }
    };

    let service = match register_msgpass_service() {
        Ok(service) => service,
        Err(()) => return 1,
    };
    debug_write(b"[test_msgpass-rs] /dev/msgpass registered\n");

    let buf = buffer.as_mut_slice();
    let message = match service.receive_bytes(buf) {
        Ok(Receive::Message(message)) => message,
        Ok(Receive::Pulse(_)) => {
            debug_write(b"[test_msgpass-rs] unexpected pulse\n");
            return 1;
        }
        Err(_) => {
            debug_write(b"[test_msgpass-rs] receive failed\n");
            return 1;
        }
    };

    if has_no_reply_arg(argc, argv) {
        mem::forget(service);
        return 0;
    }

    let n = match received_len(message.info().msglen, buf.len()) {
        Some(n) => n,
        None => {
            debug_write(b"[test_msgpass-rs] invalid message length\n");
            return 1;
        }
    };
    swap_halfwords_in_place(&mut buf[..n]);

    if message.reply_bytes(ReplyStatus::OK, &buf[..n]).is_err() {
        debug_write(b"[test_msgpass-rs] reply failed\n");
        return 1;
    }

    mem::forget(service);
    0
}

#[cfg(not(any(test, feature = "host-tests")))]
fn register_msgpass_service() -> Result<DirectService, ()> {
    let channel = match Channel::create(0) {
        Ok(channel) => channel,
        Err(_) => {
            debug_write(b"[test_msgpass-rs] ChannelCreate failed\n");
            return Err(());
        }
    };

    for _ in 0..MSGPASS_REGISTER_RETRIES {
        if channel.register_path(msgpass_path()).is_ok() {
            return Ok(DirectService::from_channel(channel));
        }
        // SAFETY: `sched_yield` takes no borrowed process state and simply
        // gives taskman time to scrub a stale `/dev/msgpass` owner.
        unsafe {
            qsoe_ffi::sched_yield();
        }
    }

    debug_write(b"[test_msgpass-rs] register failed\n");
    Err(())
}

#[cfg(not(any(test, feature = "host-tests")))]
fn msgpass_path() -> &'static CStr {
    // SAFETY: `MSGPASS_PATH` is a static byte string with exactly one trailing
    // NUL and no interior NUL bytes.
    unsafe { CStr::from_bytes_with_nul_unchecked(MSGPASS_PATH) }
}

#[cfg(not(any(test, feature = "host-tests")))]
fn received_len(msglen: i32, cap: usize) -> Option<usize> {
    if msglen < 0 {
        return None;
    }
    let n = msglen as usize;
    if n <= cap {
        Some(n)
    } else {
        None
    }
}

#[cfg(not(any(test, feature = "host-tests")))]
fn has_no_reply_arg(argc: isize, argv: *const *const u8) -> bool {
    if argc <= 1 || argv.is_null() {
        return false;
    }

    // SAFETY: QSOE crt0 passes a C argv vector with at least `argc` entries.
    let arg = unsafe { *argv.add(1) };
    if arg.is_null() {
        return false;
    }

    // SAFETY: argv entries are conventional NUL-terminated C strings.
    let cstr = unsafe { CStr::from_ptr(arg.cast::<c_char>()) };
    cstr.to_bytes() == b"--no-reply"
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

    #[test]
    fn swaps_even_halfwords() {
        let mut bytes = [0x12, 0x34, 0xab, 0xcd];
        swap_halfwords_in_place(&mut bytes);
        assert_eq!(bytes, [0x34, 0x12, 0xcd, 0xab]);
    }

    #[test]
    fn leaves_trailing_odd_byte_unchanged() {
        let mut bytes = [0x12, 0x34, 0xff];
        swap_halfwords_in_place(&mut bytes);
        assert_eq!(bytes, [0x34, 0x12, 0xff]);
    }

    #[test]
    fn handles_empty_and_single_byte_buffers() {
        let mut empty = [];
        swap_halfwords_in_place(&mut empty);
        assert_eq!(empty, []);

        let mut single = [0x7a];
        swap_halfwords_in_place(&mut single);
        assert_eq!(single, [0x7a]);
    }
}
