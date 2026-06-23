#![no_std]

pub const SLOG_RING_BYTES: usize = 64 * 1024;
pub const SLOG_EVENT_HEADER_BYTES: usize = 24;
pub const QSOE_SLOG_MAGIC: u16 = 0x534c;
pub const QSOE_SLOG_FLAG_TEXT: u8 = 0x01;
pub const QSOE_SLOG_MAX_PAYLOAD: usize = 240;

pub type SlogRing = Ring<SLOG_RING_BYTES>;

pub struct Ring<const N: usize> {
    buf: [u8; N],
    head: usize,
    tail: usize,
    used: usize,
}

impl<const N: usize> Ring<N> {
    pub const fn new() -> Self {
        Self {
            buf: [0; N],
            head: 0,
            tail: 0,
            used: 0,
        }
    }

    pub const fn capacity(&self) -> usize {
        N
    }

    pub const fn len(&self) -> usize {
        self.used
    }

    pub const fn is_empty(&self) -> bool {
        self.used == 0
    }

    pub fn clear(&mut self) {
        self.head = 0;
        self.tail = 0;
        self.used = 0;
    }

    pub fn append(&mut self, src: &[u8]) -> bool {
        if src.len() > N {
            return false;
        }
        if src.is_empty() {
            return true;
        }
        if N == 0 {
            return false;
        }

        while self.used + src.len() > N {
            if !self.evict_one() {
                self.clear();
                break;
            }
        }

        for (i, byte) in src.iter().copied().enumerate() {
            self.buf[(self.tail + i) % N] = byte;
        }
        self.tail = (self.tail + src.len()) % N;
        self.used += src.len();
        true
    }

    pub fn drain(&mut self, dst: &mut [u8]) -> usize {
        if N == 0 {
            return 0;
        }

        let mut written = 0;
        while self.used >= SLOG_EVENT_HEADER_BYTES {
            let event_size = match self.next_event_size() {
                Some(size) if size <= self.used => size,
                _ => break,
            };

            if written + event_size > dst.len() {
                break;
            }

            self.copy_from_ring(0, &mut dst[written..written + event_size]);
            self.drop_bytes(event_size);
            written += event_size;
        }

        written
    }

    fn evict_one(&mut self) -> bool {
        if self.used == 0 {
            return false;
        }
        if self.used < SLOG_EVENT_HEADER_BYTES {
            self.clear();
            return true;
        }

        let event_size = self.next_event_size().unwrap_or(self.used).min(self.used);
        self.drop_bytes(event_size);
        true
    }

    fn next_event_size(&self) -> Option<usize> {
        if self.used < SLOG_EVENT_HEADER_BYTES {
            return None;
        }

        let mut header = [0u8; SLOG_EVENT_HEADER_BYTES];
        self.copy_from_ring(0, &mut header);
        let paylen = u16::from_le_bytes([header[18], header[19]]) as usize;
        Some(SLOG_EVENT_HEADER_BYTES + paylen)
    }

    fn copy_from_ring(&self, offset: usize, dst: &mut [u8]) {
        for (i, out) in dst.iter_mut().enumerate() {
            *out = self.buf[(self.head + offset + i) % N];
        }
    }

    fn drop_bytes(&mut self, bytes: usize) {
        if bytes >= self.used {
            self.clear();
            return;
        }

        self.head = (self.head + bytes) % N;
        self.used -= bytes;
    }
}

impl<const N: usize> Default for Ring<N> {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
extern crate std;

#[cfg(test)]
mod tests {
    use super::*;
    use std::vec;
    use std::vec::Vec;

    fn event(code: u32, payload: &[u8]) -> Vec<u8> {
        let mut out = vec![0u8; SLOG_EVENT_HEADER_BYTES + payload.len()];
        out[0..2].copy_from_slice(&QSOE_SLOG_MAGIC.to_le_bytes());
        out[2] = 5;
        out[3] = QSOE_SLOG_FLAG_TEXT;
        out[4..8].copy_from_slice(&code.to_le_bytes());
        out[8..16].copy_from_slice(&(u64::from(code) * 100).to_le_bytes());
        out[16..18].copy_from_slice(&(code as u16).to_le_bytes());
        out[18..20].copy_from_slice(&(payload.len() as u16).to_le_bytes());
        out[SLOG_EVENT_HEADER_BYTES..].copy_from_slice(payload);
        out
    }

    #[test]
    fn appends_and_drains_one_event() {
        let e = event(1, b"hello");
        let mut ring = Ring::<128>::new();
        let mut out = [0u8; 128];

        assert!(ring.append(&e));
        assert_eq!(ring.len(), e.len());
        let n = ring.drain(&mut out);

        assert_eq!(n, e.len());
        assert_eq!(&out[..n], e.as_slice());
        assert!(ring.is_empty());
    }

    #[test]
    fn drains_only_whole_events_that_fit_the_read_cap() {
        let e = event(1, b"hello");
        let mut ring = Ring::<128>::new();
        let mut short = [0u8; SLOG_EVENT_HEADER_BYTES - 1];
        let mut out = [0u8; 128];

        assert!(ring.append(&e));
        assert_eq!(ring.drain(&mut short), 0);
        assert_eq!(ring.len(), e.len());

        let n = ring.drain(&mut out);
        assert_eq!(&out[..n], e.as_slice());
        assert!(ring.is_empty());
    }

    #[test]
    fn wraps_tail_without_splitting_events_for_readers() {
        let first = event(1, b"aaaaaaaaaa");
        let second = event(2, b"bbbbbbbbbb");
        let third = event(3, b"cccccccccc");
        let mut ring = Ring::<80>::new();
        let mut one = [0u8; 64];
        let mut out = [0u8; 128];

        assert!(ring.append(&first));
        assert!(ring.append(&second));
        assert_eq!(ring.drain(&mut one[..first.len()]), first.len());
        assert!(ring.append(&third));

        let n = ring.drain(&mut out);
        assert_eq!(n, second.len() + third.len());
        assert_eq!(&out[..second.len()], second.as_slice());
        assert_eq!(&out[second.len()..n], third.as_slice());
    }

    #[test]
    fn evicts_oldest_whole_events_when_full() {
        let first = event(1, b"aaaaaaaaaa");
        let second = event(2, b"bbbbbbbbbb");
        let third = event(3, b"cccccccccc");
        let mut ring = Ring::<80>::new();
        let mut out = [0u8; 128];

        assert!(ring.append(&first));
        assert!(ring.append(&second));
        assert!(ring.append(&third));

        let n = ring.drain(&mut out);
        assert_eq!(n, second.len() + third.len());
        assert_eq!(&out[..second.len()], second.as_slice());
        assert_eq!(&out[second.len()..n], third.as_slice());
    }

    #[test]
    fn can_fill_the_ring_exactly() {
        let first = event(1, b"");
        let second = event(2, b"");
        let mut ring = Ring::<{ SLOG_EVENT_HEADER_BYTES * 2 }>::new();
        let mut out = [0u8; SLOG_EVENT_HEADER_BYTES * 2];

        assert!(ring.append(&first));
        assert!(ring.append(&second));
        assert_eq!(ring.len(), ring.capacity());

        let n = ring.drain(&mut out);
        assert_eq!(n, first.len() + second.len());
        assert!(ring.is_empty());
    }

    #[test]
    fn rejects_records_larger_than_the_ring() {
        let oversized = event(1, &[0xaa; QSOE_SLOG_MAX_PAYLOAD]);
        let mut ring = Ring::<32>::new();

        assert!(!ring.append(&oversized));
        assert!(ring.is_empty());
    }

    #[test]
    fn empty_or_incomplete_ring_drain_returns_zero() {
        let mut ring = Ring::<64>::new();
        let mut out = [0u8; 64];

        assert_eq!(ring.drain(&mut out), 0);
        assert!(ring.append(&[1, 2, 3]));
        assert_eq!(ring.drain(&mut out), 0);
        assert_eq!(ring.len(), 3);
    }

    #[test]
    fn corrupt_oversized_head_event_is_clamped_during_eviction() {
        let mut corrupt = [0u8; SLOG_EVENT_HEADER_BYTES];
        corrupt[18..20].copy_from_slice(&500u16.to_le_bytes());
        let valid = event(2, b"ok");
        let mut ring = Ring::<48>::new();
        let mut out = [0u8; 64];

        assert!(ring.append(&corrupt));
        assert!(ring.append(&valid));

        let n = ring.drain(&mut out);
        assert_eq!(&out[..n], valid.as_slice());
    }
}
