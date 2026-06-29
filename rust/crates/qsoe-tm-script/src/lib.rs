#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

use core::ffi::{c_char, c_int, c_uint};

#[cfg(not(any(test, feature = "host-tests")))]
use core::panic::PanicInfo;

#[cfg(not(any(test, feature = "host-tests")))]
#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    loop {
        core::hint::spin_loop();
    }
}

unsafe fn write_nul(dst: *mut c_char, offset: usize) {
    *dst.add(offset) = 0;
}

unsafe fn write_byte(dst: *mut c_char, offset: usize, byte: u8) {
    *dst.add(offset) = byte as c_char;
}

fn is_blank(byte: u8) -> bool {
    byte == b' ' || byte == b'\t'
}

fn is_interp_end(byte: u8) -> bool {
    is_blank(byte) || byte == b'\n' || byte == b'\r'
}

/// Parse the POSIX shebang line at the beginning of `data`.
///
/// This intentionally mirrors `libtaskman/src/script.c`, including its
/// truncation behavior when `interp_cap` or `arg_cap` is smaller than the
/// source line.
///
/// # Safety
///
/// `data`, when `size >= 2`, must be readable for `size` bytes. `interp` and
/// `arg` must be writable for their corresponding capacities when those
/// capacities are non-zero.
#[no_mangle]
pub unsafe extern "C" fn tm_script_parse_shebang(
    data: *const u8,
    size: c_uint,
    interp: *mut c_char,
    interp_cap: c_uint,
    arg: *mut c_char,
    arg_cap: c_uint,
) -> c_int {
    if interp_cap == 0 || arg_cap == 0 || interp.is_null() || arg.is_null() {
        return -1;
    }

    write_nul(interp, 0);
    write_nul(arg, 0);

    let size = size as usize;
    if size < 2 || data.is_null() || *data.add(0) != b'#' || *data.add(1) != b'!' {
        return -1;
    }

    let mut i = 2usize;
    while i < size && is_blank(*data.add(i)) {
        i += 1;
    }

    let interp_cap = interp_cap as usize;
    let mut j = 0usize;
    while i < size && !is_interp_end(*data.add(i)) && j + 1 < interp_cap {
        write_byte(interp, j, *data.add(i));
        j += 1;
        i += 1;
    }
    write_nul(interp, j);
    if j == 0 {
        return -1;
    }

    while i < size && is_blank(*data.add(i)) {
        i += 1;
    }

    let arg_cap = arg_cap as usize;
    j = 0;
    while i < size && *data.add(i) != b'\n' && *data.add(i) != b'\r' && j + 1 < arg_cap {
        write_byte(arg, j, *data.add(i));
        j += 1;
        i += 1;
    }
    while j > 0 && is_blank(*arg.add(j - 1) as u8) {
        j -= 1;
    }
    write_nul(arg, j);
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::ffi::CStr;

    fn parse(input: &[u8], interp_cap: usize, arg_cap: usize) -> (c_int, String, String) {
        let mut interp = vec![0 as c_char; interp_cap];
        let mut arg = vec![0 as c_char; arg_cap];
        let rc = unsafe {
            tm_script_parse_shebang(
                input.as_ptr(),
                input.len() as c_uint,
                interp.as_mut_ptr(),
                interp.len() as c_uint,
                arg.as_mut_ptr(),
                arg.len() as c_uint,
            )
        };
        let interp = if interp_cap == 0 {
            String::new()
        } else {
            unsafe { CStr::from_ptr(interp.as_ptr()) }
                .to_str()
                .unwrap()
                .to_owned()
        };
        let arg = if arg_cap == 0 {
            String::new()
        } else {
            unsafe { CStr::from_ptr(arg.as_ptr()) }
                .to_str()
                .unwrap()
                .to_owned()
        };
        (rc, interp, arg)
    }

    #[test]
    fn parses_interpreter_and_single_argument() {
        let (rc, interp, arg) = parse(b"#!   /bin/qsh\t-x -y  \nbody", 32, 32);
        assert_eq!(rc, 0);
        assert_eq!(interp, "/bin/qsh");
        assert_eq!(arg, "-x -y");
    }

    #[test]
    fn handles_no_argument_and_cr_line_end() {
        let (rc, interp, arg) = parse(b"#!/sbin/init\rignored", 32, 32);
        assert_eq!(rc, 0);
        assert_eq!(interp, "/sbin/init");
        assert_eq!(arg, "");
    }

    #[test]
    fn rejects_non_shebang_or_empty_interpreter_after_clearing_outputs() {
        let (rc, interp, arg) = parse(b"plain text", 16, 16);
        assert_eq!(rc, -1);
        assert_eq!(interp, "");
        assert_eq!(arg, "");

        let (rc, interp, arg) = parse(b"#!   \n", 16, 16);
        assert_eq!(rc, -1);
        assert_eq!(interp, "");
        assert_eq!(arg, "");
    }

    #[test]
    fn preserves_c_truncation_behavior() {
        let (rc, interp, arg) = parse(b"#!/bin/qsh -x\n", 5, 16);
        assert_eq!(rc, 0);
        assert_eq!(interp, "/bin");
        assert_eq!(arg, "/qsh -x");

        let (rc, interp, arg) = parse(b"#!/bin/qsh abcdef\n", 32, 4);
        assert_eq!(rc, 0);
        assert_eq!(interp, "/bin/qsh");
        assert_eq!(arg, "abc");
    }

    #[test]
    fn zero_output_capacity_fails_without_accessing_buffers() {
        let mut byte = 0 as c_char;
        assert_eq!(
            unsafe {
                tm_script_parse_shebang(
                    b"#!/bin/qsh\n".as_ptr(),
                    11,
                    core::ptr::null_mut(),
                    0,
                    &mut byte,
                    1,
                )
            },
            -1
        );
        assert_eq!(
            unsafe {
                tm_script_parse_shebang(
                    b"#!/bin/qsh\n".as_ptr(),
                    11,
                    &mut byte,
                    1,
                    core::ptr::null_mut(),
                    0,
                )
            },
            -1
        );
    }
}
