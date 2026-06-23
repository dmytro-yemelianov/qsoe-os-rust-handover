#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

#[cfg(not(any(test, feature = "host-tests")))]
use core::panic::PanicInfo;

const PARSER_REUSE_CPIO: &[u8] = concat!(
    "070701",
    "00000001",
    "000081a4",
    "00000000",
    "00000000",
    "00000001",
    "00000000",
    "00000002",
    "00000000",
    "00000000",
    "00000000",
    "00000000",
    "00000006",
    "00000000",
    "hello\0",
    "ok",
    "\0\0",
    "070701",
    "00000000",
    "00000000",
    "00000000",
    "00000000",
    "00000001",
    "00000000",
    "00000000",
    "00000000",
    "00000000",
    "00000000",
    "00000000",
    "0000000b",
    "00000000",
    "TRAILER!!!\0",
    "\0\0\0",
)
.as_bytes();

#[cfg(not(any(test, feature = "host-tests")))]
#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    loop {
        core::hint::spin_loop();
    }
}

#[no_mangle]
pub extern "C" fn qsoe_minimal_rust_marker() -> u64 {
    qsoe_abi::QSOE_RUST_SPIKE_MARKER
}

#[no_mangle]
pub extern "C" fn qsoe_minimal_cpio_parser_smoke() -> u32 {
    let result = qsoe_cpio::Archive::parse(PARSER_REUSE_CPIO).and_then(|archive| {
        let info = archive.info()?;
        let entry = archive.file("hello")?;
        Ok((info.file_count == 1 && entry.is_some_and(|entry| entry.data == b"ok")) as u32)
    });

    result.unwrap_or(0)
}

#[cfg(not(test))]
#[no_mangle]
pub extern "C" fn main(_argc: isize, _argv: *const *const u8, _envp: *const *const u8) -> i32 {
    if qsoe_minimal_cpio_parser_smoke() == 1 {
        0
    } else {
        1
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn cpio_parser_reuse_smoke_runs_on_host() {
        assert_eq!(super::qsoe_minimal_cpio_parser_smoke(), 1);
    }
}
