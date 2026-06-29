#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

use core::ffi::{c_char, c_int, c_uint, c_ulonglong};

const PATHMGR_NODES: usize = 64;
const PATHMGR_NAME_MAX: usize = 30;
const PATHMGR_TARGET_MAX: usize = 128;
const PATHMGR_HANDLER_EXTERNAL: c_uint = 0;
const PATHMGR_HANDLER_TASKMAN_PMDIR: c_uint = 5;

const EINVAL: c_int = 22;
const ENOENT: c_int = 2;
const ENOMEM: c_int = 12;
const EEXIST: c_int = 17;

const TM_CPIO_S_IFMT: u32 = 0xF000;
const TM_CPIO_S_IFLNK: u32 = 0xA000;

const INVALID_IDX: i16 = -1;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TmPathmgrObj {
    pub server_pid: c_int,
    pub server_chid: c_int,
    pub flags: c_uint,
    pub handler_kind: c_uint,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TmCpioFileInfo {
    pub filename: [c_char; 64],
    pub filesize: u32,
    pub mode: u32,
    pub data: *const u8,
}

#[derive(Clone, Copy)]
struct Node {
    parent: i16,
    sibling: i16,
    child: i16,
    obj: TmPathmgrObj,
    has_obj: bool,
    is_symlink: bool,
    name_len: u8,
    target_len: u8,
    name: [u8; PATHMGR_NAME_MAX],
    target: [u8; PATHMGR_TARGET_MAX],
}

const EMPTY_OBJ: TmPathmgrObj = TmPathmgrObj {
    server_pid: 0,
    server_chid: 0,
    flags: 0,
    handler_kind: 0,
};

const EMPTY_NODE: Node = Node {
    parent: INVALID_IDX,
    sibling: INVALID_IDX,
    child: INVALID_IDX,
    obj: EMPTY_OBJ,
    has_obj: false,
    is_symlink: false,
    name_len: 0,
    target_len: 0,
    name: [0; PATHMGR_NAME_MAX],
    target: [0; PATHMGR_TARGET_MAX],
};

static mut G_POOL: [Node; PATHMGR_NODES] = [EMPTY_NODE; PATHMGR_NODES];
static mut G_POOL_USED: c_int = 0;
static mut G_ROOT: i16 = INVALID_IDX;

#[cfg(not(any(test, feature = "host-tests")))]
unsafe extern "C" {
    fn tm_cpio_find_file(
        data: *const u8,
        size: c_ulonglong,
        filename: *const c_char,
        info: *mut TmCpioFileInfo,
    ) -> c_int;
}

unsafe fn node_ptr(idx: i16) -> *mut Node {
    core::ptr::addr_of_mut!(G_POOL)
        .cast::<Node>()
        .add(idx as usize)
}

unsafe fn byte_at(path: *const c_char) -> u8 {
    *path as u8
}

unsafe fn write_c_byte(dst: *mut c_char, offset: usize, byte: u8) {
    *dst.add(offset) = byte as c_char;
}

unsafe fn pm_alloc(name: *const c_char, name_len: usize, parent: i16) -> i16 {
    if G_POOL_USED as usize >= PATHMGR_NODES || name_len > PATHMGR_NAME_MAX {
        return INVALID_IDX;
    }

    let idx = G_POOL_USED as i16;
    G_POOL_USED += 1;

    let n = node_ptr(idx);
    *n = EMPTY_NODE;
    (*n).parent = parent;
    (*n).name_len = name_len as u8;

    let mut i = 0usize;
    while i < name_len {
        (*n).name[i] = byte_at(name.add(i));
        i += 1;
    }

    idx
}

unsafe fn find_child(parent: i16, comp: *const c_char, len: usize) -> i16 {
    let mut child = (*node_ptr(parent)).child;
    while child != INVALID_IDX {
        let c = node_ptr(child);
        if (*c).name_len as usize == len {
            let mut i = 0usize;
            while i < len {
                if (*c).name[i] != byte_at(comp.add(i)) {
                    break;
                }
                i += 1;
            }
            if i == len {
                return child;
            }
        }
        child = (*c).sibling;
    }
    INVALID_IDX
}

unsafe fn add_child(parent: i16, comp: *const c_char, len: usize) -> i16 {
    let child = pm_alloc(comp, len, parent);
    if child == INVALID_IDX {
        return INVALID_IDX;
    }

    let parent_ptr = node_ptr(parent);
    (*node_ptr(child)).sibling = (*parent_ptr).child;
    (*parent_ptr).child = child;
    child
}

unsafe fn next_component(p: &mut *const c_char) -> Option<(*const c_char, usize)> {
    while byte_at(*p) == b'/' {
        *p = (*p).add(1);
    }
    if byte_at(*p) == 0 {
        return None;
    }

    let comp = *p;
    let mut len = 0usize;
    while byte_at(*p) != 0 && byte_at(*p) != b'/' {
        *p = (*p).add(1);
        len += 1;
    }
    Some((comp, len))
}

unsafe fn pm_walk(
    path: *const c_char,
    deepest_p_out: *mut *const c_char,
    is_symlink_out: *mut c_int,
) -> i16 {
    let mut node = G_ROOT;
    let mut deepest = INVALID_IDX;
    let mut deepest_p = path;
    let mut p = path;

    *is_symlink_out = 0;

    if (*node_ptr(G_ROOT)).has_obj {
        deepest = G_ROOT;
        deepest_p = path.add(1);
    }

    while let Some((comp, len)) = next_component(&mut p) {
        let child = find_child(node, comp, len);
        if child == INVALID_IDX {
            break;
        }
        node = child;
        let n = node_ptr(node);
        if (*n).is_symlink {
            deepest = node;
            deepest_p = p;
            *is_symlink_out = 1;
            break;
        }
        if (*n).has_obj {
            deepest = node;
            deepest_p = p;
        }
    }

    *deepest_p_out = deepest_p;
    deepest
}

unsafe fn strlen(path: *const c_char) -> usize {
    let mut len = 0usize;
    while byte_at(path.add(len)) != 0 {
        len += 1;
    }
    len
}

unsafe fn ptr_distance(start: *const c_char, end: *const c_char) -> c_uint {
    end.offset_from(start) as c_uint
}

#[cfg(any(test, feature = "host-tests"))]
unsafe fn cpio_find_file(
    _data: *const u8,
    _size: c_ulonglong,
    filename: *const c_char,
    info: *mut TmCpioFileInfo,
) -> c_int {
    const ETC_TARGET: &[u8; 9] = b"/usr/conf";
    const BIN_DATA: &[u8; 1] = b"x";

    if filename.is_null() || info.is_null() {
        return 0;
    }

    if cstr_eq(filename, b"etc\0") {
        (*info).filesize = ETC_TARGET.len() as u32;
        (*info).mode = TM_CPIO_S_IFLNK;
        (*info).data = ETC_TARGET.as_ptr();
        return 1;
    }
    if cstr_eq(filename, b"bin\0") {
        (*info).filesize = BIN_DATA.len() as u32;
        (*info).mode = 0x8000;
        (*info).data = BIN_DATA.as_ptr();
        return 1;
    }
    0
}

#[cfg(not(any(test, feature = "host-tests")))]
unsafe fn cpio_find_file(
    data: *const u8,
    size: c_ulonglong,
    filename: *const c_char,
    info: *mut TmCpioFileInfo,
) -> c_int {
    tm_cpio_find_file(data, size, filename, info)
}

#[cfg(any(test, feature = "host-tests"))]
unsafe fn cstr_eq(mut s: *const c_char, expected: &[u8]) -> bool {
    let mut i = 0usize;
    loop {
        let a = byte_at(s);
        if i >= expected.len() || a != expected[i] {
            return false;
        }
        if a == 0 {
            return true;
        }
        s = s.add(1);
        i += 1;
    }
}

#[no_mangle]
/// Reset the global path registry to an empty root.
///
/// # Safety
///
/// Callers must serialize access with any concurrent path registry users. The
/// C ABI is process-global and this function invalidates all prior registry
/// state.
pub unsafe extern "C" fn tm_pathmgr_init() {
    G_POOL_USED = 0;
    G_ROOT = pm_alloc(core::ptr::null(), 0, INVALID_IDX);
}

#[no_mangle]
/// Register a path-manager object at an absolute path.
///
/// # Safety
///
/// `path` must point to a readable NUL-terminated C string. `obj` must point to
/// a readable `tm_pathmgr_obj_t`. Callers must serialize access with other
/// registry mutations and lookups.
pub unsafe extern "C" fn tm_pathmgr_register(
    path: *const c_char,
    obj: *const TmPathmgrObj,
) -> c_int {
    if path.is_null() || byte_at(path) != b'/' || obj.is_null() || G_ROOT == INVALID_IDX {
        return -EINVAL;
    }

    let mut node = G_ROOT;
    let mut p = path;
    while let Some((comp, len)) = next_component(&mut p) {
        let mut child = find_child(node, comp, len);
        if child == INVALID_IDX {
            child = add_child(node, comp, len);
            if child == INVALID_IDX {
                return -ENOMEM;
            }
        }
        node = child;
    }

    let n = node_ptr(node);
    if (*n).has_obj {
        return -EINVAL;
    }

    (*n).obj = *obj;
    (*n).has_obj = true;
    0
}

#[no_mangle]
/// Remove external registrations owned by a process id.
///
/// # Safety
///
/// Callers must serialize access with other registry mutations and lookups.
pub unsafe extern "C" fn tm_pathmgr_unregister_pid(pid: c_int) -> c_int {
    let mut dropped = 0;
    let mut i = 0;
    while i < G_POOL_USED {
        let n = node_ptr(i as i16);
        if (*n).has_obj
            && (*n).obj.handler_kind == PATHMGR_HANDLER_EXTERNAL
            && (*n).obj.server_pid == pid
        {
            (*n).has_obj = false;
            dropped += 1;
        }
        i += 1;
    }
    dropped
}

#[no_mangle]
/// Resolve an absolute path to the deepest registered object.
///
/// # Safety
///
/// `path` must point to a readable NUL-terminated C string. `out` must be valid
/// for one `tm_pathmgr_obj_t` write. `out_consumed_bytes` may be null; when
/// non-null it must be valid for one `unsigned` write. Callers must serialize
/// access with concurrent registry mutations.
pub unsafe extern "C" fn tm_pathmgr_resolve(
    path: *const c_char,
    out: *mut TmPathmgrObj,
    out_consumed_bytes: *mut c_uint,
) -> c_int {
    if path.is_null() || byte_at(path) != b'/' || out.is_null() || G_ROOT == INVALID_IDX {
        return -EINVAL;
    }

    let mut deepest_p = path;
    let mut is_symlink = 0;
    let deepest = pm_walk(path, &mut deepest_p, &mut is_symlink);
    if deepest == INVALID_IDX {
        return -ENOENT;
    }

    let deepest_node = node_ptr(deepest);
    if is_symlink != 0 {
        let mut target_p = deepest_p;
        let mut target_is_symlink = 0;
        let target = pm_walk(
            (*deepest_node).target.as_ptr().cast::<c_char>(),
            &mut target_p,
            &mut target_is_symlink,
        );
        if target == INVALID_IDX || target_is_symlink != 0 || !(*node_ptr(target)).has_obj {
            return -ENOENT;
        }
        *out = (*node_ptr(target)).obj;
        if !out_consumed_bytes.is_null() {
            *out_consumed_bytes = ptr_distance(path, deepest_p);
        }
        return 0;
    }

    if (*deepest_node).obj.handler_kind == PATHMGR_HANDLER_TASKMAN_PMDIR {
        let mut rest = deepest_p;
        while byte_at(rest) == b'/' {
            rest = rest.add(1);
        }
        if byte_at(rest) != 0 {
            return -ENOENT;
        }
    }

    *out = (*deepest_node).obj;
    if !out_consumed_bytes.is_null() {
        *out_consumed_bytes = ptr_distance(path, deepest_p);
    }
    0
}

#[no_mangle]
/// Update an existing path registration.
///
/// # Safety
///
/// `path` must point to a readable NUL-terminated C string. `new_obj` must
/// point to a readable `tm_pathmgr_obj_t`. Callers must serialize access with
/// other registry mutations and lookups.
pub unsafe extern "C" fn tm_pathmgr_repath(
    path: *const c_char,
    new_obj: *const TmPathmgrObj,
) -> c_int {
    if path.is_null() || byte_at(path) != b'/' || new_obj.is_null() || G_ROOT == INVALID_IDX {
        return -EINVAL;
    }

    let mut node = G_ROOT;
    let mut p = path;
    while let Some((comp, len)) = next_component(&mut p) {
        let child = find_child(node, comp, len);
        if child == INVALID_IDX {
            return -ENOENT;
        }
        node = child;
    }

    let n = node_ptr(node);
    if !(*n).has_obj {
        return -ENOENT;
    }
    (*n).obj = *new_obj;
    0
}

#[no_mangle]
/// Create an in-memory path-manager symlink.
///
/// # Safety
///
/// `link_path` and `target_path` must point to readable NUL-terminated absolute
/// path strings. Callers must serialize access with other registry mutations
/// and lookups.
pub unsafe extern "C" fn tm_pathmgr_symlink(
    link_path: *const c_char,
    target_path: *const c_char,
) -> c_int {
    if link_path.is_null() || byte_at(link_path) != b'/' || G_ROOT == INVALID_IDX {
        return -EINVAL;
    }
    if target_path.is_null() || byte_at(target_path) != b'/' {
        return -EINVAL;
    }

    let target_len = strlen(target_path);
    if target_len == 0 || target_len >= PATHMGR_TARGET_MAX {
        return -EINVAL;
    }

    let mut node = G_ROOT;
    let mut p = link_path;
    while let Some((comp, len)) = next_component(&mut p) {
        let mut child = find_child(node, comp, len);
        if child == INVALID_IDX {
            child = add_child(node, comp, len);
            if child == INVALID_IDX {
                return -ENOMEM;
            }
        }
        node = child;
    }

    let n = node_ptr(node);
    if (*n).has_obj || (*n).is_symlink {
        return -EEXIST;
    }

    (*n).is_symlink = true;
    (*n).target_len = target_len as u8;
    let mut i = 0usize;
    while i < target_len {
        (*n).target[i] = byte_at(target_path.add(i));
        i += 1;
    }
    (*n).target[target_len] = 0;
    0
}

#[no_mangle]
/// Expand a leading symlink stored in the boot CPIO archive.
///
/// # Safety
///
/// `cpio` must be readable for `size` bytes when non-null. `path` must point to
/// a readable NUL-terminated C string. `out` must be writable for `cap` bytes
/// when `cap` is non-zero.
pub unsafe extern "C" fn tm_pathmgr_expand_symlink_cpio(
    cpio: *const u8,
    size: c_ulonglong,
    path: *const c_char,
    out: *mut c_char,
    cap: c_uint,
) -> c_int {
    if cpio.is_null()
        || size == 0
        || path.is_null()
        || byte_at(path) != b'/'
        || out.is_null()
        || cap == 0
    {
        return 0;
    }

    let mut p = path;
    while byte_at(p) == b'/' {
        p = p.add(1);
    }
    let comp = p;
    let mut clen = 0usize;
    while byte_at(p) != 0 && byte_at(p) != b'/' {
        p = p.add(1);
        clen += 1;
    }
    if clen == 0 || clen + 1 > PATHMGR_NAME_MAX + 1 {
        return 0;
    }

    let mut name = [0 as c_char; PATHMGR_NAME_MAX + 1];
    let mut i = 0usize;
    while i < clen {
        name[i] = byte_at(comp.add(i)) as c_char;
        i += 1;
    }
    name[clen] = 0;

    let mut info = TmCpioFileInfo {
        filename: [0; 64],
        filesize: 0,
        mode: 0,
        data: core::ptr::null(),
    };
    if cpio_find_file(cpio, size, name.as_ptr(), &mut info) == 0 {
        return 0;
    }
    if (info.mode & TM_CPIO_S_IFMT) != TM_CPIO_S_IFLNK {
        return 0;
    }

    let cap = cap as usize;
    let mut o = 0usize;
    let mut di = 0usize;
    while di < info.filesize as usize {
        if o + 1 >= cap {
            return 0;
        }
        write_c_byte(out, o, *info.data.add(di));
        o += 1;
        di += 1;
    }
    while byte_at(p) != 0 {
        if o + 1 >= cap {
            return 0;
        }
        write_c_byte(out, o, byte_at(p));
        o += 1;
        p = p.add(1);
    }
    write_c_byte(out, o, 0);
    1
}

#[no_mangle]
/// Expand the first registered path-manager symlink in an absolute path.
///
/// # Safety
///
/// `path` must point to a readable NUL-terminated C string. `out` must be
/// writable for `out_cap` bytes when `out_cap` is non-zero. Callers must
/// serialize access with concurrent registry mutations.
pub unsafe extern "C" fn tm_pathmgr_expand_symlink(
    path: *const c_char,
    out: *mut c_char,
    out_cap: c_uint,
) -> c_int {
    if path.is_null()
        || byte_at(path) != b'/'
        || out.is_null()
        || out_cap == 0
        || G_ROOT == INVALID_IDX
    {
        return 0;
    }

    let mut node = G_ROOT;
    let mut p = path;
    while let Some((comp, len)) = next_component(&mut p) {
        let child = find_child(node, comp, len);
        if child == INVALID_IDX {
            return 0;
        }
        node = child;
        let n = node_ptr(node);
        if (*n).is_symlink {
            let cap = out_cap as usize;
            let mut o = 0usize;
            let mut i = 0usize;
            while i < (*n).target_len as usize {
                if o + 1 >= cap {
                    return 0;
                }
                write_c_byte(out, o, (*n).target[i]);
                o += 1;
                i += 1;
            }
            while byte_at(p) != 0 {
                if o + 1 >= cap {
                    return 0;
                }
                write_c_byte(out, o, byte_at(p));
                o += 1;
                p = p.add(1);
            }
            write_c_byte(out, o, 0);
            return 1;
        }
    }
    0
}

#[no_mangle]
/// Return the `idx`th direct child of a path-manager node.
///
/// # Safety
///
/// `path` must point to a readable NUL-terminated C string. `name_out` must be
/// writable for `name_cap` bytes when `name_cap` is non-zero. `out_namelen`
/// must be valid for one `unsigned` write. Callers must serialize access with
/// concurrent registry mutations.
pub unsafe extern "C" fn tm_pathmgr_child_at(
    path: *const c_char,
    idx: c_uint,
    name_out: *mut c_char,
    name_cap: c_uint,
    out_namelen: *mut c_uint,
) -> c_int {
    if path.is_null() || byte_at(path) != b'/' || G_ROOT == INVALID_IDX {
        return -EINVAL;
    }
    if name_out.is_null() || name_cap == 0 || out_namelen.is_null() {
        return -EINVAL;
    }

    let mut node = G_ROOT;
    let mut p = path;
    while let Some((comp, len)) = next_component(&mut p) {
        let child = find_child(node, comp, len);
        if child == INVALID_IDX {
            return -EINVAL;
        }
        node = child;
    }

    let mut child = (*node_ptr(node)).child;
    let mut i = 0u32;
    while child != INVALID_IDX && i < idx {
        child = (*node_ptr(child)).sibling;
        i += 1;
    }
    if child == INVALID_IDX {
        return -ENOENT;
    }

    let child_ptr = node_ptr(child);
    let mut nlen = (*child_ptr).name_len as usize;
    if nlen + 1 > name_cap as usize {
        nlen = name_cap as usize - 1;
    }

    let mut k = 0usize;
    while k < nlen {
        write_c_byte(name_out, k, (*child_ptr).name[k]);
        k += 1;
    }
    write_c_byte(name_out, nlen, 0);
    *out_namelen = nlen as c_uint;
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::ffi::CStr;
    use std::sync::{Mutex, MutexGuard};

    static TEST_LOCK: Mutex<()> = Mutex::new(());

    fn init() -> MutexGuard<'static, ()> {
        let guard = TEST_LOCK.lock().unwrap();
        unsafe {
            tm_pathmgr_init();
        }
        guard
    }

    fn obj(pid: c_int, chid: c_int, kind: c_uint) -> TmPathmgrObj {
        TmPathmgrObj {
            server_pid: pid,
            server_chid: chid,
            flags: 0xabc,
            handler_kind: kind,
        }
    }

    unsafe fn resolve(path: &'static [u8]) -> (c_int, TmPathmgrObj, c_uint) {
        let mut out = EMPTY_OBJ;
        let mut consumed = 0;
        let rc = tm_pathmgr_resolve(path.as_ptr().cast::<c_char>(), &mut out, &mut consumed);
        (rc, out, consumed)
    }

    unsafe fn child(path: &'static [u8], idx: c_uint, cap: usize) -> (c_int, String, c_uint) {
        let mut name = vec![0 as c_char; cap];
        let mut namelen = 0;
        let rc = tm_pathmgr_child_at(
            path.as_ptr().cast::<c_char>(),
            idx,
            name.as_mut_ptr(),
            name.len() as c_uint,
            &mut namelen,
        );
        let s = if cap == 0 {
            String::new()
        } else {
            CStr::from_ptr(name.as_ptr()).to_string_lossy().into_owned()
        };
        (rc, s, namelen)
    }

    #[test]
    fn registers_and_resolves_longest_prefix() {
        let _guard = init();
        unsafe {
            let root = obj(1, 10, 2);
            let console = obj(2, 20, PATHMGR_HANDLER_EXTERNAL);
            assert_eq!(tm_pathmgr_register(c"/".as_ptr(), &root), 0);
            assert_eq!(tm_pathmgr_register(c"/dev/console".as_ptr(), &console), 0);
            assert_eq!(
                tm_pathmgr_register(c"/dev/console".as_ptr(), &console),
                -EINVAL
            );

            let (rc, out, consumed) = resolve(b"/bin/qsh\0");
            assert_eq!(rc, 0);
            assert_eq!(out, root);
            assert_eq!(consumed, 1);

            let (rc, out, consumed) = resolve(b"/dev/console/extra\0");
            assert_eq!(rc, 0);
            assert_eq!(out, console);
            assert_eq!(consumed, 12);
        }
    }

    #[test]
    fn pmdir_rejects_missing_child_remainder() {
        let _guard = init();
        unsafe {
            let dev = obj(1, 30, PATHMGR_HANDLER_TASKMAN_PMDIR);
            assert_eq!(tm_pathmgr_register(c"/dev".as_ptr(), &dev), 0);

            let (rc, out, consumed) = resolve(b"/dev\0");
            assert_eq!(rc, 0);
            assert_eq!(out, dev);
            assert_eq!(consumed, 4);

            let (rc, _, _) = resolve(b"/dev/missing\0");
            assert_eq!(rc, -ENOENT);
        }
    }

    #[test]
    fn repath_and_unregister_external_only() {
        let _guard = init();
        unsafe {
            let external = obj(42, 7, PATHMGR_HANDLER_EXTERNAL);
            let internal = obj(42, 8, 2);
            let replacement = obj(43, 9, PATHMGR_HANDLER_EXTERNAL);

            assert_eq!(tm_pathmgr_register(c"/srv".as_ptr(), &external), 0);
            assert_eq!(tm_pathmgr_register(c"/boot".as_ptr(), &internal), 0);
            assert_eq!(tm_pathmgr_repath(c"/srv".as_ptr(), &replacement), 0);
            let (rc, out, _) = resolve(b"/srv/file\0");
            assert_eq!(rc, 0);
            assert_eq!(out, replacement);

            assert_eq!(tm_pathmgr_unregister_pid(42), 0);
            assert_eq!(tm_pathmgr_unregister_pid(43), 1);
            assert_eq!(resolve(b"/srv/file\0").0, -ENOENT);
            assert_eq!(resolve(b"/boot/init\0").0, 0);
        }
    }

    #[test]
    fn symlink_resolves_and_expands_one_level() {
        let _guard = init();
        unsafe {
            let console = obj(9, 2, PATHMGR_HANDLER_EXTERNAL);
            assert_eq!(tm_pathmgr_register(c"/dev/console".as_ptr(), &console), 0);
            assert_eq!(
                tm_pathmgr_symlink(c"/dev/tty".as_ptr(), c"/dev/console".as_ptr()),
                0
            );

            let (rc, out, consumed) = resolve(b"/dev/tty/session\0");
            assert_eq!(rc, 0);
            assert_eq!(out, console);
            assert_eq!(consumed, 8);

            let mut expanded = [0 as c_char; 64];
            assert_eq!(
                tm_pathmgr_expand_symlink(
                    c"/dev/tty/session".as_ptr(),
                    expanded.as_mut_ptr(),
                    expanded.len() as c_uint,
                ),
                1
            );
            assert_eq!(
                CStr::from_ptr(expanded.as_ptr()).to_str().unwrap(),
                "/dev/console/session"
            );

            assert_eq!(
                tm_pathmgr_symlink(c"/link2".as_ptr(), c"/dev/tty".as_ptr()),
                0
            );
            assert_eq!(resolve(b"/link2\0").0, -ENOENT);
        }
    }

    #[test]
    fn cpio_symlink_expansion_uses_first_component() {
        let _guard = init();
        unsafe {
            let cpio = [1u8];
            let mut out = [0 as c_char; 64];
            assert_eq!(
                tm_pathmgr_expand_symlink_cpio(
                    cpio.as_ptr(),
                    cpio.len() as c_ulonglong,
                    c"/etc/passwd".as_ptr(),
                    out.as_mut_ptr(),
                    out.len() as c_uint,
                ),
                1
            );
            assert_eq!(
                CStr::from_ptr(out.as_ptr()).to_str().unwrap(),
                "/usr/conf/passwd"
            );
            assert_eq!(
                tm_pathmgr_expand_symlink_cpio(
                    cpio.as_ptr(),
                    cpio.len() as c_ulonglong,
                    c"/bin/qsh".as_ptr(),
                    out.as_mut_ptr(),
                    out.len() as c_uint,
                ),
                0
            );
            assert_eq!(
                tm_pathmgr_expand_symlink_cpio(
                    cpio.as_ptr(),
                    cpio.len() as c_ulonglong,
                    c"/etc/passwd".as_ptr(),
                    out.as_mut_ptr(),
                    8,
                ),
                0
            );
        }
    }

    #[test]
    fn child_enumeration_is_newest_first_and_truncates() {
        let _guard = init();
        unsafe {
            let d = obj(1, 1, PATHMGR_HANDLER_TASKMAN_PMDIR);
            assert_eq!(tm_pathmgr_register(c"/dev".as_ptr(), &d), 0);
            assert_eq!(tm_pathmgr_register(c"/dev/console".as_ptr(), &d), 0);
            assert_eq!(tm_pathmgr_register(c"/dev/null".as_ptr(), &d), 0);

            let (rc, name, len) = child(b"/dev\0", 0, 16);
            assert_eq!(rc, 0);
            assert_eq!(name, "null");
            assert_eq!(len, 4);

            let (rc, name, len) = child(b"/dev\0", 1, 5);
            assert_eq!(rc, 0);
            assert_eq!(name, "cons");
            assert_eq!(len, 4);

            assert_eq!(child(b"/dev\0", 2, 16).0, -ENOENT);
            assert_eq!(child(b"/missing\0", 0, 16).0, -EINVAL);
        }
    }
}
