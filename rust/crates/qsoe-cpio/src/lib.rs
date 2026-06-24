#![no_std]

use core::fmt;
use core::str;

pub const CPIO_HEADER_MAGIC: &[u8; 6] = b"070701";
pub const CPIO_FOOTER_MAGIC: &str = "TRAILER!!!";
pub const CPIO_ALIGNMENT: usize = 4;
pub const NEWC_HEADER_LEN: usize = 110;

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum Error {
    Truncated { offset: usize, len: usize },
    BadMagic { offset: usize },
    InvalidHex { offset: usize, byte: u8 },
    InvalidNameSize { offset: usize, namesize: u32 },
    UnterminatedName { offset: usize, namesize: usize },
    InvalidUtf8Name { offset: usize },
    ArithmeticOverflow,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Truncated { offset, len } => {
                write!(
                    f,
                    "truncated cpio archive at offset {offset}, need {len} bytes"
                )
            }
            Self::BadMagic { offset } => {
                write!(f, "bad cpio newc magic at offset {offset}")
            }
            Self::InvalidHex { offset, byte } => {
                write!(f, "invalid cpio hex byte 0x{byte:02x} at offset {offset}")
            }
            Self::InvalidNameSize { offset, namesize } => {
                write!(
                    f,
                    "invalid cpio namesize {namesize} at header offset {offset}"
                )
            }
            Self::UnterminatedName { offset, namesize } => {
                write!(
                    f,
                    "unterminated cpio name at offset {offset}, namesize {namesize}"
                )
            }
            Self::InvalidUtf8Name { offset } => {
                write!(f, "cpio entry name at offset {offset} is not UTF-8")
            }
            Self::ArithmeticOverflow => write!(f, "cpio offset arithmetic overflow"),
        }
    }
}

pub type Result<T> = core::result::Result<T, Error>;

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub struct NewcHeader {
    pub ino: u32,
    pub mode: u32,
    pub uid: u32,
    pub gid: u32,
    pub nlink: u32,
    pub mtime: u32,
    pub filesize: u32,
    pub devmajor: u32,
    pub devminor: u32,
    pub rdevmajor: u32,
    pub rdevminor: u32,
    pub namesize: u32,
    pub check: u32,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub struct Entry<'a> {
    pub header: NewcHeader,
    pub name: &'a str,
    pub data: &'a [u8],
    pub header_offset: usize,
    pub data_offset: usize,
    pub next_offset: usize,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub struct Info {
    pub file_count: usize,
    pub max_path_len: usize,
}

#[derive(Debug, Clone, Copy)]
pub struct Archive<'a> {
    bytes: &'a [u8],
}

impl<'a> Archive<'a> {
    pub fn parse(bytes: &'a [u8]) -> Result<Self> {
        let archive = Self { bytes };
        archive.validate()?;
        Ok(archive)
    }

    pub fn entries(&self) -> Entries<'a> {
        Entries {
            bytes: self.bytes,
            offset: 0,
            finished: false,
        }
    }

    pub fn entry(&self, index: usize) -> Result<Option<Entry<'a>>> {
        for (idx, entry) in self.entries().enumerate() {
            let entry = entry?;
            if idx == index {
                return Ok(Some(entry));
            }
        }
        Ok(None)
    }

    pub fn file(&self, name: &str) -> Result<Option<Entry<'a>>> {
        for entry in self.entries() {
            let entry = entry?;
            if entry.name == name {
                return Ok(Some(entry));
            }
        }
        Ok(None)
    }

    pub fn info(&self) -> Result<Info> {
        let mut file_count = 0;
        let mut max_path_len = 0;

        for entry in self.entries() {
            let entry = entry?;
            file_count += 1;
            max_path_len = max_path_len.max(entry.name.len());
        }

        Ok(Info {
            file_count,
            max_path_len,
        })
    }

    fn validate(&self) -> Result<()> {
        for entry in self.entries() {
            entry?;
        }
        Ok(())
    }
}

pub struct Entries<'a> {
    bytes: &'a [u8],
    offset: usize,
    finished: bool,
}

impl<'a> Iterator for Entries<'a> {
    type Item = Result<Entry<'a>>;

    fn next(&mut self) -> Option<Self::Item> {
        if self.finished {
            return None;
        }

        match parse_entry_at(self.bytes, self.offset) {
            Ok(Some(entry)) => {
                self.offset = entry.next_offset;
                Some(Ok(entry))
            }
            Ok(None) => {
                self.finished = true;
                None
            }
            Err(err) => {
                self.finished = true;
                Some(Err(err))
            }
        }
    }
}

fn parse_entry_at(bytes: &[u8], offset: usize) -> Result<Option<Entry<'_>>> {
    let header_bytes = read_at(bytes, offset, NEWC_HEADER_LEN)?;
    if read_at(header_bytes, 0, CPIO_HEADER_MAGIC.len())? != CPIO_HEADER_MAGIC {
        return Err(Error::BadMagic { offset });
    }

    let header = parse_header(header_bytes, offset)?;
    if header.namesize == 0 {
        return Err(Error::InvalidNameSize {
            offset,
            namesize: header.namesize,
        });
    }

    let namesize = usize::try_from(header.namesize).map_err(|_| Error::ArithmeticOverflow)?;
    let filesize = usize::try_from(header.filesize).map_err(|_| Error::ArithmeticOverflow)?;
    let name_offset = offset
        .checked_add(NEWC_HEADER_LEN)
        .ok_or(Error::ArithmeticOverflow)?;
    let name = read_at(bytes, name_offset, namesize)?;
    if name.last() != Some(&0) {
        return Err(Error::UnterminatedName {
            offset: name_offset,
            namesize,
        });
    }

    let name = &name[..name.len() - 1];
    let name = str::from_utf8(name).map_err(|_| Error::InvalidUtf8Name {
        offset: name_offset,
    })?;
    if name == CPIO_FOOTER_MAGIC {
        return Ok(None);
    }

    let data_offset = align_up(
        name_offset
            .checked_add(namesize)
            .ok_or(Error::ArithmeticOverflow)?,
    )?;
    let data = read_at(bytes, data_offset, filesize)?;
    let next_offset = align_up(
        data_offset
            .checked_add(filesize)
            .ok_or(Error::ArithmeticOverflow)?,
    )?;
    read_at(bytes, next_offset, 0)?;

    Ok(Some(Entry {
        header,
        name,
        data,
        header_offset: offset,
        data_offset,
        next_offset,
    }))
}

fn parse_header(bytes: &[u8], header_offset: usize) -> Result<NewcHeader> {
    Ok(NewcHeader {
        ino: read_hex_field(bytes, header_offset, 6)?,
        mode: read_hex_field(bytes, header_offset, 14)?,
        uid: read_hex_field(bytes, header_offset, 22)?,
        gid: read_hex_field(bytes, header_offset, 30)?,
        nlink: read_hex_field(bytes, header_offset, 38)?,
        mtime: read_hex_field(bytes, header_offset, 46)?,
        filesize: read_hex_field(bytes, header_offset, 54)?,
        devmajor: read_hex_field(bytes, header_offset, 62)?,
        devminor: read_hex_field(bytes, header_offset, 70)?,
        rdevmajor: read_hex_field(bytes, header_offset, 78)?,
        rdevminor: read_hex_field(bytes, header_offset, 86)?,
        namesize: read_hex_field(bytes, header_offset, 94)?,
        check: read_hex_field(bytes, header_offset, 102)?,
    })
}

fn read_hex_field(bytes: &[u8], header_offset: usize, field_offset: usize) -> Result<u32> {
    let mut value = 0u32;
    for (idx, byte) in read_at(bytes, field_offset, 8)?.iter().copied().enumerate() {
        let digit = match byte {
            b'0'..=b'9' => u32::from(byte - b'0'),
            b'a'..=b'f' => u32::from(byte - b'a' + 10),
            b'A'..=b'F' => u32::from(byte - b'A' + 10),
            _ => {
                return Err(Error::InvalidHex {
                    offset: header_offset + field_offset + idx,
                    byte,
                });
            }
        };
        value = (value << 4) | digit;
    }
    Ok(value)
}

fn align_up(offset: usize) -> Result<usize> {
    offset
        .checked_add(CPIO_ALIGNMENT - 1)
        .map(|value| value & !(CPIO_ALIGNMENT - 1))
        .ok_or(Error::ArithmeticOverflow)
}

fn read_at(bytes: &[u8], offset: usize, len: usize) -> Result<&[u8]> {
    let end = offset.checked_add(len).ok_or(Error::ArithmeticOverflow)?;
    bytes
        .get(offset..end)
        .ok_or(Error::Truncated { offset, len })
}

#[cfg(test)]
extern crate std;

#[cfg(test)]
mod tests {
    use super::*;
    use std::vec::Vec;

    #[test]
    fn parses_valid_newc_archive() {
        let bytes = fixture_archive();
        let archive = Archive::parse(&bytes).expect("parse cpio");
        let info = archive.info().expect("info");

        assert_eq!(
            info,
            Info {
                file_count: 2,
                max_path_len: "etc/passwd".len()
            }
        );

        let first = archive.entry(0).expect("entry 0").expect("entry exists");
        assert_eq!(first.name, "bin/hello");
        assert_eq!(first.data, b"hello");
        assert_eq!(first.header.filesize, 5);

        let passwd = archive
            .file("etc/passwd")
            .expect("find passwd")
            .expect("passwd exists");
        assert_eq!(passwd.data, b"root:x:0:0:root:/:/bin/qsh\n");

        assert!(archive.entry(2).expect("entry 2").is_none());
        assert!(archive.file("missing").expect("missing").is_none());
    }

    #[test]
    fn iterator_yields_entries_in_archive_order() {
        let bytes = fixture_archive();
        let archive = Archive::parse(&bytes).expect("parse cpio");
        let names: Vec<&str> = archive
            .entries()
            .map(|entry| entry.expect("entry").name)
            .collect();

        assert_eq!(names, ["bin/hello", "etc/passwd"]);
    }

    #[test]
    fn rejects_truncated_header_without_panicking() {
        assert!(matches!(
            Archive::parse(b"070701"),
            Err(Error::Truncated {
                offset: 0,
                len: NEWC_HEADER_LEN
            })
        ));
    }

    #[test]
    fn rejects_bad_magic_without_panicking() {
        let mut archive = fixture_archive();
        archive[0] = b'1';

        assert!(matches!(
            Archive::parse(&archive),
            Err(Error::BadMagic { offset: 0 })
        ));
    }

    #[test]
    fn rejects_invalid_hex_without_panicking() {
        let mut archive = fixture_archive();
        archive[54] = b'g';

        assert!(matches!(
            Archive::parse(&archive),
            Err(Error::InvalidHex {
                offset: 54,
                byte: b'g'
            })
        ));
    }

    #[test]
    fn rejects_zero_namesize_without_panicking() {
        let mut archive = fixture_archive();
        archive[94..102].copy_from_slice(b"00000000");

        assert!(matches!(
            Archive::parse(&archive),
            Err(Error::InvalidNameSize {
                offset: 0,
                namesize: 0
            })
        ));
    }

    #[test]
    fn rejects_unterminated_name_without_panicking() {
        let mut archive = fixture_archive();
        let namesize = u32::from_str_radix(str::from_utf8(&archive[94..102]).unwrap(), 16)
            .expect("namesize") as usize;
        let nul = NEWC_HEADER_LEN + namesize - 1;
        archive[nul] = b'x';

        assert!(matches!(
            Archive::parse(&archive),
            Err(Error::UnterminatedName {
                offset: NEWC_HEADER_LEN,
                ..
            })
        ));
    }

    #[test]
    fn rejects_invalid_utf8_name_without_panicking() {
        let mut archive = fixture_archive();
        archive[NEWC_HEADER_LEN] = 0xff;

        assert!(matches!(
            Archive::parse(&archive),
            Err(Error::InvalidUtf8Name {
                offset: NEWC_HEADER_LEN
            })
        ));
    }

    #[test]
    fn rejects_truncated_data_without_panicking() {
        let mut archive = Vec::new();
        push_entry(&mut archive, "bin/hello", b"hello");
        archive.truncate(NEWC_HEADER_LEN + "bin/hello".len() + 1);

        assert!(matches!(
            Archive::parse(&archive),
            Err(Error::Truncated { .. })
        ));
    }

    fn fixture_archive() -> Vec<u8> {
        let mut archive = Vec::new();
        push_entry(&mut archive, "bin/hello", b"hello");
        push_entry(&mut archive, "etc/passwd", b"root:x:0:0:root:/:/bin/qsh\n");
        push_entry(&mut archive, CPIO_FOOTER_MAGIC, b"");
        archive
    }

    fn push_entry(archive: &mut Vec<u8>, name: &str, data: &[u8]) {
        let namesize = name.len() + 1;
        archive.extend_from_slice(b"070701");
        push_hex(archive, 1);
        push_hex(archive, 0o100644);
        push_hex(archive, 0);
        push_hex(archive, 0);
        push_hex(archive, 1);
        push_hex(archive, 0);
        push_hex(archive, data.len() as u32);
        push_hex(archive, 0);
        push_hex(archive, 0);
        push_hex(archive, 0);
        push_hex(archive, 0);
        push_hex(archive, namesize as u32);
        push_hex(archive, 0);

        archive.extend_from_slice(name.as_bytes());
        archive.push(0);
        pad_to_alignment(archive);
        archive.extend_from_slice(data);
        pad_to_alignment(archive);
    }

    fn push_hex(archive: &mut Vec<u8>, value: u32) {
        use std::format;

        archive.extend_from_slice(format!("{value:08x}").as_bytes());
    }

    fn pad_to_alignment(archive: &mut Vec<u8>) {
        let padding = (CPIO_ALIGNMENT - archive.len() % CPIO_ALIGNMENT) % CPIO_ALIGNMENT;
        archive.resize(archive.len() + padding, 0);
    }
}
