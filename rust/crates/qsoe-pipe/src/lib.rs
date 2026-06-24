#![no_std]

pub const PIPE_POOL_SIZE: usize = 16;
pub const PIPE_BUF_BYTES: usize = 4096;
pub const PIPE_IO_MAX: usize = 896;

const PIPE_DIR_BIT: u64 = 0x1;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Direction {
    Read,
    Write,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PipeStatus {
    Ok,
    BadFd,
    Again,
    TooManyFiles,
    BrokenPipe,
    Unsupported,
}

impl PipeStatus {
    pub const fn errno(self) -> i32 {
        match self {
            Self::Ok => 0,
            Self::BadFd => 9,
            Self::Again => 11,
            Self::TooManyFiles => 23,
            Self::BrokenPipe => 30,
            Self::Unsupported => 37,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PipeReply {
    Empty {
        rcvid: i32,
        status: PipeStatus,
    },
    Word {
        rcvid: i32,
        status: PipeStatus,
        value: u64,
    },
    ReadPayload {
        rcvid: i32,
        status: PipeStatus,
        len: usize,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PipeReplies {
    entries: [Option<PipeReply>; 3],
    len: usize,
}

impl PipeReplies {
    pub const fn new() -> Self {
        Self {
            entries: [None, None, None],
            len: 0,
        }
    }

    pub fn single(reply: PipeReply) -> Self {
        let mut replies = Self::new();
        replies.push(reply);
        replies
    }

    pub const fn len(&self) -> usize {
        self.len
    }

    pub const fn is_empty(&self) -> bool {
        self.len == 0
    }

    pub fn entries(&self) -> &[Option<PipeReply>; 3] {
        &self.entries
    }

    fn push(&mut self, reply: PipeReply) {
        debug_assert!(self.len < self.entries.len());
        if self.len < self.entries.len() {
            self.entries[self.len] = Some(reply);
            self.len += 1;
        }
    }
}

impl Default for PipeReplies {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Clone, Copy)]
struct ParkedReader {
    rcvid: i32,
    want: usize,
}

#[derive(Clone, Copy)]
struct ParkedWriter {
    rcvid: i32,
    buf: [u8; PIPE_IO_MAX],
    offset: usize,
    left: usize,
}

impl ParkedWriter {
    fn new(rcvid: i32, data: &[u8]) -> Self {
        let mut buf = [0; PIPE_IO_MAX];
        let len = core::cmp::min(data.len(), PIPE_IO_MAX);
        buf[..len].copy_from_slice(&data[..len]);
        Self {
            rcvid,
            buf,
            offset: 0,
            left: len,
        }
    }

    fn remaining(&self) -> &[u8] {
        &self.buf[self.offset..self.offset + self.left]
    }

    fn advance(&mut self, n: usize) {
        self.offset += n;
        self.left -= n;
    }
}

#[derive(Clone, Copy)]
struct PipeSlot {
    in_use: bool,
    unique_id: u32,
    reader_count: u32,
    writer_count: u32,
    head: usize,
    tail: usize,
    buf: [u8; PIPE_BUF_BYTES],
    parked_reader: Option<ParkedReader>,
    parked_writer: Option<ParkedWriter>,
}

impl PipeSlot {
    const fn new() -> Self {
        Self {
            in_use: false,
            unique_id: 0,
            reader_count: 0,
            writer_count: 0,
            head: 0,
            tail: 0,
            buf: [0; PIPE_BUF_BYTES],
            parked_reader: None,
            parked_writer: None,
        }
    }

    fn reset(&mut self) {
        *self = Self::new();
    }

    fn allocate(&mut self, unique_id: u32) {
        self.in_use = true;
        self.unique_id = unique_id;
        self.reader_count = 1;
        self.writer_count = 1;
        self.head = 0;
        self.tail = 0;
        self.parked_reader = None;
        self.parked_writer = None;
    }

    fn count(&self) -> usize {
        (self.tail + PIPE_BUF_BYTES - self.head) % PIPE_BUF_BYTES
    }

    fn space(&self) -> usize {
        (PIPE_BUF_BYTES - 1) - self.count()
    }

    fn drain(&mut self, dst: &mut [u8]) -> usize {
        let n = core::cmp::min(dst.len(), self.count());
        for out in dst.iter_mut().take(n) {
            *out = self.buf[self.head];
            self.head = (self.head + 1) % PIPE_BUF_BYTES;
        }
        n
    }

    fn fill(&mut self, src: &[u8]) -> usize {
        let n = core::cmp::min(src.len(), self.space());
        for byte in src.iter().take(n) {
            self.buf[self.tail] = *byte;
            self.tail = (self.tail + 1) % PIPE_BUF_BYTES;
        }
        n
    }
}

pub struct PipeManager {
    pipes: [PipeSlot; PIPE_POOL_SIZE],
    reply_data: [u8; PIPE_IO_MAX],
}

impl PipeManager {
    pub const fn new() -> Self {
        Self {
            pipes: [PipeSlot::new(); PIPE_POOL_SIZE],
            reply_data: [0; PIPE_IO_MAX],
        }
    }

    pub fn reply_payload(&self, len: usize) -> &[u8] {
        &self.reply_data[..core::cmp::min(len, PIPE_IO_MAX)]
    }

    pub fn handle_read(&mut self, badge: u64, want: usize, rcvid: i32) -> PipeReplies {
        let (uid, direction) = decode_badge(badge);
        if direction != Direction::Read {
            return PipeReplies::single(PipeReply::Empty {
                rcvid,
                status: PipeStatus::BadFd,
            });
        }

        let idx = match self.find_or_alloc_index(uid) {
            Some(idx) => idx,
            None => {
                return PipeReplies::single(PipeReply::Empty {
                    rcvid,
                    status: PipeStatus::TooManyFiles,
                });
            }
        };

        let want = core::cmp::min(want, PIPE_IO_MAX);
        let mut replies = PipeReplies::new();
        let (pipes, reply_data) = (&mut self.pipes, &mut self.reply_data);
        let pipe = &mut pipes[idx];

        if pipe.count() > 0 {
            let got = pipe.drain(&mut reply_data[..want]);
            if pipe.parked_writer.is_some() && pipe.space() > 0 {
                if let Some(reply) = resume_parked_writer(pipe) {
                    replies.push(reply);
                }
            }
            replies.push(PipeReply::ReadPayload {
                rcvid,
                status: PipeStatus::Ok,
                len: got,
            });
            return replies;
        }

        if pipe.writer_count == 0 {
            replies.push(PipeReply::ReadPayload {
                rcvid,
                status: PipeStatus::Ok,
                len: 0,
            });
            return replies;
        }

        if pipe.parked_reader.is_some() {
            replies.push(PipeReply::Empty {
                rcvid,
                status: PipeStatus::Again,
            });
            return replies;
        }

        pipe.parked_reader = Some(ParkedReader { rcvid, want });
        replies
    }

    pub fn handle_write(&mut self, badge: u64, data: &[u8], rcvid: i32) -> PipeReplies {
        let (uid, direction) = decode_badge(badge);
        if direction != Direction::Write {
            return PipeReplies::single(PipeReply::Empty {
                rcvid,
                status: PipeStatus::BadFd,
            });
        }

        let idx = match self.find_or_alloc_index(uid) {
            Some(idx) => idx,
            None => {
                return PipeReplies::single(PipeReply::Empty {
                    rcvid,
                    status: PipeStatus::TooManyFiles,
                });
            }
        };

        let data = &data[..core::cmp::min(data.len(), PIPE_IO_MAX)];
        let mut accepted = 0;
        let mut replies = PipeReplies::new();
        let (pipes, reply_data) = (&mut self.pipes, &mut self.reply_data);
        let pipe = &mut pipes[idx];

        if pipe.reader_count == 0 {
            replies.push(PipeReply::Empty {
                rcvid,
                status: PipeStatus::BrokenPipe,
            });
            return replies;
        }

        if let Some(reader) = pipe.parked_reader.take() {
            let give = core::cmp::min(data.len(), reader.want);
            reply_data[..give].copy_from_slice(&data[..give]);
            accepted += give;
            replies.push(PipeReply::ReadPayload {
                rcvid: reader.rcvid,
                status: PipeStatus::Ok,
                len: give,
            });
        }

        let remaining = &data[accepted..];
        let put = pipe.fill(remaining);
        accepted += put;

        if accepted == data.len() {
            replies.push(PipeReply::Word {
                rcvid,
                status: PipeStatus::Ok,
                value: accepted as u64,
            });
            return replies;
        }

        if pipe.parked_writer.is_some() {
            replies.push(PipeReply::Word {
                rcvid,
                status: PipeStatus::Ok,
                value: accepted as u64,
            });
            return replies;
        }

        pipe.parked_writer = Some(ParkedWriter::new(rcvid, &data[accepted..]));
        replies
    }

    pub fn handle_close(&mut self, badge: u64, rcvid: i32) -> PipeReplies {
        let (uid, direction) = decode_badge(badge);
        let idx = match self.find_or_alloc_index(uid) {
            Some(idx) => idx,
            None => {
                return PipeReplies::single(PipeReply::Empty {
                    rcvid,
                    status: PipeStatus::TooManyFiles,
                });
            }
        };

        let mut replies = PipeReplies::new();
        let pipe = &mut self.pipes[idx];

        match direction {
            Direction::Read => {
                if pipe.reader_count > 0 {
                    pipe.reader_count -= 1;
                }
            }
            Direction::Write => {
                if pipe.writer_count > 0 {
                    pipe.writer_count -= 1;
                }
            }
        }

        if pipe.writer_count == 0 {
            if let Some(reader) = pipe.parked_reader.take() {
                replies.push(PipeReply::Word {
                    rcvid: reader.rcvid,
                    status: PipeStatus::Ok,
                    value: 0,
                });
            }
        }

        if pipe.reader_count == 0 {
            if let Some(writer) = pipe.parked_writer.take() {
                replies.push(PipeReply::Empty {
                    rcvid: writer.rcvid,
                    status: PipeStatus::BrokenPipe,
                });
            }
        }

        if pipe.reader_count == 0 && pipe.writer_count == 0 {
            pipe.reset();
        }

        replies.push(PipeReply::Empty {
            rcvid,
            status: PipeStatus::Ok,
        });
        replies
    }

    fn find_or_alloc_index(&mut self, uid: u32) -> Option<usize> {
        let mut free = None;
        for (idx, pipe) in self.pipes.iter().enumerate() {
            if pipe.in_use && pipe.unique_id == uid {
                return Some(idx);
            }
            if !pipe.in_use && free.is_none() {
                free = Some(idx);
            }
        }

        let idx = free?;
        self.pipes[idx].allocate(uid);
        Some(idx)
    }
}

impl Default for PipeManager {
    fn default() -> Self {
        Self::new()
    }
}

pub fn decode_badge(badge: u64) -> (u32, Direction) {
    let uid = (badge >> 1) as u32;
    let direction = if badge & PIPE_DIR_BIT == 0 {
        Direction::Read
    } else {
        Direction::Write
    };
    (uid, direction)
}

fn resume_parked_writer(pipe: &mut PipeSlot) -> Option<PipeReply> {
    let mut writer = pipe.parked_writer.take()?;
    let moved = pipe.fill(writer.remaining());
    writer.advance(moved);
    if writer.left == 0 {
        Some(PipeReply::Empty {
            rcvid: writer.rcvid,
            status: PipeStatus::Ok,
        })
    } else {
        pipe.parked_writer = Some(writer);
        None
    }
}

#[cfg(test)]
mod tests {
    extern crate std;

    use super::*;
    use std::vec::Vec;

    fn badge(uid: u64, direction: Direction) -> u64 {
        (uid << 1)
            | match direction {
                Direction::Read => 0,
                Direction::Write => 1,
            }
    }

    fn replies_vec(replies: &PipeReplies) -> Vec<PipeReply> {
        replies.entries().iter().flatten().copied().collect()
    }

    fn read_payload(manager: &PipeManager, reply: PipeReply) -> &[u8] {
        match reply {
            PipeReply::ReadPayload { len, .. } => manager.reply_payload(len),
            _ => panic!("expected read payload"),
        }
    }

    #[test]
    fn decodes_badge_direction_and_id() {
        assert_eq!(decode_badge(84), (42, Direction::Read));
        assert_eq!(decode_badge(85), (42, Direction::Write));
    }

    #[test]
    fn write_then_read_round_trips_bytes() {
        let mut manager = PipeManager::new();
        let write = manager.handle_write(badge(7, Direction::Write), b"pipe", 10);
        assert_eq!(
            replies_vec(&write),
            [PipeReply::Word {
                rcvid: 10,
                status: PipeStatus::Ok,
                value: 4
            }]
        );

        let read = manager.handle_read(badge(7, Direction::Read), 8, 11);
        let entries = replies_vec(&read);
        assert_eq!(
            entries,
            [PipeReply::ReadPayload {
                rcvid: 11,
                status: PipeStatus::Ok,
                len: 4
            }]
        );
        assert_eq!(read_payload(&manager, entries[0]), b"pipe");
    }

    #[test]
    fn wrong_end_operations_fail_with_badfd() {
        let mut manager = PipeManager::new();
        assert_eq!(
            replies_vec(&manager.handle_read(badge(1, Direction::Write), 1, 1)),
            [PipeReply::Empty {
                rcvid: 1,
                status: PipeStatus::BadFd
            }]
        );
        assert_eq!(
            replies_vec(&manager.handle_write(badge(1, Direction::Read), b"x", 2)),
            [PipeReply::Empty {
                rcvid: 2,
                status: PipeStatus::BadFd
            }]
        );
    }

    #[test]
    fn empty_read_parks_until_writer_arrives() {
        let mut manager = PipeManager::new();
        assert!(manager
            .handle_read(badge(2, Direction::Read), PIPE_IO_MAX, 20)
            .is_empty());

        let replies = manager.handle_write(badge(2, Direction::Write), b"ready", 21);
        let entries = replies_vec(&replies);
        assert_eq!(
            entries,
            [
                PipeReply::ReadPayload {
                    rcvid: 20,
                    status: PipeStatus::Ok,
                    len: 5
                },
                PipeReply::Word {
                    rcvid: 21,
                    status: PipeStatus::Ok,
                    value: 5
                }
            ]
        );
        assert_eq!(read_payload(&manager, entries[0]), b"ready");
    }

    #[test]
    fn second_empty_reader_gets_eagain() {
        let mut manager = PipeManager::new();
        assert!(manager
            .handle_read(badge(3, Direction::Read), 1, 30)
            .is_empty());
        assert_eq!(
            replies_vec(&manager.handle_read(badge(3, Direction::Read), 1, 31)),
            [PipeReply::Empty {
                rcvid: 31,
                status: PipeStatus::Again
            }]
        );
    }

    #[test]
    fn ring_wrap_preserves_byte_order() {
        let mut manager = PipeManager::new();
        let chunk = [b'a'; PIPE_IO_MAX];
        for rcvid in 0..4 {
            assert_eq!(
                replies_vec(&manager.handle_write(badge(4, Direction::Write), &chunk, rcvid)),
                [PipeReply::Word {
                    rcvid,
                    status: PipeStatus::Ok,
                    value: PIPE_IO_MAX as u64
                }]
            );
        }

        for _ in 0..3 {
            let entries = replies_vec(&manager.handle_read(badge(4, Direction::Read), 512, 40));
            assert_eq!(
                entries,
                [PipeReply::ReadPayload {
                    rcvid: 40,
                    status: PipeStatus::Ok,
                    len: 512
                }]
            );
            assert_eq!(read_payload(&manager, entries[0]), &[b'a'; 512]);
        }

        let wrap = [b'b'; 700];
        assert_eq!(
            replies_vec(&manager.handle_write(badge(4, Direction::Write), &wrap, 41)),
            [PipeReply::Word {
                rcvid: 41,
                status: PipeStatus::Ok,
                value: 700
            }]
        );

        let mut out = Vec::new();
        for rcvid in 50..58 {
            let entries = replies_vec(&manager.handle_read(badge(4, Direction::Read), 896, rcvid));
            let Some(reply) = entries.first().copied() else {
                break;
            };
            let PipeReply::ReadPayload { len, .. } = reply else {
                break;
            };
            if len == 0 {
                break;
            }
            out.extend_from_slice(read_payload(&manager, reply));
        }
        assert!(out.ends_with(&wrap[..]));
    }

    #[test]
    fn full_pipe_parks_writer_and_read_resumes_it() {
        let mut manager = PipeManager::new();
        let chunk = [0x55; PIPE_IO_MAX];
        for rcvid in 60..64 {
            let replies = manager.handle_write(badge(5, Direction::Write), &chunk, rcvid);
            assert_eq!(replies.len(), 1);
        }

        let parked = manager.handle_write(badge(5, Direction::Write), &chunk, 64);
        assert!(parked.is_empty());

        let read = manager.handle_read(badge(5, Direction::Read), PIPE_IO_MAX, 65);
        let entries = replies_vec(&read);
        assert_eq!(
            entries,
            [
                PipeReply::Empty {
                    rcvid: 64,
                    status: PipeStatus::Ok
                },
                PipeReply::ReadPayload {
                    rcvid: 65,
                    status: PipeStatus::Ok,
                    len: PIPE_IO_MAX
                }
            ]
        );
    }

    #[test]
    fn write_close_wakes_parked_reader_with_zero_word() {
        let mut manager = PipeManager::new();
        assert!(manager
            .handle_read(badge(6, Direction::Read), 16, 70)
            .is_empty());

        assert_eq!(
            replies_vec(&manager.handle_close(badge(6, Direction::Write), 71)),
            [
                PipeReply::Word {
                    rcvid: 70,
                    status: PipeStatus::Ok,
                    value: 0
                },
                PipeReply::Empty {
                    rcvid: 71,
                    status: PipeStatus::Ok
                }
            ]
        );
    }

    #[test]
    fn read_close_wakes_parked_writer_with_epipe() {
        let mut manager = PipeManager::new();
        let chunk = [0x33; PIPE_IO_MAX];
        for rcvid in 80..84 {
            let _ = manager.handle_write(badge(8, Direction::Write), &chunk, rcvid);
        }
        assert!(manager
            .handle_write(badge(8, Direction::Write), &chunk, 84)
            .is_empty());

        assert_eq!(
            replies_vec(&manager.handle_close(badge(8, Direction::Read), 85)),
            [
                PipeReply::Empty {
                    rcvid: 84,
                    status: PipeStatus::BrokenPipe
                },
                PipeReply::Empty {
                    rcvid: 85,
                    status: PipeStatus::Ok
                }
            ]
        );
    }

    #[test]
    fn closed_writer_makes_empty_read_eof() {
        let mut manager = PipeManager::new();
        let _ = manager.handle_close(badge(9, Direction::Write), 90);
        let read = manager.handle_read(badge(9, Direction::Read), 16, 91);
        assert_eq!(
            replies_vec(&read),
            [PipeReply::ReadPayload {
                rcvid: 91,
                status: PipeStatus::Ok,
                len: 0
            }]
        );
    }

    #[test]
    fn pool_exhaustion_returns_emfile() {
        let mut manager = PipeManager::new();
        for uid in 0..PIPE_POOL_SIZE as u64 {
            let replies = manager.handle_write(badge(uid, Direction::Write), b"x", uid as i32);
            assert_eq!(replies.len(), 1);
        }

        assert_eq!(
            replies_vec(&manager.handle_write(
                badge(PIPE_POOL_SIZE as u64 + 1, Direction::Write),
                b"x",
                200
            )),
            [PipeReply::Empty {
                rcvid: 200,
                status: PipeStatus::TooManyFiles
            }]
        );
    }
}
