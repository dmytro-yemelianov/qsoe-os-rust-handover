#![no_std]

use core::convert::{TryFrom, TryInto};
use core::fmt;

pub const ELF_MAGIC: &[u8; 4] = b"\x7fELF";
pub const EI_CLASS: usize = 4;
pub const EI_DATA: usize = 5;
pub const EI_VERSION: usize = 6;
pub const ELFCLASS64: u8 = 2;
pub const ELFDATA2LSB: u8 = 1;
pub const EV_CURRENT: u8 = 1;
pub const ET_EXEC: u16 = 2;
pub const EM_RISCV: u16 = 243;
pub const ELF64_EHDR_LEN: usize = 64;
pub const ELF64_SHDR_LEN: usize = 64;
pub const ELF64_REL_LEN: usize = 16;
pub const ELF64_RELA_LEN: usize = 24;
pub const SHT_REL: u32 = 9;
pub const SHT_RELA: u32 = 4;

pub mod riscv {
    pub const R_RISCV_NONE: u32 = 0;
    pub const R_RISCV_32: u32 = 1;
    pub const R_RISCV_64: u32 = 2;
    pub const R_RISCV_RELATIVE: u32 = 3;
    pub const R_RISCV_COPY: u32 = 4;
    pub const R_RISCV_JUMP_SLOT: u32 = 5;

    pub fn relocation_name(type_: u32) -> Option<&'static str> {
        match type_ {
            R_RISCV_NONE => Some("R_RISCV_NONE"),
            R_RISCV_32 => Some("R_RISCV_32"),
            R_RISCV_64 => Some("R_RISCV_64"),
            R_RISCV_RELATIVE => Some("R_RISCV_RELATIVE"),
            R_RISCV_COPY => Some("R_RISCV_COPY"),
            R_RISCV_JUMP_SLOT => Some("R_RISCV_JUMP_SLOT"),
            _ => None,
        }
    }
}

pub fn relocation_type_name(machine: u16, type_: u32) -> Option<&'static str> {
    match machine {
        EM_RISCV => riscv::relocation_name(type_),
        _ => None,
    }
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum Error {
    Truncated {
        offset: usize,
        len: usize,
    },
    BadMagic,
    UnsupportedClass {
        found: u8,
    },
    UnsupportedData {
        found: u8,
    },
    UnsupportedVersion {
        found: u8,
    },
    UnsupportedElf {
        reason: &'static str,
    },
    InvalidSectionEntrySize {
        index: u16,
        expected: usize,
        actual: usize,
    },
    ArithmeticOverflow,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Truncated { offset, len } => {
                write!(f, "truncated ELF file at offset {offset}, need {len} bytes")
            }
            Self::BadMagic => write!(f, "bad ELF magic"),
            Self::UnsupportedClass { found } => write!(f, "unsupported ELF class {found}"),
            Self::UnsupportedData { found } => write!(f, "unsupported ELF data encoding {found}"),
            Self::UnsupportedVersion { found } => write!(f, "unsupported ELF version {found}"),
            Self::UnsupportedElf { reason } => write!(f, "unsupported ELF file: {reason}"),
            Self::InvalidSectionEntrySize {
                index,
                expected,
                actual,
            } => write!(
                f,
                "invalid ELF section {index} entry size {actual}, expected at least {expected}"
            ),
            Self::ArithmeticOverflow => write!(f, "ELF offset arithmetic overflow"),
        }
    }
}

pub type Result<T> = core::result::Result<T, Error>;

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub struct Header {
    pub type_: u16,
    pub machine: u16,
    pub entry: u64,
    pub phoff: u64,
    pub shoff: u64,
    pub flags: u32,
    pub ehsize: u16,
    pub phentsize: u16,
    pub phnum: u16,
    pub shentsize: u16,
    pub shnum: u16,
    pub shstrndx: u16,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub struct SectionHeader {
    pub index: u16,
    pub name_offset: u32,
    pub type_: u32,
    pub flags: u64,
    pub addr: u64,
    pub offset: u64,
    pub size: u64,
    pub link: u32,
    pub info: u32,
    pub addralign: u64,
    pub entsize: u64,
}

impl SectionHeader {
    pub fn is_relocation(&self) -> bool {
        self.type_ == SHT_REL || self.type_ == SHT_RELA
    }

    pub fn has_addends(&self) -> bool {
        self.type_ == SHT_RELA
    }
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub struct Relocation {
    pub section_index: u16,
    pub offset: u64,
    pub symbol: u32,
    pub type_: u32,
    pub addend: Option<i64>,
}

#[derive(Debug, Clone, Copy)]
pub struct ElfFile<'a> {
    bytes: &'a [u8],
    header: Header,
}

impl<'a> ElfFile<'a> {
    pub fn parse(bytes: &'a [u8]) -> Result<Self> {
        let header = parse_header(bytes)?;
        validate_section_table(bytes, &header)?;
        Ok(Self { bytes, header })
    }

    pub fn header(&self) -> Header {
        self.header
    }

    pub fn sections(&self) -> Sections<'a> {
        Sections {
            file: *self,
            index: 0,
        }
    }

    pub fn section(&self, index: u16) -> Result<SectionHeader> {
        if index >= self.header.shnum {
            return Err(Error::UnsupportedElf {
                reason: "section index out of range",
            });
        }

        let shoff = usize::try_from(self.header.shoff).map_err(|_| Error::ArithmeticOverflow)?;
        let shentsize = usize::from(self.header.shentsize);
        let offset = shoff
            .checked_add(
                usize::from(index)
                    .checked_mul(shentsize)
                    .ok_or(Error::ArithmeticOverflow)?,
            )
            .ok_or(Error::ArithmeticOverflow)?;
        parse_section_header(read_at(self.bytes, offset, ELF64_SHDR_LEN)?, index)
    }

    pub fn relocation_entries(&self, section: SectionHeader) -> Result<RelocationEntries<'a>> {
        if !section.is_relocation() {
            return Err(Error::UnsupportedElf {
                reason: "section is not a relocation section",
            });
        }

        let expected = if section.has_addends() {
            ELF64_RELA_LEN
        } else {
            ELF64_REL_LEN
        };
        let entsize = if section.entsize == 0 {
            expected
        } else {
            usize::try_from(section.entsize).map_err(|_| Error::ArithmeticOverflow)?
        };
        if entsize < expected {
            return Err(Error::InvalidSectionEntrySize {
                index: section.index,
                expected,
                actual: entsize,
            });
        }

        let offset = usize::try_from(section.offset).map_err(|_| Error::ArithmeticOverflow)?;
        let size = usize::try_from(section.size).map_err(|_| Error::ArithmeticOverflow)?;
        if size % entsize != 0 {
            return Err(Error::UnsupportedElf {
                reason: "relocation section size is not a multiple of entry size",
            });
        }

        Ok(RelocationEntries {
            bytes: read_at(self.bytes, offset, size)?,
            section_index: section.index,
            has_addends: section.has_addends(),
            expected,
            entsize,
            next_offset: 0,
        })
    }

    pub fn relocations(&self) -> Relocations<'a> {
        Relocations {
            file: *self,
            next_section: 0,
            current: None,
            done: false,
        }
    }
}

pub struct Sections<'a> {
    file: ElfFile<'a>,
    index: u16,
}

impl Iterator for Sections<'_> {
    type Item = Result<SectionHeader>;

    fn next(&mut self) -> Option<Self::Item> {
        if self.index >= self.file.header.shnum {
            return None;
        }

        let index = self.index;
        self.index = self.index.saturating_add(1);
        Some(self.file.section(index))
    }
}

pub struct RelocationEntries<'a> {
    bytes: &'a [u8],
    section_index: u16,
    has_addends: bool,
    expected: usize,
    entsize: usize,
    next_offset: usize,
}

impl Iterator for RelocationEntries<'_> {
    type Item = Result<Relocation>;

    fn next(&mut self) -> Option<Self::Item> {
        if self.next_offset >= self.bytes.len() {
            return None;
        }

        let offset = self.next_offset;
        self.next_offset = self.next_offset.saturating_add(self.entsize);
        Some(parse_relocation(
            self.bytes,
            offset,
            self.section_index,
            self.has_addends,
            self.expected,
        ))
    }
}

pub struct Relocations<'a> {
    file: ElfFile<'a>,
    next_section: u16,
    current: Option<RelocationEntries<'a>>,
    done: bool,
}

impl Iterator for Relocations<'_> {
    type Item = Result<Relocation>;

    fn next(&mut self) -> Option<Self::Item> {
        if self.done {
            return None;
        }

        loop {
            if let Some(entries) = &mut self.current {
                if let Some(entry) = entries.next() {
                    return Some(entry);
                }
                self.current = None;
            }

            if self.next_section >= self.file.header.shnum {
                self.done = true;
                return None;
            }

            let section = match self.file.section(self.next_section) {
                Ok(section) => section,
                Err(err) => {
                    self.done = true;
                    return Some(Err(err));
                }
            };
            self.next_section = self.next_section.saturating_add(1);

            if section.is_relocation() {
                match self.file.relocation_entries(section) {
                    Ok(entries) => self.current = Some(entries),
                    Err(err) => {
                        self.done = true;
                        return Some(Err(err));
                    }
                }
            }
        }
    }
}

fn parse_header(bytes: &[u8]) -> Result<Header> {
    let header = read_at(bytes, 0, ELF64_EHDR_LEN)?;
    if read_at(header, 0, ELF_MAGIC.len())? != ELF_MAGIC {
        return Err(Error::BadMagic);
    }
    if header[EI_CLASS] != ELFCLASS64 {
        return Err(Error::UnsupportedClass {
            found: header[EI_CLASS],
        });
    }
    if header[EI_DATA] != ELFDATA2LSB {
        return Err(Error::UnsupportedData {
            found: header[EI_DATA],
        });
    }
    if header[EI_VERSION] != EV_CURRENT {
        return Err(Error::UnsupportedVersion {
            found: header[EI_VERSION],
        });
    }

    let ehsize = read_u16_at(header, 52)?;
    if usize::from(ehsize) < ELF64_EHDR_LEN {
        return Err(Error::UnsupportedElf {
            reason: "ELF header entry is too small",
        });
    }

    Ok(Header {
        type_: read_u16_at(header, 16)?,
        machine: read_u16_at(header, 18)?,
        entry: read_u64_at(header, 24)?,
        phoff: read_u64_at(header, 32)?,
        shoff: read_u64_at(header, 40)?,
        flags: read_u32_at(header, 48)?,
        ehsize,
        phentsize: read_u16_at(header, 54)?,
        phnum: read_u16_at(header, 56)?,
        shentsize: read_u16_at(header, 58)?,
        shnum: read_u16_at(header, 60)?,
        shstrndx: read_u16_at(header, 62)?,
    })
}

fn validate_section_table(bytes: &[u8], header: &Header) -> Result<()> {
    if header.shnum == 0 {
        return Ok(());
    }

    let shentsize = usize::from(header.shentsize);
    if shentsize < ELF64_SHDR_LEN {
        return Err(Error::UnsupportedElf {
            reason: "section header entry is too small",
        });
    }

    let shoff = usize::try_from(header.shoff).map_err(|_| Error::ArithmeticOverflow)?;
    let table_len = usize::from(header.shnum)
        .checked_mul(shentsize)
        .ok_or(Error::ArithmeticOverflow)?;
    read_at(bytes, shoff, table_len)?;
    Ok(())
}

fn parse_section_header(bytes: &[u8], index: u16) -> Result<SectionHeader> {
    Ok(SectionHeader {
        index,
        name_offset: read_u32_at(bytes, 0)?,
        type_: read_u32_at(bytes, 4)?,
        flags: read_u64_at(bytes, 8)?,
        addr: read_u64_at(bytes, 16)?,
        offset: read_u64_at(bytes, 24)?,
        size: read_u64_at(bytes, 32)?,
        link: read_u32_at(bytes, 40)?,
        info: read_u32_at(bytes, 44)?,
        addralign: read_u64_at(bytes, 48)?,
        entsize: read_u64_at(bytes, 56)?,
    })
}

fn parse_relocation(
    bytes: &[u8],
    offset: usize,
    section_index: u16,
    has_addends: bool,
    expected: usize,
) -> Result<Relocation> {
    let entry = read_at(bytes, offset, expected)?;
    let info = read_u64_at(entry, 8)?;

    Ok(Relocation {
        section_index,
        offset: read_u64_at(entry, 0)?,
        symbol: (info >> 32) as u32,
        type_: info as u32,
        addend: if has_addends {
            Some(read_i64_at(entry, 16)?)
        } else {
            None
        },
    })
}

fn read_at(bytes: &[u8], offset: usize, len: usize) -> Result<&[u8]> {
    let end = offset.checked_add(len).ok_or(Error::ArithmeticOverflow)?;
    bytes
        .get(offset..end)
        .ok_or(Error::Truncated { offset, len })
}

fn read_array_at<const N: usize>(bytes: &[u8], offset: usize) -> Result<&[u8; N]> {
    read_at(bytes, offset, N)?
        .try_into()
        .map_err(|_| Error::Truncated { offset, len: N })
}

fn read_u16_at(bytes: &[u8], offset: usize) -> Result<u16> {
    Ok(u16::from_le_bytes(*read_array_at::<2>(bytes, offset)?))
}

fn read_u32_at(bytes: &[u8], offset: usize) -> Result<u32> {
    Ok(u32::from_le_bytes(*read_array_at::<4>(bytes, offset)?))
}

fn read_u64_at(bytes: &[u8], offset: usize) -> Result<u64> {
    Ok(u64::from_le_bytes(*read_array_at::<8>(bytes, offset)?))
}

fn read_i64_at(bytes: &[u8], offset: usize) -> Result<i64> {
    Ok(i64::from_le_bytes(*read_array_at::<8>(bytes, offset)?))
}

#[cfg(test)]
extern crate std;

#[cfg(test)]
mod tests {
    use super::{relocation_type_name, riscv, ElfFile, Error};
    use std::env;
    use std::eprintln;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::vec;
    use std::vec::Vec;

    #[test]
    fn parses_synthetic_relocation_sections() {
        let bytes = synthetic_elf();
        let elf = ElfFile::parse(&bytes).expect("parse ELF");

        assert_eq!(elf.header().machine, super::EM_RISCV);

        let sections: Vec<_> = elf
            .sections()
            .map(|section| section.expect("section"))
            .collect();
        assert_eq!(sections.len(), 3);
        assert!(sections[1].has_addends());
        assert!(sections[2].is_relocation());

        let relocations: Vec<_> = elf
            .relocations()
            .map(|relocation| relocation.expect("relocation"))
            .collect();
        assert_eq!(
            relocations,
            vec![
                super::Relocation {
                    section_index: 1,
                    offset: 0x1000,
                    symbol: 2,
                    type_: riscv::R_RISCV_64,
                    addend: Some(-4),
                },
                super::Relocation {
                    section_index: 1,
                    offset: 0x2000,
                    symbol: 3,
                    type_: riscv::R_RISCV_JUMP_SLOT,
                    addend: Some(0),
                },
                super::Relocation {
                    section_index: 2,
                    offset: 0x3000,
                    symbol: 0,
                    type_: riscv::R_RISCV_RELATIVE,
                    addend: None,
                },
            ]
        );
    }

    #[test]
    fn rejects_bad_magic_and_truncated_section_table() {
        assert!(matches!(
            ElfFile::parse(b"not elf"),
            Err(Error::Truncated { .. })
        ));

        let mut bytes = synthetic_elf();
        bytes[0] = 0;
        assert!(matches!(ElfFile::parse(&bytes), Err(Error::BadMagic)));

        let mut bytes = synthetic_elf();
        bytes.truncate(128);
        assert!(matches!(
            ElfFile::parse(&bytes),
            Err(Error::Truncated {
                offset: 64,
                len: 192
            })
        ));
    }

    #[test]
    fn identifies_relocation_types_used_by_existing_qsoe_binaries() {
        let fixtures: &[(&str, &[(u32, usize)])] = &[
            (
                "quser/build/sbin/slogger/slogger.elf",
                &[(riscv::R_RISCV_64, 1), (riscv::R_RISCV_JUMP_SLOT, 10)],
            ),
            (
                "quser/build/dev/virtio/devb-virtio.elf",
                &[(riscv::R_RISCV_64, 1), (riscv::R_RISCV_JUMP_SLOT, 19)],
            ),
            (
                "quser/build/fs/qrv/fs-qrv.elf",
                &[(riscv::R_RISCV_64, 1), (riscv::R_RISCV_JUMP_SLOT, 25)],
            ),
            (
                "quser/build/qsh/qsh.elf",
                &[(riscv::R_RISCV_64, 186), (riscv::R_RISCV_JUMP_SLOT, 66)],
            ),
            (
                "quser/build/sbin/login/login.elf",
                &[(riscv::R_RISCV_64, 3), (riscv::R_RISCV_JUMP_SLOT, 29)],
            ),
            (
                "quser/build/test/msgpass/test_msgpass.elf",
                &[(riscv::R_RISCV_JUMP_SLOT, 11)],
            ),
            (
                "quser/build/test/syncspace/test_syncspace.elf",
                &[(riscv::R_RISCV_JUMP_SLOT, 9)],
            ),
            (
                "quser/build/test/suite/suite.elf",
                &[(riscv::R_RISCV_JUMP_SLOT, 67)],
            ),
        ];

        let root = workspace_root();
        let required = env::var_os("QSOE_ELF_FIXTURES_REQUIRED").is_some();
        let mut checked = 0;

        for (relative, expected) in fixtures {
            let path = root.join(relative);
            let bytes = match fs::read(&path) {
                Ok(bytes) => bytes,
                Err(err) if err.kind() == std::io::ErrorKind::NotFound && !required => {
                    eprintln!("skipping missing ELF fixture: {}", path.display());
                    continue;
                }
                Err(err) => panic!("read {}: {err}", path.display()),
            };

            let elf = ElfFile::parse(&bytes).unwrap_or_else(|err| {
                panic!("parse {}: {err}", path.display());
            });
            assert_eq!(elf.header().machine, super::EM_RISCV, "{relative}");

            let counts = relocation_counts(&elf);
            assert_eq!(counts, *expected, "{relative}");

            let labels: Vec<_> = counts
                .iter()
                .map(|(type_, _)| relocation_type_name(elf.header().machine, *type_))
                .collect();
            assert!(
                labels.iter().all(Option::is_some),
                "unknown relocation type in {relative}: {counts:?}"
            );

            checked += 1;
        }

        if required {
            assert_eq!(
                checked,
                fixtures.len(),
                "required ELF fixtures were not all checked"
            );
        }
    }

    fn relocation_counts(elf: &ElfFile<'_>) -> Vec<(u32, usize)> {
        let mut counts = Vec::new();
        for relocation in elf.relocations() {
            let relocation = relocation.expect("relocation");
            if let Some((_, count)) = counts
                .iter_mut()
                .find(|(type_, _)| *type_ == relocation.type_)
            {
                *count += 1;
            } else {
                counts.push((relocation.type_, 1));
            }
        }
        counts.sort_by_key(|(type_, _)| *type_);
        counts
    }

    fn workspace_root() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .ancestors()
            .nth(3)
            .expect("workspace root")
            .to_path_buf()
    }

    fn synthetic_elf() -> Vec<u8> {
        let mut bytes = vec![0; 320];

        bytes[0..4].copy_from_slice(super::ELF_MAGIC);
        bytes[super::EI_CLASS] = super::ELFCLASS64;
        bytes[super::EI_DATA] = super::ELFDATA2LSB;
        bytes[super::EI_VERSION] = super::EV_CURRENT;
        put_u16(&mut bytes, 16, super::ET_EXEC);
        put_u16(&mut bytes, 18, super::EM_RISCV);
        put_u32(&mut bytes, 20, 1);
        put_u64(&mut bytes, 40, 64);
        put_u16(&mut bytes, 52, super::ELF64_EHDR_LEN as u16);
        put_u16(&mut bytes, 58, super::ELF64_SHDR_LEN as u16);
        put_u16(&mut bytes, 60, 3);

        put_section(
            &mut bytes,
            1,
            TestSection {
                type_: super::SHT_RELA,
                offset: 256,
                size: 48,
                entsize: super::ELF64_RELA_LEN as u64,
            },
        );
        put_section(
            &mut bytes,
            2,
            TestSection {
                type_: super::SHT_REL,
                offset: 304,
                size: 16,
                entsize: super::ELF64_REL_LEN as u64,
            },
        );

        put_rela(&mut bytes, 256, 0x1000, 2, riscv::R_RISCV_64, -4);
        put_rela(&mut bytes, 280, 0x2000, 3, riscv::R_RISCV_JUMP_SLOT, 0);
        put_rel(&mut bytes, 304, 0x3000, 0, riscv::R_RISCV_RELATIVE);

        bytes
    }

    struct TestSection {
        type_: u32,
        offset: u64,
        size: u64,
        entsize: u64,
    }

    fn put_section(bytes: &mut [u8], index: usize, section: TestSection) {
        let offset = super::ELF64_EHDR_LEN + index * super::ELF64_SHDR_LEN;
        put_u32(bytes, offset + 4, section.type_);
        put_u64(bytes, offset + 24, section.offset);
        put_u64(bytes, offset + 32, section.size);
        put_u64(bytes, offset + 56, section.entsize);
    }

    fn put_rel(bytes: &mut [u8], offset: usize, r_offset: u64, symbol: u32, type_: u32) {
        put_u64(bytes, offset, r_offset);
        put_u64(bytes, offset + 8, r_info(symbol, type_));
    }

    fn put_rela(
        bytes: &mut [u8],
        offset: usize,
        r_offset: u64,
        symbol: u32,
        type_: u32,
        addend: i64,
    ) {
        put_rel(bytes, offset, r_offset, symbol, type_);
        bytes[offset + 16..offset + 24].copy_from_slice(&addend.to_le_bytes());
    }

    fn r_info(symbol: u32, type_: u32) -> u64 {
        (u64::from(symbol) << 32) | u64::from(type_)
    }

    fn put_u16(bytes: &mut [u8], offset: usize, value: u16) {
        bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
    }

    fn put_u32(bytes: &mut [u8], offset: usize, value: u32) {
        bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
    }

    fn put_u64(bytes: &mut [u8], offset: usize, value: u64) {
        bytes[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
    }
}
