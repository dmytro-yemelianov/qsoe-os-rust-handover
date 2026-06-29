#![cfg_attr(not(any(test, feature = "host-tests")), no_std)]

use core::cell::UnsafeCell;
use core::ffi::{c_char, c_int, c_uint, c_ulong, c_void};

#[cfg(not(any(test, feature = "host-tests")))]
use core::panic::PanicInfo;

const EINVAL: c_int = 21;
const ENOMEM: c_int = 12;
const ENOSPC: c_int = 26;

const TM_RSRC_POOL_SIZE: usize = 256;
const TM_RSRC_NAME_MAX: usize = 28;
const RSRCDBMGR_TYPE_MASK: u32 = 0xff;
const RSRCDBMGR_MEMORY: u16 = 0;
const RSRCDBMGR_TYPE_COUNT: usize = 8;
const RSRCDBMGR_FLAG_MASK: u32 = 0xffffff00;
const RSRCDBMGR_FLAG_USED: u32 = 0x00000100;
const RSRCDBMGR_FLAG_ALIGN: u32 = 0x00000200;
const RSRCDBMGR_FLAG_RANGE: u32 = 0x00000400;

const TM_SYSCFG_TAG_END: u16 = 0;
const TM_SYSCFG_TAG_MEMORY: u16 = 7;

const QSOE_MSG_MAX_LENGTH: usize = 120;
const QSOE_MSG_MAX_EXTRA_CAPS: usize = 3;
const NONE: usize = usize::MAX;

type PidT = c_int;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RsrcAlloc {
    pub start: u64,
    pub end: u64,
    pub flags: u32,
    pub name: *const c_char,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RsrcRequest {
    pub length: u64,
    pub align: u64,
    pub start: u64,
    pub end: u64,
    pub flags: u32,
    pub zero: [u32; 2],
    pub name: *const c_char,
}

#[repr(C)]
struct QsoeIpcbuf {
    tag: c_ulong,
    msg: [c_ulong; QSOE_MSG_MAX_LENGTH],
    user_data: c_ulong,
    caps_or_badges: [c_ulong; QSOE_MSG_MAX_EXTRA_CAPS],
    receive_cnode: c_ulong,
    receive_index: c_ulong,
    receive_depth: c_ulong,
}

#[cfg(any(test, feature = "host-tests"))]
impl QsoeIpcbuf {
    const fn zeroed() -> Self {
        Self {
            tag: 0,
            msg: [0; QSOE_MSG_MAX_LENGTH],
            user_data: 0,
            caps_or_badges: [0; QSOE_MSG_MAX_EXTRA_CAPS],
            receive_cnode: 0,
            receive_index: 0,
            receive_depth: 0,
        }
    }
}

#[repr(C)]
#[allow(dead_code)]
struct QsoeTcbPrefix {
    tid: c_int,
    qerrno: c_int,
    cancel_pending: c_int,
    detached: c_int,
    exited: c_int,
    reaped: c_int,
    self_pid: c_int,
    ipcbuf: *mut QsoeIpcbuf,
}

#[derive(Clone, Copy)]
struct Entry {
    next: usize,
    start: u64,
    end: u64,
    owner: PidT,
    class: u16,
    flags: u16,
    name: [u8; TM_RSRC_NAME_MAX],
}

impl Entry {
    const fn zeroed() -> Self {
        Self {
            next: NONE,
            start: 0,
            end: 0,
            owner: 0,
            class: 0,
            flags: 0,
            name: [0; TM_RSRC_NAME_MAX],
        }
    }
}

struct ResourceDb {
    pool: [Entry; TM_RSRC_POOL_SIZE],
    free_head: usize,
    class_head: [usize; RSRCDBMGR_TYPE_COUNT],
}

impl ResourceDb {
    const fn new() -> Self {
        Self {
            pool: [Entry::zeroed(); TM_RSRC_POOL_SIZE],
            free_head: NONE,
            class_head: [NONE; RSRCDBMGR_TYPE_COUNT],
        }
    }

    fn init(&mut self) {
        self.free_head = NONE;
        let mut i = TM_RSRC_POOL_SIZE;
        while i > 0 {
            i -= 1;
            self.pool[i].next = self.free_head;
            self.free_head = i;
        }
        let mut c = 0usize;
        while c < RSRCDBMGR_TYPE_COUNT {
            self.class_head[c] = NONE;
            c += 1;
        }
    }

    fn pool_alloc(&mut self) -> Option<usize> {
        let idx = self.free_head;
        if idx == NONE {
            return None;
        }
        self.free_head = self.pool[idx].next;
        self.pool[idx] = Entry::zeroed();
        Some(idx)
    }

    fn pool_free(&mut self, idx: usize) {
        self.pool[idx].next = self.free_head;
        self.free_head = idx;
    }

    fn list_insert(&mut self, idx: usize) {
        let class = self.pool[idx].class as usize;
        if class >= RSRCDBMGR_TYPE_COUNT {
            return;
        }

        let mut prev = NONE;
        let mut cur = self.class_head[class];
        while cur != NONE && self.pool[cur].start < self.pool[idx].start {
            prev = cur;
            cur = self.pool[cur].next;
        }

        self.pool[idx].next = cur;
        if prev == NONE {
            self.class_head[class] = idx;
        } else {
            self.pool[prev].next = idx;
        }
    }

    fn list_remove(&mut self, idx: usize) {
        let class = self.pool[idx].class as usize;
        if class >= RSRCDBMGR_TYPE_COUNT {
            return;
        }

        let mut prev = NONE;
        let mut cur = self.class_head[class];
        while cur != NONE && cur != idx {
            prev = cur;
            cur = self.pool[cur].next;
        }
        if cur == NONE {
            return;
        }
        if prev == NONE {
            self.class_head[class] = self.pool[idx].next;
        } else {
            self.pool[prev].next = self.pool[idx].next;
        }
        self.pool[idx].next = NONE;
    }

    fn find_fit(&self, class: u16, req: &RsrcRequest) -> Option<(usize, u64, u64)> {
        let class_idx = class as usize;
        if class_idx >= RSRCDBMGR_TYPE_COUNT {
            return None;
        }

        let range = (req.flags & RSRCDBMGR_FLAG_RANGE) != 0;
        let aligned = (req.flags & RSRCDBMGR_FLAG_ALIGN) != 0;
        let align = if aligned && req.align != 0 {
            req.align
        } else {
            1
        };

        let mut cur = self.class_head[class_idx];
        while cur != NONE {
            let e = self.pool[cur];
            if e.owner == 0 {
                let mut lo = e.start;
                let mut hi = e.end;
                if range {
                    if req.start > lo {
                        lo = req.start;
                    }
                    if req.end < hi {
                        hi = req.end;
                    }
                }
                if hi >= lo {
                    if align > 1 {
                        lo = lo.wrapping_add(align).wrapping_sub(1) & !(align - 1);
                    }
                    let granted_end =
                        lo.wrapping_add(if req.length != 0 { req.length - 1 } else { 0 });
                    if granted_end >= lo && granted_end <= hi {
                        return Some((cur, lo, granted_end));
                    }
                }
            }
            cur = self.pool[cur].next;
        }
        None
    }

    fn carve(
        &mut self,
        idx: usize,
        g_start: u64,
        g_end: u64,
        owner: PidT,
        flags: u32,
        name: *const c_char,
    ) -> Result<usize, c_int> {
        let carved = self.pool_alloc().ok_or(-ENOMEM)?;
        let mut right = NONE;
        if g_end < self.pool[idx].end {
            right = match self.pool_alloc() {
                Some(idx) => idx,
                None => {
                    self.pool_free(carved);
                    return Err(-ENOMEM);
                }
            };
        }

        self.pool[carved].class = self.pool[idx].class;
        self.pool[carved].start = g_start;
        self.pool[carved].end = g_end;
        self.pool[carved].owner = owner;
        self.pool[carved].flags = ((flags & RSRCDBMGR_FLAG_MASK) >> 8) as u16;
        unsafe {
            copy_name(&mut self.pool[carved].name, name);
        }

        if right != NONE {
            self.pool[right].class = self.pool[idx].class;
            self.pool[right].start = g_end.wrapping_add(1);
            self.pool[right].end = self.pool[idx].end;
            self.pool[right].owner = 0;
            self.pool[right].flags = 0;
        }

        if g_start > self.pool[idx].start {
            self.pool[idx].end = g_start - 1;
        } else {
            self.list_remove(idx);
            self.pool_free(idx);
        }

        self.list_insert(carved);
        if right != NONE {
            self.list_insert(right);
        }
        Ok(carved)
    }

    fn merge_neighbours(&mut self, idx: usize) {
        let class = self.pool[idx].class as usize;
        if class >= RSRCDBMGR_TYPE_COUNT {
            return;
        }

        let mut prev = NONE;
        let mut cur = self.class_head[class];
        while cur != NONE && cur != idx {
            prev = cur;
            cur = self.pool[cur].next;
        }
        if cur == NONE {
            return;
        }

        let right = self.pool[idx].next;
        if right != NONE
            && self.pool[right].owner == 0
            && self.pool[right].start == self.pool[idx].end.wrapping_add(1)
        {
            self.pool[idx].end = self.pool[right].end;
            self.pool[idx].next = self.pool[right].next;
            self.pool_free(right);
        }

        if prev != NONE
            && self.pool[prev].owner == 0
            && self.pool[prev].end.wrapping_add(1) == self.pool[idx].start
        {
            self.pool[prev].end = self.pool[idx].end;
            self.pool[prev].next = self.pool[idx].next;
            self.pool_free(idx);
        }
    }

    unsafe fn create(&mut self, caller: PidT, count: c_uint) -> c_int {
        let p = ipc_payload_ptr().cast::<RsrcAlloc>();
        if p.is_null() {
            return -EINVAL;
        }

        let mut i = 0usize;
        while i < count as usize {
            let item = *p.add(i);
            let class = (item.flags & RSRCDBMGR_TYPE_MASK) as u16;
            if class as usize >= RSRCDBMGR_TYPE_COUNT {
                return -EINVAL;
            }
            let Some(idx) = self.pool_alloc() else {
                return -ENOMEM;
            };
            self.pool[idx].class = class;
            self.pool[idx].start = item.start;
            self.pool[idx].end = item.end;
            self.pool[idx].owner = if (item.flags & RSRCDBMGR_FLAG_USED) != 0 {
                caller
            } else {
                0
            };
            self.list_insert(idx);
            if self.pool[idx].owner == 0 {
                self.merge_neighbours(idx);
            }
            i += 1;
        }
        0
    }

    unsafe fn destroy(&mut self, count: c_uint) -> c_int {
        let p = ipc_payload_ptr().cast::<RsrcAlloc>();
        if p.is_null() {
            return -EINVAL;
        }

        let mut i = 0usize;
        while i < count as usize {
            let item = *p.add(i);
            let class = (item.flags & RSRCDBMGR_TYPE_MASK) as usize;
            if class >= RSRCDBMGR_TYPE_COUNT {
                return -EINVAL;
            }
            let mut cur = self.class_head[class];
            while cur != NONE {
                let next = self.pool[cur].next;
                if self.pool[cur].start == item.start && self.pool[cur].end == item.end {
                    self.list_remove(cur);
                    self.pool_free(cur);
                    break;
                }
                cur = next;
            }
            i += 1;
        }
        0
    }

    unsafe fn attach(&mut self, caller: PidT, count: c_uint) -> c_int {
        let p = ipc_payload_ptr().cast::<RsrcRequest>();
        if p.is_null() {
            return -EINVAL;
        }
        if count > 16 {
            return -EINVAL;
        }

        let mut granted = [NONE; 16];
        let mut ngranted = 0usize;
        let mut i = 0usize;

        while i < count as usize {
            let req = *p.add(i);
            let class = (req.flags & RSRCDBMGR_TYPE_MASK) as u16;
            if class as usize >= RSRCDBMGR_TYPE_COUNT {
                return self.rollback_attach(&granted, ngranted);
            }

            let Some((fit, gs, ge)) = self.find_fit(class, &req) else {
                return self.rollback_attach(&granted, ngranted);
            };
            let carved = match self.carve(fit, gs, ge, caller, req.flags, core::ptr::null()) {
                Ok(idx) => idx,
                Err(_) => return self.rollback_attach(&granted, ngranted),
            };

            granted[ngranted] = carved;
            ngranted += 1;

            (*p.add(i)).start = gs;
            (*p.add(i)).end = ge;
            (*p.add(i)).length = ge.wrapping_sub(gs).wrapping_add(1);
            i += 1;
        }
        0
    }

    fn rollback_attach(&mut self, granted: &[usize; 16], ngranted: usize) -> c_int {
        let mut j = 0usize;
        while j < ngranted {
            let idx = granted[j];
            if idx != NONE {
                self.pool[idx].owner = 0;
                self.merge_neighbours(idx);
            }
            j += 1;
        }
        -ENOSPC
    }

    unsafe fn detach(&mut self, caller: PidT, count: c_uint) -> c_int {
        let p = ipc_payload_ptr().cast::<RsrcRequest>();
        if p.is_null() {
            return -EINVAL;
        }

        let mut i = 0usize;
        while i < count as usize {
            let req = *p.add(i);
            let class = (req.flags & RSRCDBMGR_TYPE_MASK) as usize;
            if class >= RSRCDBMGR_TYPE_COUNT {
                return -EINVAL;
            }
            let mut cur = self.class_head[class];
            while cur != NONE {
                let next = self.pool[cur].next;
                if self.pool[cur].owner == caller
                    && self.pool[cur].start == req.start
                    && self.pool[cur].end == req.end
                {
                    self.pool[cur].owner = 0;
                    self.pool[cur].flags = 0;
                    self.merge_neighbours(cur);
                    break;
                }
                cur = next;
            }
            i += 1;
        }
        0
    }

    unsafe fn query(
        &mut self,
        listcnt: c_uint,
        start: c_uint,
        type_: u32,
        out_written: *mut c_uint,
    ) -> c_int {
        if out_written.is_null() {
            return -EINVAL;
        }
        let class = (type_ & RSRCDBMGR_TYPE_MASK) as usize;
        if class >= RSRCDBMGR_TYPE_COUNT {
            return -EINVAL;
        }

        let p = ipc_payload_ptr().cast::<RsrcAlloc>();
        if p.is_null() {
            return -EINVAL;
        }

        let mut idx = 0u32;
        let mut written = 0u32;
        let mut cur = self.class_head[class];
        while cur != NONE {
            if idx >= start {
                if listcnt != 0 && written >= listcnt {
                    break;
                }
                if listcnt != 0 {
                    *p.add(written as usize) = RsrcAlloc {
                        start: self.pool[cur].start,
                        end: self.pool[cur].end,
                        flags: u32::from(self.pool[cur].class)
                            | if self.pool[cur].owner != 0 {
                                RSRCDBMGR_FLAG_USED
                            } else {
                                0
                            },
                        name: core::ptr::null(),
                    };
                }
                written += 1;
            }
            idx += 1;
            cur = self.pool[cur].next;
        }
        *out_written = written;
        0
    }

    fn release_pid(&mut self, pid: PidT) {
        if pid <= 0 {
            return;
        }

        let mut class = 0usize;
        while class < RSRCDBMGR_TYPE_COUNT {
            let mut cur = self.class_head[class];
            while cur != NONE {
                let next = self.pool[cur].next;
                if self.pool[cur].owner == pid {
                    self.pool[cur].owner = 0;
                    self.pool[cur].flags = 0;
                    self.merge_neighbours(cur);
                    cur = self.class_head[class];
                    continue;
                }
                cur = next;
            }
            class += 1;
        }
    }

    unsafe fn seed_from_syscfg(&mut self) {
        let mut blob: *const c_void = core::ptr::null();
        let mut blob_len: c_uint = 0;
        if tm_syscfg_get(&mut blob, &mut blob_len) != 0 {
            return;
        }
        if blob.is_null() {
            return;
        }

        let bp = blob.cast::<u8>();
        let mut off = 0usize;
        while off + 4 <= blob_len as usize {
            let id = read_le16(bp.add(off));
            let len = read_le16(bp.add(off + 2)) as usize;
            if id == TM_SYSCFG_TAG_END {
                break;
            }
            if id == TM_SYSCFG_TAG_MEMORY && len == 16 {
                let base = read_le64(bp.add(off + 4));
                let size = read_le64(bp.add(off + 12));
                let Some(idx) = self.pool_alloc() else {
                    return;
                };
                self.pool[idx].class = RSRCDBMGR_MEMORY;
                self.pool[idx].start = base;
                self.pool[idx].end = base.wrapping_add(size).wrapping_sub(1);
                self.pool[idx].owner = 0;
                self.list_insert(idx);
            }
            off += 4 + len;
        }
    }
}

struct GlobalDb(UnsafeCell<ResourceDb>);

unsafe impl Sync for GlobalDb {}

static DB: GlobalDb = GlobalDb(UnsafeCell::new(ResourceDb::new()));

#[cfg(any(test, feature = "host-tests"))]
static HOST_IPCBUF: GlobalIpcbuf = GlobalIpcbuf(UnsafeCell::new(QsoeIpcbuf::zeroed()));

#[cfg(any(test, feature = "host-tests"))]
struct GlobalIpcbuf(UnsafeCell<QsoeIpcbuf>);

#[cfg(any(test, feature = "host-tests"))]
unsafe impl Sync for GlobalIpcbuf {}

#[cfg(any(test, feature = "host-tests"))]
static HOST_SYSCFG: GlobalSyscfg = GlobalSyscfg(UnsafeCell::new(HostSyscfg::new()));

#[cfg(any(test, feature = "host-tests"))]
struct HostSyscfg {
    buf: [u8; 128],
    len: c_uint,
    ready: c_int,
}

#[cfg(any(test, feature = "host-tests"))]
impl HostSyscfg {
    const fn new() -> Self {
        Self {
            buf: [0; 128],
            len: 0,
            ready: -1,
        }
    }
}

#[cfg(any(test, feature = "host-tests"))]
struct GlobalSyscfg(UnsafeCell<HostSyscfg>);

#[cfg(any(test, feature = "host-tests"))]
unsafe impl Sync for GlobalSyscfg {}

#[cfg(not(any(test, feature = "host-tests")))]
#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    loop {
        core::hint::spin_loop();
    }
}

fn db_mut() -> *mut ResourceDb {
    DB.0.get()
}

unsafe fn copy_name(dst: &mut [u8; TM_RSRC_NAME_MAX], name: *const c_char) {
    if name.is_null() {
        return;
    }
    let mut i = 0usize;
    while i + 1 < TM_RSRC_NAME_MAX {
        let ch = *name.add(i) as u8;
        if ch == 0 {
            break;
        }
        dst[i] = ch;
        i += 1;
    }
}

unsafe fn read_le16(p: *const u8) -> u16 {
    u16::from(*p) | (u16::from(*p.add(1)) << 8)
}

unsafe fn read_le64(p: *const u8) -> u64 {
    let mut out = 0u64;
    let mut i = 8usize;
    while i > 0 {
        i -= 1;
        out = (out << 8) | u64::from(*p.add(i));
    }
    out
}

#[cfg(any(test, feature = "host-tests"))]
unsafe fn ipc_payload_ptr() -> *mut u8 {
    let ipc = HOST_IPCBUF.0.get();
    let msg = core::ptr::addr_of_mut!((*ipc).msg) as *mut c_ulong;
    msg.add(4) as *mut u8
}

#[cfg(all(not(any(test, feature = "host-tests")), target_arch = "riscv64"))]
unsafe fn ipc_payload_ptr() -> *mut u8 {
    let tcb: *mut QsoeTcbPrefix;
    core::arch::asm!("mv {}, tp", out(reg) tcb);
    if tcb.is_null() || (*tcb).ipcbuf.is_null() {
        return core::ptr::null_mut();
    }
    let msg = core::ptr::addr_of_mut!((*(*tcb).ipcbuf).msg) as *mut c_ulong;
    msg.add(4) as *mut u8
}

#[cfg(all(not(any(test, feature = "host-tests")), not(target_arch = "riscv64")))]
unsafe fn ipc_payload_ptr() -> *mut u8 {
    core::ptr::null_mut()
}

#[cfg(not(any(test, feature = "host-tests")))]
extern "C" {
    fn tm_syscfg_get(out_blob: *mut *const c_void, out_len: *mut c_uint) -> c_int;
}

#[cfg(any(test, feature = "host-tests"))]
/// Host-test shim for LQ `tm_syscfg_get`.
///
/// # Safety
///
/// Non-null output pointers must be valid for one pointer/length write.
#[no_mangle]
pub unsafe extern "C" fn tm_syscfg_get(
    out_blob: *mut *const c_void,
    out_len: *mut c_uint,
) -> c_int {
    let syscfg = &*HOST_SYSCFG.0.get();
    if syscfg.ready != 0 {
        return -1;
    }
    if !out_blob.is_null() {
        *out_blob = syscfg.buf.as_ptr().cast::<c_void>();
    }
    if !out_len.is_null() {
        *out_len = syscfg.len;
    }
    0
}

#[no_mangle]
pub extern "C" fn tm_rsrc_init() {
    unsafe {
        (*db_mut()).init();
    }
}

/// Create resource records from taskman's IPC payload.
///
/// # Safety
///
/// The current LQ thread must expose a valid IPC buffer through `tp`, and
/// `msg[4..]` must contain `count` contiguous `rsrc_alloc_t` records.
#[no_mangle]
pub unsafe extern "C" fn tm_rsrc_create(caller: PidT, count: c_uint) -> c_int {
    (*db_mut()).create(caller, count)
}

/// Destroy exact resource records described by taskman's IPC payload.
///
/// # Safety
///
/// The current LQ thread must expose a valid IPC buffer through `tp`, and
/// `msg[4..]` must contain `count` contiguous `rsrc_alloc_t` records.
#[no_mangle]
pub unsafe extern "C" fn tm_rsrc_destroy(_caller: PidT, count: c_uint) -> c_int {
    (*db_mut()).destroy(count)
}

/// Attach resources to `caller`, echoing granted ranges into the IPC payload.
///
/// # Safety
///
/// The current LQ thread must expose a valid IPC buffer through `tp`, and
/// `msg[4..]` must contain `count` contiguous `rsrc_request_t` records.
#[no_mangle]
pub unsafe extern "C" fn tm_rsrc_attach(caller: PidT, count: c_uint) -> c_int {
    (*db_mut()).attach(caller, count)
}

/// Detach resources from `caller` using request records in the IPC payload.
///
/// # Safety
///
/// The current LQ thread must expose a valid IPC buffer through `tp`, and
/// `msg[4..]` must contain `count` contiguous `rsrc_request_t` records.
#[no_mangle]
pub unsafe extern "C" fn tm_rsrc_detach(caller: PidT, count: c_uint) -> c_int {
    (*db_mut()).detach(caller, count)
}

/// Query resource records into taskman's IPC payload.
///
/// # Safety
///
/// The current LQ thread must expose a valid IPC buffer through `tp`.
/// `out_written`, when non-null, must be writable for one `unsigned`.
#[no_mangle]
pub unsafe extern "C" fn tm_rsrc_query(
    caller: PidT,
    listcnt: c_uint,
    start: c_uint,
    type_: u32,
    out_written: *mut c_uint,
) -> c_int {
    let _ = caller;
    (*db_mut()).query(listcnt, start, type_, out_written)
}

#[no_mangle]
pub extern "C" fn tm_rsrc_release_pid(pid: PidT) {
    unsafe {
        (*db_mut()).release_pid(pid);
    }
}

#[no_mangle]
pub extern "C" fn tm_rsrc_seed_from_syscfg() {
    unsafe {
        (*db_mut()).seed_from_syscfg();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::{align_of, offset_of, size_of};

    static TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    unsafe fn payload_allocs(count: usize) -> &'static mut [RsrcAlloc] {
        core::slice::from_raw_parts_mut(ipc_payload_ptr().cast::<RsrcAlloc>(), count)
    }

    unsafe fn payload_requests(count: usize) -> &'static mut [RsrcRequest] {
        core::slice::from_raw_parts_mut(ipc_payload_ptr().cast::<RsrcRequest>(), count)
    }

    unsafe fn clear_payload() {
        core::ptr::write_bytes(ipc_payload_ptr(), 0, 116 * size_of::<c_ulong>());
    }

    unsafe fn set_host_syscfg(bytes: &[u8]) {
        let syscfg = &mut *HOST_SYSCFG.0.get();
        syscfg.buf = [0; 128];
        let mut i = 0usize;
        while i < bytes.len() {
            syscfg.buf[i] = bytes[i];
            i += 1;
        }
        syscfg.len = bytes.len() as c_uint;
        syscfg.ready = 0;
    }

    #[test]
    fn c_abi_layouts_match_headers() {
        let _guard = TEST_LOCK.lock().unwrap();
        assert_eq!(size_of::<c_ulong>(), 8);
        assert_eq!(size_of::<RsrcAlloc>(), 32);
        assert_eq!(align_of::<RsrcAlloc>(), 8);
        assert_eq!(offset_of!(RsrcAlloc, start), 0);
        assert_eq!(offset_of!(RsrcAlloc, end), 8);
        assert_eq!(offset_of!(RsrcAlloc, flags), 16);
        assert_eq!(offset_of!(RsrcAlloc, name), 24);
        assert_eq!(size_of::<RsrcRequest>(), 56);
        assert_eq!(offset_of!(RsrcRequest, length), 0);
        assert_eq!(offset_of!(RsrcRequest, align), 8);
        assert_eq!(offset_of!(RsrcRequest, start), 16);
        assert_eq!(offset_of!(RsrcRequest, end), 24);
        assert_eq!(offset_of!(RsrcRequest, flags), 32);
        assert_eq!(offset_of!(RsrcRequest, zero), 36);
        assert_eq!(offset_of!(RsrcRequest, name), 48);
        assert_eq!(offset_of!(QsoeTcbPrefix, ipcbuf), 32);
    }

    #[test]
    fn create_query_attach_detach_and_merge() {
        let _guard = TEST_LOCK.lock().unwrap();
        unsafe {
            clear_payload();
            tm_rsrc_init();

            let allocs = payload_allocs(4);
            allocs[0] = RsrcAlloc {
                start: 100,
                end: 199,
                flags: u32::from(RSRCDBMGR_MEMORY),
                name: core::ptr::null(),
            };
            assert_eq!(tm_rsrc_create(7, 1), 0);

            let mut written = 99;
            assert_eq!(
                tm_rsrc_query(0, 4, 0, u32::from(RSRCDBMGR_MEMORY), &mut written),
                0
            );
            assert_eq!(written, 1);
            assert_eq!(payload_allocs(1)[0].start, 100);
            assert_eq!(payload_allocs(1)[0].end, 199);
            assert_eq!(payload_allocs(1)[0].flags, u32::from(RSRCDBMGR_MEMORY));

            let reqs = payload_requests(1);
            reqs[0] = RsrcRequest {
                length: 16,
                align: 16,
                start: 120,
                end: 180,
                flags: u32::from(RSRCDBMGR_MEMORY) | RSRCDBMGR_FLAG_RANGE | RSRCDBMGR_FLAG_ALIGN,
                zero: [0; 2],
                name: core::ptr::null(),
            };
            assert_eq!(tm_rsrc_attach(42, 1), 0);
            assert_eq!(payload_requests(1)[0].start, 128);
            assert_eq!(payload_requests(1)[0].end, 143);
            assert_eq!(payload_requests(1)[0].length, 16);

            assert_eq!(
                tm_rsrc_query(0, 4, 0, u32::from(RSRCDBMGR_MEMORY), &mut written),
                0
            );
            let rows = payload_allocs(3);
            assert_eq!(written, 3);
            assert_eq!((rows[0].start, rows[0].end, rows[0].flags), (100, 127, 0));
            assert_eq!(
                (rows[1].start, rows[1].end, rows[1].flags),
                (128, 143, RSRCDBMGR_FLAG_USED)
            );
            assert_eq!((rows[2].start, rows[2].end, rows[2].flags), (144, 199, 0));

            let reqs = payload_requests(1);
            reqs[0] = RsrcRequest {
                length: 16,
                align: 0,
                start: 128,
                end: 143,
                flags: u32::from(RSRCDBMGR_MEMORY),
                zero: [0; 2],
                name: core::ptr::null(),
            };
            assert_eq!(tm_rsrc_detach(42, 1), 0);

            assert_eq!(
                tm_rsrc_query(0, 4, 0, u32::from(RSRCDBMGR_MEMORY), &mut written),
                0
            );
            assert_eq!(written, 1);
            assert_eq!(payload_allocs(1)[0].start, 100);
            assert_eq!(payload_allocs(1)[0].end, 199);
        }
    }

    #[test]
    fn attach_rollback_keeps_prior_echo_but_frees_grant() {
        let _guard = TEST_LOCK.lock().unwrap();
        unsafe {
            clear_payload();
            tm_rsrc_init();
            let allocs = payload_allocs(1);
            allocs[0] = RsrcAlloc {
                start: 0,
                end: 9,
                flags: u32::from(RSRCDBMGR_MEMORY),
                name: core::ptr::null(),
            };
            assert_eq!(tm_rsrc_create(1, 1), 0);

            let reqs = payload_requests(2);
            reqs[0] = RsrcRequest {
                length: 4,
                align: 1,
                start: 0,
                end: 0,
                flags: u32::from(RSRCDBMGR_MEMORY),
                zero: [0; 2],
                name: core::ptr::null(),
            };
            reqs[1] = RsrcRequest {
                length: 100,
                align: 1,
                start: 0,
                end: 0,
                flags: u32::from(RSRCDBMGR_MEMORY),
                zero: [0; 2],
                name: core::ptr::null(),
            };
            assert_eq!(tm_rsrc_attach(22, 2), -ENOSPC);
            assert_eq!(payload_requests(2)[0].start, 0);
            assert_eq!(payload_requests(2)[0].end, 3);

            let mut written = 0;
            assert_eq!(
                tm_rsrc_query(0, 4, 0, u32::from(RSRCDBMGR_MEMORY), &mut written),
                0
            );
            assert_eq!(written, 1);
            assert_eq!(payload_allocs(1)[0].start, 0);
            assert_eq!(payload_allocs(1)[0].end, 9);
            assert_eq!(payload_allocs(1)[0].flags, 0);
        }
    }

    #[test]
    fn release_pid_frees_owned_entries_and_query_count_mode_counts_all() {
        let _guard = TEST_LOCK.lock().unwrap();
        unsafe {
            clear_payload();
            tm_rsrc_init();
            let allocs = payload_allocs(2);
            allocs[0] = RsrcAlloc {
                start: 0,
                end: 31,
                flags: u32::from(RSRCDBMGR_MEMORY),
                name: core::ptr::null(),
            };
            allocs[1] = RsrcAlloc {
                start: 100,
                end: 199,
                flags: u32::from(RSRCDBMGR_MEMORY),
                name: core::ptr::null(),
            };
            assert_eq!(tm_rsrc_create(1, 2), 0);

            let reqs = payload_requests(2);
            reqs[0] = RsrcRequest {
                length: 8,
                align: 1,
                start: 0,
                end: 0,
                flags: u32::from(RSRCDBMGR_MEMORY),
                zero: [0; 2],
                name: core::ptr::null(),
            };
            reqs[1] = RsrcRequest {
                length: 8,
                align: 1,
                start: 0,
                end: 0,
                flags: u32::from(RSRCDBMGR_MEMORY),
                zero: [0; 2],
                name: core::ptr::null(),
            };
            assert_eq!(tm_rsrc_attach(5, 2), 0);

            let reqs = payload_requests(1);
            reqs[0] = RsrcRequest {
                length: 8,
                align: 1,
                start: 0,
                end: 0,
                flags: u32::from(RSRCDBMGR_MEMORY),
                zero: [0; 2],
                name: core::ptr::null(),
            };
            assert_eq!(tm_rsrc_attach(6, 1), 0);
            tm_rsrc_release_pid(5);

            let mut written = 0;
            assert_eq!(
                tm_rsrc_query(0, 0, 0, u32::from(RSRCDBMGR_MEMORY), &mut written),
                0
            );
            assert_eq!(written, 4);

            assert_eq!(
                tm_rsrc_query(0, 8, 0, u32::from(RSRCDBMGR_MEMORY), &mut written),
                0
            );
            let rows = payload_allocs(4);
            assert_eq!(written, 4);
            assert_eq!((rows[0].start, rows[0].end, rows[0].flags), (0, 15, 0));
            assert_eq!(
                (rows[1].start, rows[1].end, rows[1].flags),
                (16, 23, RSRCDBMGR_FLAG_USED)
            );
            assert_eq!((rows[2].start, rows[2].end, rows[2].flags), (24, 31, 0));
            assert_eq!((rows[3].start, rows[3].end, rows[3].flags), (100, 199, 0));
        }
    }

    #[test]
    fn seed_from_syscfg_adds_memory_tags_without_merging() {
        let _guard = TEST_LOCK.lock().unwrap();
        unsafe {
            clear_payload();
            tm_rsrc_init();
            let mut blob = [0u8; 44];
            blob[0] = TM_SYSCFG_TAG_MEMORY as u8;
            blob[2] = 16;
            blob[4..12].copy_from_slice(&0x1000u64.to_le_bytes());
            blob[12..20].copy_from_slice(&0x100u64.to_le_bytes());
            blob[20] = TM_SYSCFG_TAG_MEMORY as u8;
            blob[22] = 16;
            blob[24..32].copy_from_slice(&0x1100u64.to_le_bytes());
            blob[32..40].copy_from_slice(&0x80u64.to_le_bytes());
            set_host_syscfg(&blob);

            tm_rsrc_seed_from_syscfg();
            let mut written = 0;
            assert_eq!(
                tm_rsrc_query(0, 8, 0, u32::from(RSRCDBMGR_MEMORY), &mut written),
                0
            );
            let rows = payload_allocs(2);
            assert_eq!(written, 2);
            assert_eq!((rows[0].start, rows[0].end), (0x1000, 0x10ff));
            assert_eq!((rows[1].start, rows[1].end), (0x1100, 0x117f));
        }
    }

    #[test]
    fn invalid_classes_and_null_out_written_match_c_errors() {
        let _guard = TEST_LOCK.lock().unwrap();
        unsafe {
            clear_payload();
            tm_rsrc_init();
            let allocs = payload_allocs(1);
            allocs[0] = RsrcAlloc {
                start: 0,
                end: 1,
                flags: 99,
                name: core::ptr::null(),
            };
            assert_eq!(tm_rsrc_create(1, 1), -EINVAL);

            let reqs = payload_requests(1);
            reqs[0] = RsrcRequest {
                length: 1,
                align: 1,
                start: 0,
                end: 0,
                flags: 99,
                zero: [0; 2],
                name: core::ptr::null(),
            };
            assert_eq!(tm_rsrc_attach(1, 1), -ENOSPC);
            assert_eq!(tm_rsrc_attach(1, 17), -EINVAL);
            assert_eq!(
                tm_rsrc_query(0, 1, 0, u32::from(RSRCDBMGR_MEMORY), core::ptr::null_mut()),
                -EINVAL
            );
        }
    }
}
