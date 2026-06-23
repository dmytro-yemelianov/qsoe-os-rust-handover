#![no_std]

use core::fmt;
use core::str;

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum Error {
    Truncated {
        offset: usize,
        len: usize,
    },
    BadSysmapMagic {
        found: u32,
    },
    UnsupportedSysmapVersion {
        found: u16,
    },
    InvalidSysmapHeader {
        hdr_bytes: u16,
        total_bytes: u32,
    },
    MissingEndTag,
    UnexpectedLen {
        context: &'static str,
        expected: usize,
        actual: usize,
    },
    UnterminatedString {
        context: &'static str,
    },
    InvalidUtf8 {
        context: &'static str,
    },
    ArithmeticOverflow,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Truncated { offset, len } => {
                write!(
                    f,
                    "truncated sysview blob at offset {offset}, need {len} bytes"
                )
            }
            Self::BadSysmapMagic { found } => {
                write!(f, "bad sysmap magic 0x{found:08x}")
            }
            Self::UnsupportedSysmapVersion { found } => {
                write!(f, "unsupported sysmap version {found}")
            }
            Self::InvalidSysmapHeader {
                hdr_bytes,
                total_bytes,
            } => {
                write!(
                    f,
                    "invalid sysmap header: hdr_bytes={hdr_bytes}, total_bytes={total_bytes}"
                )
            }
            Self::MissingEndTag => write!(f, "missing sysview END tag"),
            Self::UnexpectedLen {
                context,
                expected,
                actual,
            } => {
                write!(
                    f,
                    "{context} has length {actual}, expected {expected} bytes"
                )
            }
            Self::UnterminatedString { context } => {
                write!(f, "{context} is not NUL terminated")
            }
            Self::InvalidUtf8 { context } => write!(f, "{context} is not UTF-8"),
            Self::ArithmeticOverflow => write!(f, "sysview offset arithmetic overflow"),
        }
    }
}

pub type Result<T> = core::result::Result<T, Error>;

pub mod syscfg {
    use super::{read_at, read_cstr, read_u16_at, read_u32_field, read_u64_field, Error, Result};

    pub const TAG_END: u16 = 0;
    pub const TAG_VERSION: u16 = 1;
    pub const TAG_MODEL: u16 = 2;
    pub const TAG_COMPATIBLE: u16 = 3;
    pub const TAG_TIMEBASE_HZ: u16 = 4;
    pub const TAG_NUM_CPUS: u16 = 5;
    pub const TAG_BOOT_HART: u16 = 6;
    pub const TAG_MEMORY: u16 = 7;
    pub const TAG_PCI_ECAM: u16 = 8;
    pub const TAG_PCI_IRQ: u16 = 9;
    pub const TAG_PCI_WINDOW: u16 = 10;
    pub const TAG_DW_MSI: u16 = 11;
    pub const TAG_UART: u16 = 12;
    pub const TAG_CMDLINE: u16 = 13;
    pub const VERSION: u32 = 1;
    pub const HEADER_LEN: usize = 4;

    #[derive(Debug, Clone, Copy, Eq, PartialEq)]
    pub struct Tag<'a> {
        pub id: u16,
        pub payload: &'a [u8],
        pub offset: usize,
        pub next_offset: usize,
    }

    #[derive(Debug, Clone, Copy)]
    pub struct Blob<'a> {
        bytes: &'a [u8],
    }

    impl<'a> Blob<'a> {
        pub fn parse(bytes: &'a [u8]) -> Result<Self> {
            let blob = Self { bytes };
            blob.validate()?;
            Ok(blob)
        }

        pub fn tags(&self) -> Tags<'a> {
            Tags {
                bytes: self.bytes,
                offset: 0,
                finished: false,
                saw_end: false,
            }
        }

        pub fn find(&self, id: u16) -> Result<Option<Tag<'a>>> {
            for tag in self.tags() {
                let tag = tag?;
                if tag.id == id {
                    return Ok(Some(tag));
                }
            }
            Ok(None)
        }

        pub fn find_u32(&self, id: u16) -> Result<Option<u32>> {
            self.find(id)?
                .map(|tag| tag.u32("syscfg u32 tag"))
                .transpose()
        }

        pub fn find_u64(&self, id: u16) -> Result<Option<u64>> {
            self.find(id)?
                .map(|tag| tag.u64("syscfg u64 tag"))
                .transpose()
        }

        pub fn find_cstr(&self, id: u16, context: &'static str) -> Result<Option<&'a str>> {
            self.find(id)?.map(|tag| tag.cstr(context)).transpose()
        }

        fn validate(&self) -> Result<()> {
            let mut tags = self.tags();
            for tag in tags.by_ref() {
                tag?;
            }
            if tags.saw_end {
                Ok(())
            } else {
                Err(Error::MissingEndTag)
            }
        }
    }

    impl<'a> Tag<'a> {
        pub fn u32(&self, context: &'static str) -> Result<u32> {
            if self.payload.len() != 4 {
                return Err(Error::UnexpectedLen {
                    context,
                    expected: 4,
                    actual: self.payload.len(),
                });
            }
            read_u32_field(self.payload, 0, context)
        }

        pub fn u64(&self, context: &'static str) -> Result<u64> {
            if self.payload.len() != 8 {
                return Err(Error::UnexpectedLen {
                    context,
                    expected: 8,
                    actual: self.payload.len(),
                });
            }
            read_u64_field(self.payload, 0, context)
        }

        pub fn cstr(&self, context: &'static str) -> Result<&'a str> {
            read_cstr(self.payload, context)
        }
    }

    pub struct Tags<'a> {
        bytes: &'a [u8],
        offset: usize,
        finished: bool,
        saw_end: bool,
    }

    impl<'a> Iterator for Tags<'a> {
        type Item = Result<Tag<'a>>;

        fn next(&mut self) -> Option<Self::Item> {
            if self.finished {
                return None;
            }

            match parse_tag_at(self.bytes, self.offset) {
                Ok(Some(tag)) => {
                    self.offset = tag.next_offset;
                    Some(Ok(tag))
                }
                Ok(None) => {
                    self.finished = true;
                    self.saw_end = true;
                    None
                }
                Err(err) => {
                    self.finished = true;
                    Some(Err(err))
                }
            }
        }
    }

    fn parse_tag_at(bytes: &[u8], offset: usize) -> Result<Option<Tag<'_>>> {
        if offset >= bytes.len() {
            return Err(Error::MissingEndTag);
        }

        let header = read_at(bytes, offset, HEADER_LEN)?;
        let id = read_u16_at(header, 0)?;
        let len = read_u16_at(header, 2)? as usize;
        if id == TAG_END {
            if len != 0 {
                return Err(Error::UnexpectedLen {
                    context: "syscfg END",
                    expected: 0,
                    actual: len,
                });
            }
            return Ok(None);
        }

        let payload_offset = offset
            .checked_add(HEADER_LEN)
            .ok_or(Error::ArithmeticOverflow)?;
        let payload = read_at(bytes, payload_offset, len)?;
        let next_offset = payload_offset
            .checked_add(len)
            .ok_or(Error::ArithmeticOverflow)?;

        Ok(Some(Tag {
            id,
            payload,
            offset,
            next_offset,
        }))
    }
}

pub mod sysmap {
    use super::{
        align_up, read_at, read_cstr, read_u16_at, read_u32_at, read_u32_field, read_u64_field,
        Error, Result,
    };

    pub const MAGIC: u32 = 0x5053_5953;
    pub const VERSION: u16 = 1;
    pub const PAGE_BYTES: usize = 4096;
    pub const HEADER_LEN: usize = 16;
    pub const TLV_HEADER_LEN: usize = 4;
    pub const TLV_ALIGNMENT: usize = 8;

    pub const TAG_END: u16 = 0;
    pub const TAG_RAMINFO: u16 = 1;
    pub const TAG_PLIC: u16 = 2;
    pub const TAG_PCI_ECAM: u16 = 3;
    pub const TAG_INITRD: u16 = 4;
    pub const TAG_MTIME_FREQ: u16 = 5;
    pub const TAG_CMDLINE: u16 = 6;
    pub const TAG_BOARD: u16 = 7;
    pub const TAG_RTC: u16 = 8;
    pub const TAG_CONSOLE: u16 = 9;
    pub const TAG_IMSIC: u16 = 10;

    #[derive(Debug, Clone, Copy, Eq, PartialEq)]
    pub struct Header {
        pub magic: u32,
        pub version: u16,
        pub hdr_bytes: u16,
        pub total_bytes: u32,
    }

    #[derive(Debug, Clone, Copy, Eq, PartialEq)]
    pub struct Tlv<'a> {
        pub tag: u16,
        pub payload: &'a [u8],
        pub offset: usize,
        pub next_offset: usize,
    }

    #[derive(Debug, Clone, Copy, Eq, PartialEq)]
    pub struct Range {
        pub base: u64,
        pub size: u64,
    }

    #[derive(Debug, Clone, Copy)]
    pub struct Page<'a> {
        bytes: &'a [u8],
        header: Header,
    }

    impl<'a> Page<'a> {
        pub fn parse(bytes: &'a [u8]) -> Result<Self> {
            let header = parse_header(bytes)?;
            validate_header(bytes, header)?;
            let page = Self { bytes, header };
            page.validate_tlvs()?;
            Ok(page)
        }

        pub fn header(&self) -> Header {
            self.header
        }

        pub fn tlvs(&self) -> Tlvs<'a> {
            Tlvs {
                bytes: self.bytes,
                offset: self.header.hdr_bytes as usize,
                end: self.header.total_bytes as usize,
                finished: false,
                saw_end: false,
            }
        }

        pub fn find(&self, tag: u16) -> Result<Option<Tlv<'a>>> {
            for tlv in self.tlvs() {
                let tlv = tlv?;
                if tlv.tag == tag {
                    return Ok(Some(tlv));
                }
            }
            Ok(None)
        }

        pub fn raminfo(&self) -> Result<Option<Range>> {
            self.find(TAG_RAMINFO)?
                .map(|tlv| tlv.range("sysmap raminfo"))
                .transpose()
        }

        pub fn initrd(&self) -> Result<Option<Range>> {
            self.find(TAG_INITRD)?
                .map(|tlv| tlv.range("sysmap initrd"))
                .transpose()
        }

        pub fn mtime_hz(&self) -> Result<Option<u32>> {
            self.find(TAG_MTIME_FREQ)?
                .map(|tlv| tlv.u32_at(0, "sysmap mtime_freq.hz"))
                .transpose()
        }

        pub fn cmdline(&self) -> Result<Option<&'a str>> {
            self.find(TAG_CMDLINE)?
                .map(|tlv| tlv.cstr("sysmap cmdline"))
                .transpose()
        }

        fn validate_tlvs(&self) -> Result<()> {
            let mut tlvs = self.tlvs();
            for tlv in tlvs.by_ref() {
                tlv?;
            }
            if tlvs.saw_end {
                Ok(())
            } else {
                Err(Error::MissingEndTag)
            }
        }
    }

    impl<'a> Tlv<'a> {
        pub fn u32_at(&self, offset: usize, context: &'static str) -> Result<u32> {
            read_u32_field(self.payload, offset, context)
        }

        pub fn u64_at(&self, offset: usize, context: &'static str) -> Result<u64> {
            read_u64_field(self.payload, offset, context)
        }

        pub fn range(&self, context: &'static str) -> Result<Range> {
            if self.payload.len() < 16 {
                return Err(Error::UnexpectedLen {
                    context,
                    expected: 16,
                    actual: self.payload.len(),
                });
            }
            Ok(Range {
                base: read_u64_field(self.payload, 0, context)?,
                size: read_u64_field(self.payload, 8, context)?,
            })
        }

        pub fn cstr(&self, context: &'static str) -> Result<&'a str> {
            read_cstr(self.payload, context)
        }
    }

    pub struct Tlvs<'a> {
        bytes: &'a [u8],
        offset: usize,
        end: usize,
        finished: bool,
        saw_end: bool,
    }

    impl<'a> Iterator for Tlvs<'a> {
        type Item = Result<Tlv<'a>>;

        fn next(&mut self) -> Option<Self::Item> {
            if self.finished {
                return None;
            }

            match parse_tlv_at(self.bytes, self.offset, self.end) {
                Ok(Some(tlv)) => {
                    self.offset = tlv.next_offset;
                    Some(Ok(tlv))
                }
                Ok(None) => {
                    self.finished = true;
                    self.saw_end = true;
                    None
                }
                Err(err) => {
                    self.finished = true;
                    Some(Err(err))
                }
            }
        }
    }

    fn parse_header(bytes: &[u8]) -> Result<Header> {
        let header = read_at(bytes, 0, HEADER_LEN)?;
        Ok(Header {
            magic: read_u32_at(header, 0)?,
            version: read_u16_at(header, 4)?,
            hdr_bytes: read_u16_at(header, 6)?,
            total_bytes: read_u32_at(header, 8)?,
        })
    }

    fn validate_header(bytes: &[u8], header: Header) -> Result<()> {
        if header.magic != MAGIC {
            return Err(Error::BadSysmapMagic {
                found: header.magic,
            });
        }
        if header.version != VERSION {
            return Err(Error::UnsupportedSysmapVersion {
                found: header.version,
            });
        }

        let hdr_bytes = header.hdr_bytes as usize;
        let total_bytes =
            usize::try_from(header.total_bytes).map_err(|_| Error::ArithmeticOverflow)?;
        if hdr_bytes < HEADER_LEN
            || total_bytes < hdr_bytes
            || total_bytes > bytes.len()
            || total_bytes > PAGE_BYTES
        {
            return Err(Error::InvalidSysmapHeader {
                hdr_bytes: header.hdr_bytes,
                total_bytes: header.total_bytes,
            });
        }
        Ok(())
    }

    fn parse_tlv_at(bytes: &[u8], offset: usize, end: usize) -> Result<Option<Tlv<'_>>> {
        if offset >= end {
            return Err(Error::MissingEndTag);
        }

        let header_end = offset
            .checked_add(TLV_HEADER_LEN)
            .ok_or(Error::ArithmeticOverflow)?;
        if header_end > end {
            return Err(Error::Truncated {
                offset,
                len: TLV_HEADER_LEN,
            });
        }

        let header = read_at(bytes, offset, TLV_HEADER_LEN)?;
        let tag = read_u16_at(header, 0)?;
        let len = read_u16_at(header, 2)? as usize;
        if tag == TAG_END {
            if len != 0 {
                return Err(Error::UnexpectedLen {
                    context: "sysmap END",
                    expected: 0,
                    actual: len,
                });
            }
            return Ok(None);
        }

        let payload_offset = offset
            .checked_add(TLV_HEADER_LEN)
            .ok_or(Error::ArithmeticOverflow)?;
        let payload = read_at(bytes, payload_offset, len)?;
        let record_end = payload_offset
            .checked_add(len)
            .ok_or(Error::ArithmeticOverflow)?;
        if record_end > end {
            return Err(Error::Truncated { offset, len });
        }
        let next_offset = align_up(record_end, TLV_ALIGNMENT)?;
        if next_offset > end {
            return Err(Error::Truncated { offset, len });
        }

        Ok(Some(Tlv {
            tag,
            payload,
            offset,
            next_offset,
        }))
    }
}

fn read_cstr<'a>(bytes: &'a [u8], context: &'static str) -> Result<&'a str> {
    if bytes.last() != Some(&0) {
        return Err(Error::UnterminatedString { context });
    }
    str::from_utf8(&bytes[..bytes.len() - 1]).map_err(|_| Error::InvalidUtf8 { context })
}

fn align_up(offset: usize, align: usize) -> Result<usize> {
    offset
        .checked_add(align - 1)
        .map(|value| value & !(align - 1))
        .ok_or(Error::ArithmeticOverflow)
}

fn read_at(bytes: &[u8], offset: usize, len: usize) -> Result<&[u8]> {
    let end = offset.checked_add(len).ok_or(Error::ArithmeticOverflow)?;
    bytes
        .get(offset..end)
        .ok_or(Error::Truncated { offset, len })
}

fn read_u16(bytes: &[u8; 2]) -> u16 {
    u16::from_le_bytes(*bytes)
}

fn read_u32(bytes: &[u8; 4]) -> u32 {
    u32::from_le_bytes(*bytes)
}

fn read_u64(bytes: &[u8; 8]) -> u64 {
    u64::from_le_bytes(*bytes)
}

fn read_u16_at(bytes: &[u8], offset: usize) -> Result<u16> {
    match read_at(bytes, offset, 2)? {
        [a, b] => Ok(read_u16(&[*a, *b])),
        _ => Err(Error::ArithmeticOverflow),
    }
}

fn read_u32_at(bytes: &[u8], offset: usize) -> Result<u32> {
    match read_at(bytes, offset, 4)? {
        [a, b, c, d] => Ok(read_u32(&[*a, *b, *c, *d])),
        _ => Err(Error::ArithmeticOverflow),
    }
}

fn read_u64_at(bytes: &[u8], offset: usize) -> Result<u64> {
    match read_at(bytes, offset, 8)? {
        [a, b, c, d, e, f, g, h] => Ok(read_u64(&[*a, *b, *c, *d, *e, *f, *g, *h])),
        _ => Err(Error::ArithmeticOverflow),
    }
}

fn read_u32_field(bytes: &[u8], offset: usize, context: &'static str) -> Result<u32> {
    read_u32_at(bytes, offset).map_err(|err| field_len_error(err, context, offset, 4, bytes.len()))
}

fn read_u64_field(bytes: &[u8], offset: usize, context: &'static str) -> Result<u64> {
    read_u64_at(bytes, offset).map_err(|err| field_len_error(err, context, offset, 8, bytes.len()))
}

fn field_len_error(
    err: Error,
    context: &'static str,
    offset: usize,
    width: usize,
    actual: usize,
) -> Error {
    match err {
        Error::Truncated { .. } => Error::UnexpectedLen {
            context,
            expected: offset.saturating_add(width),
            actual,
        },
        other => other,
    }
}

#[cfg(test)]
extern crate std;

#[cfg(test)]
mod tests {
    use super::{syscfg, sysmap, Error};
    use std::vec::Vec;

    #[test]
    fn syscfg_reads_bounded_scalar_and_string_tags() {
        let mut bytes = Vec::new();
        push_syscfg_tag(&mut bytes, syscfg::TAG_VERSION, &1u32.to_le_bytes());
        push_syscfg_tag(
            &mut bytes,
            syscfg::TAG_TIMEBASE_HZ,
            &10_000_000u64.to_le_bytes(),
        );
        push_syscfg_tag(&mut bytes, syscfg::TAG_MODEL, b"qemu-virt\0");
        push_syscfg_tag(&mut bytes, syscfg::TAG_END, &[]);

        let blob = syscfg::Blob::parse(&bytes).expect("parse syscfg");
        assert_eq!(
            blob.find_u32(syscfg::TAG_VERSION),
            Ok(Some(syscfg::VERSION))
        );
        assert_eq!(blob.find_u64(syscfg::TAG_TIMEBASE_HZ), Ok(Some(10_000_000)));
        assert_eq!(
            blob.find_cstr(syscfg::TAG_MODEL, "model"),
            Ok(Some("qemu-virt"))
        );
        assert!(blob.find(syscfg::TAG_BOOT_HART).expect("find").is_none());

        let tags: Vec<u16> = blob.tags().map(|tag| tag.expect("tag").id).collect();
        assert_eq!(
            tags,
            [
                syscfg::TAG_VERSION,
                syscfg::TAG_TIMEBASE_HZ,
                syscfg::TAG_MODEL
            ]
        );
    }

    #[test]
    fn syscfg_rejects_tags_that_overrun_the_blob() {
        let bytes = [1, 0, 8, 0, 0, 0];
        assert!(matches!(
            syscfg::Blob::parse(&bytes),
            Err(Error::Truncated { offset: 4, len: 8 })
        ));
    }

    #[test]
    fn syscfg_rejects_missing_end_tag() {
        let mut bytes = Vec::new();
        push_syscfg_tag(&mut bytes, syscfg::TAG_VERSION, &1u32.to_le_bytes());
        assert!(matches!(
            syscfg::Blob::parse(&bytes),
            Err(Error::MissingEndTag)
        ));
    }

    #[test]
    fn syscfg_rejects_nonzero_end_tag_length() {
        let mut bytes = Vec::new();
        push_syscfg_tag(&mut bytes, syscfg::TAG_END, &[0]);

        assert!(matches!(
            syscfg::Blob::parse(&bytes),
            Err(Error::UnexpectedLen {
                context: "syscfg END",
                expected: 0,
                actual: 1
            })
        ));
    }

    #[test]
    fn syscfg_validates_lengths_before_exposing_scalars() {
        let mut bytes = Vec::new();
        push_syscfg_tag(&mut bytes, syscfg::TAG_VERSION, &[1, 0]);
        push_syscfg_tag(&mut bytes, syscfg::TAG_END, &[]);
        let blob = syscfg::Blob::parse(&bytes).expect("parse syscfg");

        assert!(matches!(
            blob.find_u32(syscfg::TAG_VERSION),
            Err(Error::UnexpectedLen {
                expected: 4,
                actual: 2,
                ..
            })
        ));
    }

    #[test]
    fn syscfg_validates_strings_before_exposing_strs() {
        let mut bytes = Vec::new();
        push_syscfg_tag(&mut bytes, syscfg::TAG_MODEL, b"not-terminated");
        push_syscfg_tag(&mut bytes, syscfg::TAG_END, &[]);
        let blob = syscfg::Blob::parse(&bytes).expect("parse syscfg");

        assert!(matches!(
            blob.find_cstr(syscfg::TAG_MODEL, "model"),
            Err(Error::UnterminatedString { context: "model" })
        ));
    }

    #[test]
    fn sysmap_reads_header_tlvs_and_typed_bodies() {
        let mut page = sysmap_header();
        push_sysmap_tlv(
            &mut page,
            sysmap::TAG_RAMINFO,
            &[
                0x00, 0x00, 0x00, 0x80, 0, 0, 0, 0, 0x00, 0x00, 0x00, 0x20, 0, 0, 0, 0,
            ],
        );
        push_sysmap_tlv(
            &mut page,
            sysmap::TAG_MTIME_FREQ,
            &[0x40, 0x42, 0x0f, 0, 0, 0, 0, 0],
        );
        push_sysmap_tlv(&mut page, sysmap::TAG_CMDLINE, b"mainfs=/dev/vblk0\0");
        push_sysmap_tlv(&mut page, sysmap::TAG_END, &[]);
        finish_sysmap(&mut page);

        let sysmap = sysmap::Page::parse(&page).expect("parse sysmap");
        assert_eq!(sysmap.header().hdr_bytes as usize, sysmap::HEADER_LEN);
        assert_eq!(
            sysmap.raminfo().expect("raminfo"),
            Some(sysmap::Range {
                base: 0x8000_0000,
                size: 0x2000_0000
            })
        );
        assert_eq!(sysmap.mtime_hz(), Ok(Some(1_000_000)));
        assert_eq!(sysmap.cmdline(), Ok(Some("mainfs=/dev/vblk0")));
    }

    #[test]
    fn sysmap_rejects_bad_magic_and_invalid_bounds() {
        let mut page = sysmap_header();
        push_sysmap_tlv(&mut page, sysmap::TAG_END, &[]);
        finish_sysmap(&mut page);

        page[0] = 0;
        assert!(matches!(
            sysmap::Page::parse(&page),
            Err(Error::BadSysmapMagic { .. })
        ));

        let mut page = sysmap_header();
        put_u32(&mut page, 8, 5000);
        assert!(matches!(
            sysmap::Page::parse(&page),
            Err(Error::InvalidSysmapHeader { .. })
        ));
    }

    #[test]
    fn sysmap_rejects_tlv_overrun_and_missing_end() {
        let mut page = sysmap_header();
        page.extend_from_slice(&sysmap::TAG_RAMINFO.to_le_bytes());
        page.extend_from_slice(&(64u16).to_le_bytes());
        finish_sysmap(&mut page);

        assert!(matches!(
            sysmap::Page::parse(&page),
            Err(Error::Truncated { .. })
        ));

        let mut page = sysmap_header();
        push_sysmap_tlv(&mut page, sysmap::TAG_RAMINFO, &[0; 16]);
        finish_sysmap(&mut page);
        assert!(matches!(
            sysmap::Page::parse(&page),
            Err(Error::MissingEndTag)
        ));
    }

    #[test]
    fn sysmap_rejects_partial_tlv_header_inside_total_bytes() {
        let mut page = sysmap_header();
        page.extend_from_slice(&sysmap::TAG_RAMINFO.to_le_bytes());
        finish_sysmap(&mut page);

        assert!(matches!(
            sysmap::Page::parse(&page),
            Err(Error::Truncated {
                offset: sysmap::HEADER_LEN,
                len: sysmap::TLV_HEADER_LEN
            })
        ));
    }

    #[test]
    fn sysmap_rejects_nonzero_end_tlv_length() {
        let mut page = sysmap_header();
        push_sysmap_tlv(&mut page, sysmap::TAG_END, &[0]);
        finish_sysmap(&mut page);

        assert!(matches!(
            sysmap::Page::parse(&page),
            Err(Error::UnexpectedLen {
                context: "sysmap END",
                expected: 0,
                actual: 1
            })
        ));
    }

    #[test]
    fn sysmap_validates_body_lengths_before_exposing_fields() {
        let mut page = sysmap_header();
        push_sysmap_tlv(&mut page, sysmap::TAG_RAMINFO, &[0; 8]);
        push_sysmap_tlv(&mut page, sysmap::TAG_CMDLINE, b"not-terminated");
        push_sysmap_tlv(&mut page, sysmap::TAG_END, &[]);
        finish_sysmap(&mut page);
        let sysmap = sysmap::Page::parse(&page).expect("parse sysmap");

        assert!(matches!(
            sysmap.raminfo(),
            Err(Error::UnexpectedLen {
                expected: 16,
                actual: 8,
                ..
            })
        ));
        assert!(matches!(
            sysmap.cmdline(),
            Err(Error::UnterminatedString {
                context: "sysmap cmdline"
            })
        ));
    }

    fn push_syscfg_tag(bytes: &mut Vec<u8>, id: u16, payload: &[u8]) {
        bytes.extend_from_slice(&id.to_le_bytes());
        bytes.extend_from_slice(&(payload.len() as u16).to_le_bytes());
        bytes.extend_from_slice(payload);
    }

    fn sysmap_header() -> Vec<u8> {
        let mut page = Vec::new();
        page.extend_from_slice(&sysmap::MAGIC.to_le_bytes());
        page.extend_from_slice(&sysmap::VERSION.to_le_bytes());
        page.extend_from_slice(&(sysmap::HEADER_LEN as u16).to_le_bytes());
        page.extend_from_slice(&0u32.to_le_bytes());
        page.extend_from_slice(&0u32.to_le_bytes());
        page
    }

    fn push_sysmap_tlv(page: &mut Vec<u8>, tag: u16, payload: &[u8]) {
        page.extend_from_slice(&tag.to_le_bytes());
        page.extend_from_slice(&(payload.len() as u16).to_le_bytes());
        page.extend_from_slice(payload);
        let pad =
            (sysmap::TLV_ALIGNMENT - page.len() % sysmap::TLV_ALIGNMENT) % sysmap::TLV_ALIGNMENT;
        page.resize(page.len() + pad, 0);
    }

    fn finish_sysmap(page: &mut Vec<u8>) {
        let len = page.len() as u32;
        put_u32(page, 8, len);
    }

    fn put_u32(bytes: &mut [u8], offset: usize, value: u32) {
        bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
    }
}
