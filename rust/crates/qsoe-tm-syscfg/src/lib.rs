#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

use core::ffi::{c_char, c_int, c_uint, c_void};

const TM_SYSCFG_TAG_END: u16 = 0;
const TAG_HEADER_LEN: usize = 4;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TmSyscfgState {
    pub buf: *mut u8,
    pub cap: c_uint,
    pub len: c_uint,
    pub ready: c_int,
}

fn checked_record_end(offset: usize, payload_len: usize) -> Option<usize> {
    offset
        .checked_add(TAG_HEADER_LEN)
        .and_then(|start| start.checked_add(payload_len))
}

unsafe fn write_le16(dst: *mut u8, offset: usize, value: u16) {
    *dst.add(offset) = (value & 0xff) as u8;
    *dst.add(offset + 1) = ((value >> 8) & 0xff) as u8;
}

unsafe fn read_le16(src: *const u8, offset: usize) -> u16 {
    u16::from(*src.add(offset)) | (u16::from(*src.add(offset + 1)) << 8)
}

unsafe fn c_strlen(mut s: *const c_char) -> usize {
    if s.is_null() {
        return 0;
    }
    let mut n = 0usize;
    while *s != 0 {
        n += 1;
        s = s.add(1);
    }
    n
}

/// Initialize caller-owned syscfg builder state.
///
/// # Safety
///
/// `state` may be null. If non-null, it must point to writable storage whose
/// layout matches `tm_syscfg_state_t`.
#[no_mangle]
pub unsafe extern "C" fn tm_syscfg_init(state: *mut TmSyscfgState, buf: *mut c_void, cap: c_uint) {
    if state.is_null() {
        return;
    }
    (*state).buf = buf.cast::<u8>();
    (*state).cap = cap;
    (*state).len = 0;
    (*state).ready = 0;
}

/// Emit one raw TLV record.
///
/// # Safety
///
/// `state` may be null. If non-null, `state.buf` must be writable for
/// `state.cap` bytes. When `payload` is non-null, it must be readable for
/// `len` bytes.
#[no_mangle]
pub unsafe extern "C" fn tm_syscfg_emit(
    state: *mut TmSyscfgState,
    id: u16,
    payload: *const c_void,
    len: c_uint,
) -> c_int {
    if state.is_null() || (*state).buf.is_null() {
        return -1;
    }
    if (*state).ready != 0 {
        return -1;
    }

    let used = (*state).len as usize;
    let payload_len = len as usize;
    let Some(end) = checked_record_end(used, payload_len) else {
        return -1;
    };
    if end > (*state).cap as usize {
        return -1;
    }

    let buf = (*state).buf;
    write_le16(buf, used, id);
    write_le16(buf, used + 2, len as u16);

    if len != 0 && !payload.is_null() {
        let src = payload.cast::<u8>();
        let mut i = 0usize;
        while i < payload_len {
            *buf.add(used + TAG_HEADER_LEN + i) = *src.add(i);
            i += 1;
        }
    }

    (*state).len = end as c_uint;
    0
}

/// Emit a little-endian u32 payload.
///
/// # Safety
///
/// See `tm_syscfg_emit`.
#[no_mangle]
pub unsafe extern "C" fn tm_syscfg_emit_u32(
    state: *mut TmSyscfgState,
    id: u16,
    value: u32,
) -> c_int {
    let le = value.to_le_bytes();
    tm_syscfg_emit(state, id, le.as_ptr().cast::<c_void>(), le.len() as c_uint)
}

/// Emit a little-endian u64 payload.
///
/// # Safety
///
/// See `tm_syscfg_emit`.
#[no_mangle]
pub unsafe extern "C" fn tm_syscfg_emit_u64(
    state: *mut TmSyscfgState,
    id: u16,
    value: u64,
) -> c_int {
    let le = value.to_le_bytes();
    tm_syscfg_emit(state, id, le.as_ptr().cast::<c_void>(), le.len() as c_uint)
}

/// Emit a NUL-terminated string payload, including the trailing NUL.
///
/// # Safety
///
/// `str_` may be null. If non-null, it must point to a readable C string.
#[no_mangle]
pub unsafe extern "C" fn tm_syscfg_emit_asciz(
    state: *mut TmSyscfgState,
    id: u16,
    str_: *const c_char,
) -> c_int {
    let len = c_strlen(str_);
    if len == 0 {
        return 0;
    }
    tm_syscfg_emit(state, id, str_.cast::<c_void>(), (len + 1) as c_uint)
}

/// Append the END sentinel and lock the blob.
///
/// # Safety
///
/// `state` may be null. If non-null, it must point to writable syscfg state.
#[no_mangle]
pub unsafe extern "C" fn tm_syscfg_finalize(state: *mut TmSyscfgState) -> c_int {
    if state.is_null() {
        return -1;
    }
    if (*state).ready != 0 {
        return 0;
    }
    if tm_syscfg_emit(state, TM_SYSCFG_TAG_END, core::ptr::null(), 0) != 0 {
        return -1;
    }
    (*state).ready = 1;
    0
}

/// Return the finalized blob pointer and byte length.
///
/// # Safety
///
/// Pointers may be null. Non-null output pointers must be writable.
#[no_mangle]
pub unsafe extern "C" fn tm_syscfg_get(
    state: *const TmSyscfgState,
    out_blob: *mut *const c_void,
    out_len: *mut c_uint,
) -> c_int {
    if state.is_null() || (*state).ready == 0 {
        return -1;
    }
    if !out_blob.is_null() {
        *out_blob = (*state).buf.cast::<c_void>();
    }
    if !out_len.is_null() {
        *out_len = (*state).len;
    }
    0
}

/// Find the first payload for `tag_id`.
///
/// # Safety
///
/// `state` may be null. If non-null and finalized, `state.buf` must be
/// readable for `state.len` bytes. Non-null output pointers must be writable.
#[no_mangle]
pub unsafe extern "C" fn tm_syscfg_find(
    state: *const TmSyscfgState,
    tag_id: c_uint,
    out_ptr: *mut *const c_void,
    out_len: *mut c_uint,
) -> c_int {
    if state.is_null() || (*state).ready == 0 || (*state).buf.is_null() {
        return -1;
    }

    let buf = (*state).buf.cast::<u8>();
    let blob_len = (*state).len as usize;
    let mut off = 0usize;
    while off
        .checked_add(TAG_HEADER_LEN)
        .is_some_and(|header_end| header_end <= blob_len)
    {
        let id = read_le16(buf, off);
        let len = read_le16(buf, off + 2);
        if id == TM_SYSCFG_TAG_END {
            return -1;
        }
        if u32::from(id) == tag_id {
            if !out_ptr.is_null() {
                *out_ptr = buf.add(off + TAG_HEADER_LEN).cast::<c_void>();
            }
            if !out_len.is_null() {
                *out_len = c_uint::from(len);
            }
            return 0;
        }
        let Some(next) = checked_record_end(off, usize::from(len)) else {
            return -1;
        };
        off = next;
    }
    -1
}

/// Find and decode a little-endian u32 payload.
///
/// # Safety
///
/// `out` must be writable when non-null. Other pointer rules match
/// `tm_syscfg_find`.
#[no_mangle]
pub unsafe extern "C" fn tm_syscfg_find_u32(
    state: *const TmSyscfgState,
    tag_id: c_uint,
    out: *mut u32,
) -> c_int {
    if out.is_null() {
        return -1;
    }
    let mut p: *const c_void = core::ptr::null();
    let mut len: c_uint = 0;
    if tm_syscfg_find(state, tag_id, &mut p, &mut len) != 0 {
        return -1;
    }
    if len != 4 {
        return -1;
    }
    let bp = p.cast::<u8>();
    *out = u32::from(*bp)
        | (u32::from(*bp.add(1)) << 8)
        | (u32::from(*bp.add(2)) << 16)
        | (u32::from(*bp.add(3)) << 24);
    0
}

/// Find and decode a little-endian u64 payload.
///
/// # Safety
///
/// `out` must be writable when non-null. Other pointer rules match
/// `tm_syscfg_find`.
#[no_mangle]
pub unsafe extern "C" fn tm_syscfg_find_u64(
    state: *const TmSyscfgState,
    tag_id: c_uint,
    out: *mut u64,
) -> c_int {
    if out.is_null() {
        return -1;
    }
    let mut p: *const c_void = core::ptr::null();
    let mut len: c_uint = 0;
    if tm_syscfg_find(state, tag_id, &mut p, &mut len) != 0 {
        return -1;
    }
    if len != 8 {
        return -1;
    }
    let bp = p.cast::<u8>();
    let mut value = 0u64;
    let mut i = 8usize;
    while i > 0 {
        i -= 1;
        value = (value << 8) | u64::from(*bp.add(i));
    }
    *out = value;
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    const TAG_VERSION: u16 = 1;
    const TAG_MODEL: u16 = 2;
    const TAG_TIMEBASE: u16 = 4;

    unsafe fn new_state(buf: &mut [u8]) -> TmSyscfgState {
        let mut state = TmSyscfgState {
            buf: core::ptr::null_mut(),
            cap: 0,
            len: 99,
            ready: 1,
        };
        tm_syscfg_init(
            &mut state,
            buf.as_mut_ptr().cast::<c_void>(),
            buf.len() as c_uint,
        );
        state
    }

    #[test]
    fn emits_finds_and_gets_finalized_blob() {
        unsafe {
            let mut buf = [0u8; 64];
            let mut state = new_state(&mut buf);

            assert_eq!(tm_syscfg_emit_u32(&mut state, TAG_VERSION, 1), 0);
            assert_eq!(
                tm_syscfg_emit_asciz(
                    &mut state,
                    TAG_MODEL,
                    c"qemu-virt".as_ptr().cast::<c_char>()
                ),
                0
            );
            assert_eq!(tm_syscfg_emit_u64(&mut state, TAG_TIMEBASE, 10_000_000), 0);
            assert_eq!(tm_syscfg_finalize(&mut state), 0);
            assert_eq!(state.ready, 1);

            let mut blob: *const c_void = core::ptr::null();
            let mut blob_len = 0;
            assert_eq!(tm_syscfg_get(&state, &mut blob, &mut blob_len), 0);
            assert_eq!(blob, buf.as_ptr().cast::<c_void>());
            assert_eq!(blob_len, state.len);

            let mut version = 0u32;
            let mut timebase = 0u64;
            assert_eq!(
                tm_syscfg_find_u32(&state, TAG_VERSION.into(), &mut version),
                0
            );
            assert_eq!(
                tm_syscfg_find_u64(&state, TAG_TIMEBASE.into(), &mut timebase),
                0
            );
            assert_eq!(version, 1);
            assert_eq!(timebase, 10_000_000);

            let mut model_ptr: *const c_void = core::ptr::null();
            let mut model_len = 0;
            assert_eq!(
                tm_syscfg_find(&state, TAG_MODEL.into(), &mut model_ptr, &mut model_len),
                0
            );
            assert_eq!(model_len, 10);
            assert_eq!(
                core::slice::from_raw_parts(model_ptr.cast::<u8>(), model_len as usize),
                b"qemu-virt\0"
            );
        }
    }

    #[test]
    fn empty_asciz_is_skipped() {
        unsafe {
            let mut buf = [0u8; 16];
            let mut state = new_state(&mut buf);

            assert_eq!(
                tm_syscfg_emit_asciz(&mut state, TAG_MODEL, core::ptr::null()),
                0
            );
            assert_eq!(
                tm_syscfg_emit_asciz(&mut state, TAG_MODEL, c"".as_ptr().cast::<c_char>()),
                0
            );
            assert_eq!(state.len, 0);
        }
    }

    #[test]
    fn bounds_ready_and_finalize_match_c() {
        unsafe {
            let mut small = [0u8; 7];
            let mut state = new_state(&mut small);
            assert_eq!(tm_syscfg_emit_u32(&mut state, TAG_VERSION, 1), -1);
            assert_eq!(state.len, 0);

            let mut exact = [0u8; 8];
            let mut state = new_state(&mut exact);
            assert_eq!(tm_syscfg_emit_u32(&mut state, TAG_VERSION, 1), 0);
            assert_eq!(tm_syscfg_finalize(&mut state), -1);
            assert_eq!(state.ready, 0);

            let mut enough = [0u8; 12];
            let mut state = new_state(&mut enough);
            assert_eq!(tm_syscfg_emit_u32(&mut state, TAG_VERSION, 1), 0);
            assert_eq!(tm_syscfg_finalize(&mut state), 0);
            assert_eq!(tm_syscfg_emit_u32(&mut state, TAG_VERSION, 2), -1);
            assert_eq!(tm_syscfg_finalize(&mut state), 0);
        }
    }

    #[test]
    fn raw_null_payload_keeps_existing_payload_bytes() {
        unsafe {
            let mut buf = [0x5au8; 16];
            let mut state = new_state(&mut buf);

            assert_eq!(tm_syscfg_emit(&mut state, 9, core::ptr::null(), 3), 0);
            assert_eq!(&buf[0..4], &[9, 0, 3, 0]);
            assert_eq!(&buf[4..7], &[0x5a, 0x5a, 0x5a]);
            assert_eq!(state.len, 7);
        }
    }

    #[test]
    fn find_returns_matching_malformed_payload_len() {
        unsafe {
            let mut buf = [10u8, 0, 20, 0];
            let state = TmSyscfgState {
                buf: buf.as_mut_ptr(),
                cap: buf.len() as c_uint,
                len: 4,
                ready: 1,
            };
            let mut ptr: *const c_void = core::ptr::null();
            let mut len = 0;
            assert_eq!(tm_syscfg_find(&state, 10, &mut ptr, &mut len), 0);
            assert_eq!(ptr, buf.as_ptr().wrapping_add(4).cast::<c_void>());
            assert_eq!(len, 20);
        }
    }

    #[test]
    fn typed_find_rejects_wrong_lengths_and_missing_tags() {
        unsafe {
            let mut buf = [0u8; 32];
            let mut state = new_state(&mut buf);
            let raw = [1u8, 2, 3];
            assert_eq!(
                tm_syscfg_emit(&mut state, TAG_VERSION, raw.as_ptr().cast::<c_void>(), 3),
                0
            );
            assert_eq!(tm_syscfg_finalize(&mut state), 0);

            let mut out32 = 0xfeed_beefu32;
            let mut out64 = 0xfeed_beef_dead_beefu64;
            assert_eq!(
                tm_syscfg_find_u32(&state, TAG_VERSION.into(), &mut out32),
                -1
            );
            assert_eq!(
                tm_syscfg_find_u64(&state, TAG_TIMEBASE.into(), &mut out64),
                -1
            );
            assert_eq!(out32, 0xfeed_beef);
            assert_eq!(out64, 0xfeed_beef_dead_beef);
        }
    }
}
