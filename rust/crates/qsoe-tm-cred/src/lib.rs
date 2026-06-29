#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

use core::ffi::{c_char, c_int, c_uint};

#[cfg(not(any(test, feature = "host-tests")))]
use core::panic::PanicInfo;

pub const TM_CWD_MAX: usize = 256;
pub const TM_CRED_KEEP: c_uint = 0xffff_ffff;

const EINVAL: c_int = 21;
const ERANGE: c_int = 32;
const ENAMETOOLONG: c_int = 35;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TmCredInfo {
    pub ruid: c_uint,
    pub euid: c_uint,
    pub suid: c_uint,
    pub rgid: c_uint,
    pub egid: c_uint,
    pub sgid: c_uint,
    pub ngroups: u32,
}

impl TmCredInfo {
    const fn root() -> Self {
        Self {
            ruid: 0,
            euid: 0,
            suid: 0,
            rgid: 0,
            egid: 0,
            sgid: 0,
            ngroups: 0,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TmCredState {
    pub cwd: [c_char; TM_CWD_MAX],
    pub umask: c_uint,
    pub cred: TmCredInfo,
}

#[cfg(not(any(test, feature = "host-tests")))]
#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    loop {
        core::hint::spin_loop();
    }
}

/// Initialise a `tm_cred_state_t` record.
///
/// # Safety
///
/// `state` may be null. If non-null, it must point to a writable
/// `tm_cred_state_t`-compatible record.
#[no_mangle]
pub unsafe extern "C" fn tm_cred_init(state: *mut TmCredState) {
    if state.is_null() {
        return;
    }
    (*state).cwd[0] = b'/' as c_char;
    (*state).cwd[1] = 0;
    (*state).umask = 0o022;
    (*state).cred = TmCredInfo::root();
}

/// Set cwd to an absolute path with a caller-provided byte length.
///
/// # Safety
///
/// `state` and `path` may be null. If non-null, `path` must be readable for
/// `path_len` bytes and `state` must be writable.
#[no_mangle]
pub unsafe extern "C" fn tm_cred_chdir(
    state: *mut TmCredState,
    path: *const c_char,
    path_len: c_uint,
) -> c_int {
    if state.is_null() || path.is_null() {
        return -EINVAL;
    }
    let len = path_len as usize;
    if len == 0 || len >= TM_CWD_MAX {
        return -ENAMETOOLONG;
    }
    if *path != b'/' as c_char {
        return -EINVAL;
    }

    let mut i = 0usize;
    while i < len {
        (*state).cwd[i] = *path.add(i);
        i += 1;
    }
    (*state).cwd[len] = 0;
    0
}

/// Copy cwd bytes into the caller's buffer and return the byte count.
///
/// # Safety
///
/// Pointers may be null. If non-null, `dst_buf` must be writable for `cap`
/// bytes and `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn tm_cred_getcwd(
    state: *const TmCredState,
    dst_buf: *mut c_char,
    cap: c_uint,
    out_len: *mut c_uint,
) -> c_int {
    if state.is_null() || dst_buf.is_null() || cap == 0 || out_len.is_null() {
        return -EINVAL;
    }

    let mut len = 0usize;
    while len < TM_CWD_MAX && (*state).cwd[len] != 0 {
        len += 1;
    }
    if len > cap as usize {
        return -ERANGE;
    }

    let mut i = 0usize;
    while i < len {
        *dst_buf.add(i) = (*state).cwd[i];
        i += 1;
    }
    *out_len = len as c_uint;
    0
}

/// Exchange-and-set umask.
///
/// # Safety
///
/// `state` and `out_old` may be null. If non-null, they must be valid for the
/// documented reads and writes.
#[no_mangle]
pub unsafe extern "C" fn tm_cred_umask(
    state: *mut TmCredState,
    set: c_int,
    out_old: *mut c_uint,
) -> c_int {
    if state.is_null() || out_old.is_null() {
        return -EINVAL;
    }
    *out_old = (*state).umask;
    if set >= 0 {
        (*state).umask = (set as c_uint) & 0o777;
    }
    0
}

/// Mutate credential fields, preserving fields passed as `TM_CRED_KEEP`.
///
/// # Safety
///
/// `state` may be null. If non-null, it must point to a writable
/// `tm_cred_state_t`-compatible record.
#[no_mangle]
pub unsafe extern "C" fn tm_cred_set(
    state: *mut TmCredState,
    ruid_new: c_uint,
    euid_new: c_uint,
    suid_new: c_uint,
    rgid_new: c_uint,
    egid_new: c_uint,
    sgid_new: c_uint,
) -> c_int {
    if state.is_null() {
        return -EINVAL;
    }
    if ruid_new != TM_CRED_KEEP {
        (*state).cred.ruid = ruid_new;
    }
    if euid_new != TM_CRED_KEEP {
        (*state).cred.euid = euid_new;
    }
    if suid_new != TM_CRED_KEEP {
        (*state).cred.suid = suid_new;
    }
    if rgid_new != TM_CRED_KEEP {
        (*state).cred.rgid = rgid_new;
    }
    if egid_new != TM_CRED_KEEP {
        (*state).cred.egid = egid_new;
    }
    if sgid_new != TM_CRED_KEEP {
        (*state).cred.sgid = sgid_new;
    }
    0
}

fn id_held(value: c_uint, a: c_uint, b: c_uint, c: c_uint) -> bool {
    value == TM_CRED_KEEP || value == a || value == b || value == c
}

/// Return non-zero when the requested credential change is permitted.
///
/// # Safety
///
/// `cur` may be null. If non-null, it must point to a readable
/// `_cred_info`-compatible record.
#[no_mangle]
pub unsafe extern "C" fn tm_cred_change_permitted(
    cur: *const TmCredInfo,
    ruid_new: c_uint,
    euid_new: c_uint,
    suid_new: c_uint,
    rgid_new: c_uint,
    egid_new: c_uint,
    sgid_new: c_uint,
) -> c_int {
    if cur.is_null() {
        return 0;
    }
    let cur = *cur;
    if cur.euid == 0 {
        return 1;
    }
    (id_held(ruid_new, cur.ruid, cur.euid, cur.suid)
        && id_held(euid_new, cur.ruid, cur.euid, cur.suid)
        && id_held(suid_new, cur.ruid, cur.euid, cur.suid)
        && id_held(rgid_new, cur.rgid, cur.egid, cur.sgid)
        && id_held(egid_new, cur.rgid, cur.egid, cur.sgid)
        && id_held(sgid_new, cur.rgid, cur.egid, cur.sgid)) as c_int
}

/// Copy out the current credential record.
///
/// # Safety
///
/// Pointers may be null. If non-null, `state` must be readable and `out_cred`
/// must be writable for one `_cred_info`-compatible record.
#[no_mangle]
pub unsafe extern "C" fn tm_cred_self_info(state: *const TmCredState, out_cred: *mut TmCredInfo) {
    if state.is_null() || out_cred.is_null() {
        return;
    }
    *out_cred = (*state).cred;
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::{offset_of, size_of};

    fn blank_state(fill: c_char) -> TmCredState {
        TmCredState {
            cwd: [fill; TM_CWD_MAX],
            umask: 0,
            cred: TmCredInfo {
                ruid: 99,
                euid: 99,
                suid: 99,
                rgid: 88,
                egid: 88,
                sgid: 88,
                ngroups: 7,
            },
        }
    }

    fn c_buf(bytes: &[u8]) -> [c_char; TM_CWD_MAX] {
        let mut out = [0 as c_char; TM_CWD_MAX];
        let mut i = 0usize;
        while i < bytes.len() {
            out[i] = bytes[i] as c_char;
            i += 1;
        }
        out
    }

    unsafe fn read_bytes(buf: &[c_char], len: usize) -> [u8; TM_CWD_MAX] {
        let mut out = [0u8; TM_CWD_MAX];
        let mut i = 0usize;
        while i < len {
            out[i] = buf[i] as u8;
            i += 1;
        }
        out
    }

    #[test]
    fn c_abi_layout_matches_tm_cred_h() {
        assert_eq!(size_of::<TmCredInfo>(), 28);
        assert_eq!(offset_of!(TmCredInfo, ruid), 0);
        assert_eq!(offset_of!(TmCredInfo, euid), 4);
        assert_eq!(offset_of!(TmCredInfo, suid), 8);
        assert_eq!(offset_of!(TmCredInfo, rgid), 12);
        assert_eq!(offset_of!(TmCredInfo, egid), 16);
        assert_eq!(offset_of!(TmCredInfo, sgid), 20);
        assert_eq!(offset_of!(TmCredInfo, ngroups), 24);

        assert_eq!(size_of::<TmCredState>(), 288);
        assert_eq!(offset_of!(TmCredState, cwd), 0);
        assert_eq!(offset_of!(TmCredState, umask), 256);
        assert_eq!(offset_of!(TmCredState, cred), 260);
    }

    #[test]
    fn init_sets_root_defaults_without_requiring_zeroed_input() {
        unsafe {
            let mut state = blank_state(0x55 as c_char);
            tm_cred_init(&mut state);

            assert_eq!(state.cwd[0] as u8, b'/');
            assert_eq!(state.cwd[1], 0);
            assert_eq!(state.cwd[2] as u8, 0x55);
            assert_eq!(state.umask, 0o022);
            assert_eq!(state.cred, TmCredInfo::root());

            tm_cred_init(core::ptr::null_mut());
        }
    }

    #[test]
    fn chdir_accepts_absolute_bounded_paths() {
        unsafe {
            let mut state = blank_state(0);
            let path = c_buf(b"/usr/bin");
            assert_eq!(tm_cred_chdir(&mut state, path.as_ptr(), 8), 0);
            assert_eq!(&read_bytes(&state.cwd, 8)[..8], b"/usr/bin");
            assert_eq!(state.cwd[8], 0);

            let rel = c_buf(b"tmp");
            assert_eq!(tm_cred_chdir(&mut state, rel.as_ptr(), 3), -EINVAL);
            assert_eq!(tm_cred_chdir(&mut state, path.as_ptr(), 0), -ENAMETOOLONG);
            assert_eq!(
                tm_cred_chdir(&mut state, path.as_ptr(), TM_CWD_MAX as c_uint),
                -ENAMETOOLONG
            );
            assert_eq!(
                tm_cred_chdir(core::ptr::null_mut(), path.as_ptr(), 1),
                -EINVAL
            );
            assert_eq!(tm_cred_chdir(&mut state, core::ptr::null(), 1), -EINVAL);
        }
    }

    #[test]
    fn getcwd_copies_without_trailing_nul() {
        unsafe {
            let mut state = blank_state(0);
            let path = c_buf(b"/home/root");
            assert_eq!(tm_cred_chdir(&mut state, path.as_ptr(), 10), 0);

            let mut dst = [0x66 as c_char; TM_CWD_MAX];
            let mut len = 0;
            assert_eq!(tm_cred_getcwd(&state, dst.as_mut_ptr(), 10, &mut len), 0);
            assert_eq!(len, 10);
            assert_eq!(&read_bytes(&dst, 10)[..10], b"/home/root");
            assert_eq!(dst[10] as u8, 0x66);

            len = 123;
            assert_eq!(
                tm_cred_getcwd(&state, dst.as_mut_ptr(), 9, &mut len),
                -ERANGE
            );
            assert_eq!(len, 123);

            assert_eq!(
                tm_cred_getcwd(core::ptr::null(), dst.as_mut_ptr(), 1, &mut len),
                -EINVAL
            );
            assert_eq!(
                tm_cred_getcwd(&state, core::ptr::null_mut(), 1, &mut len),
                -EINVAL
            );
            assert_eq!(
                tm_cred_getcwd(&state, dst.as_mut_ptr(), 0, &mut len),
                -EINVAL
            );
            assert_eq!(
                tm_cred_getcwd(&state, dst.as_mut_ptr(), 1, core::ptr::null_mut()),
                -EINVAL
            );
        }
    }

    #[test]
    fn umask_exchanges_and_masks_to_permissions_bits() {
        unsafe {
            let mut state = blank_state(0);
            state.umask = 0o022;
            let mut old = 0;

            assert_eq!(tm_cred_umask(&mut state, -1, &mut old), 0);
            assert_eq!(old, 0o022);
            assert_eq!(state.umask, 0o022);

            assert_eq!(tm_cred_umask(&mut state, 0o1777, &mut old), 0);
            assert_eq!(old, 0o022);
            assert_eq!(state.umask, 0o777);

            assert_eq!(tm_cred_umask(core::ptr::null_mut(), 0, &mut old), -EINVAL);
            assert_eq!(tm_cred_umask(&mut state, 0, core::ptr::null_mut()), -EINVAL);
        }
    }

    #[test]
    fn set_mutates_only_non_keep_fields_and_self_info_snapshots() {
        unsafe {
            let mut state = blank_state(0);
            tm_cred_init(&mut state);
            assert_eq!(
                tm_cred_set(&mut state, 100, TM_CRED_KEEP, 101, 200, TM_CRED_KEEP, 201),
                0
            );
            assert_eq!(
                state.cred,
                TmCredInfo {
                    ruid: 100,
                    euid: 0,
                    suid: 101,
                    rgid: 200,
                    egid: 0,
                    sgid: 201,
                    ngroups: 0,
                }
            );

            let mut out = TmCredInfo::root();
            tm_cred_self_info(&state, &mut out);
            assert_eq!(out, state.cred);
            tm_cred_self_info(core::ptr::null(), &mut out);
            tm_cred_self_info(&state, core::ptr::null_mut());

            assert_eq!(
                tm_cred_set(core::ptr::null_mut(), 1, 2, 3, 4, 5, 6,),
                -EINVAL
            );
        }
    }

    #[test]
    fn change_policy_allows_root_and_held_ids_only() {
        unsafe {
            let root = TmCredInfo {
                ruid: 10,
                euid: 0,
                suid: 11,
                rgid: 20,
                egid: 21,
                sgid: 22,
                ngroups: 0,
            };
            assert_eq!(
                tm_cred_change_permitted(&root, 999, 998, 997, 996, 995, 994),
                1
            );

            let user = TmCredInfo {
                ruid: 1000,
                euid: 1001,
                suid: 1002,
                rgid: 2000,
                egid: 2001,
                sgid: 2002,
                ngroups: 0,
            };
            assert_eq!(
                tm_cred_change_permitted(&user, 1002, 1000, TM_CRED_KEEP, 2001, 2002, TM_CRED_KEEP,),
                1
            );
            assert_eq!(
                tm_cred_change_permitted(&user, 0, 1000, 1001, 2000, 2001, 2002),
                0
            );
            assert_eq!(
                tm_cred_change_permitted(&user, 1000, 1001, 1002, 0, 2000, 2001),
                0
            );
            assert_eq!(
                tm_cred_change_permitted(
                    core::ptr::null(),
                    TM_CRED_KEEP,
                    TM_CRED_KEEP,
                    TM_CRED_KEEP,
                    TM_CRED_KEEP,
                    TM_CRED_KEEP,
                    TM_CRED_KEEP,
                ),
                0
            );
        }
    }
}
