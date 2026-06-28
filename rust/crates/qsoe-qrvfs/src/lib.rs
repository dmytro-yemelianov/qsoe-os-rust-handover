use std::fmt;
use std::str;

pub const QRVFS_MAGIC: u32 = 0x5152_5631;
pub const QRVFS_VERSION: u32 = 2;
pub const QRVFS_BSIZE: usize = 4096;
pub const QRVFS_ROOTINO: u32 = 1;
pub const QRVFS_T_DIR: u16 = 1;
pub const QRVFS_T_FILE: u16 = 2;
pub const QRVFS_T_SLINK: u16 = 3;
pub const QRVFS_T_DEV: u16 = 4;
pub const QRVFS_NDIRECT: usize = 7;
pub const QRVFS_NINDIRECT: usize = QRVFS_BSIZE / 8;
pub const QRVFS_NINDIRECT2: usize = QRVFS_NINDIRECT * QRVFS_NINDIRECT;
pub const QRVFS_NINDIRECT3: usize = QRVFS_NINDIRECT2 * QRVFS_NINDIRECT;
pub const QRVFS_SINGLE_IDX: usize = QRVFS_NDIRECT;
pub const QRVFS_DOUBLE_IDX: usize = QRVFS_NDIRECT + 1;
pub const QRVFS_TRIPLE_IDX: usize = QRVFS_NDIRECT + 2;
pub const QRVFS_NADDRS: usize = QRVFS_NDIRECT + 3;
pub const QRVFS_MAXFILE: usize =
    QRVFS_NDIRECT + QRVFS_NINDIRECT + QRVFS_NINDIRECT2 + QRVFS_NINDIRECT3;
pub const QRVFS_NAMESIZ: usize = 252;
pub const QRVFS_IPB: u64 = (QRVFS_BSIZE / 128) as u64;
pub const QRVFS_DPB: usize = QRVFS_BSIZE / 256;
pub const QRVFS_BPB: u64 = (QRVFS_BSIZE * 8) as u64;

pub mod writer;

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum Error {
    Truncated { offset: usize, len: usize },
    BadMagic { found: u32 },
    UnsupportedVersion { found: u32 },
    InvalidInode { inum: u32 },
    InvalidUtf8Name,
    ArithmeticOverflow,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Truncated { offset, len } => {
                write!(
                    f,
                    "truncated qrvfs image at offset {offset}, need {len} bytes"
                )
            }
            Self::BadMagic { found } => {
                write!(
                    f,
                    "bad qrvfs magic 0x{found:08x}, expected 0x{QRVFS_MAGIC:08x}"
                )
            }
            Self::UnsupportedVersion { found } => {
                write!(
                    f,
                    "unsupported qrvfs version {found}, expected {QRVFS_VERSION}"
                )
            }
            Self::InvalidInode { inum } => write!(f, "invalid qrvfs inode {inum}"),
            Self::InvalidUtf8Name => write!(f, "qrvfs directory entry name is not UTF-8"),
            Self::ArithmeticOverflow => write!(f, "qrvfs offset arithmetic overflow"),
        }
    }
}

impl std::error::Error for Error {}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub struct Superblock {
    pub magic: u32,
    pub version: u32,
    pub size: u64,
    pub nblocks: u64,
    pub ninodes: u64,
    pub nlog: u64,
    pub logstart: u64,
    pub inodestart: u64,
    pub bmapstart: u64,
    pub datastart: u64,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct Inode {
    pub type_: u16,
    pub nlink: u16,
    pub mode: u32,
    pub uid: u32,
    pub gid: u32,
    pub size: u64,
    pub atime: u64,
    pub mtime: u64,
    pub ctime: u64,
    pub addrs: [u64; QRVFS_NADDRS],
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct TreeEntry {
    pub path: String,
    pub inum: u32,
    pub type_: u16,
    pub mode: u32,
    pub size: u64,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct Inspection {
    pub superblock: Superblock,
    pub entries: Vec<TreeEntry>,
    pub directories: usize,
    pub files: usize,
}

#[derive(Debug, Clone)]
struct DirEntry {
    inum: u32,
    name: String,
}

pub struct Image<'a> {
    bytes: &'a [u8],
    superblock: Superblock,
}

impl<'a> Image<'a> {
    pub fn parse(bytes: &'a [u8]) -> Result<Self> {
        let sb_block = read_at(bytes, QRVFS_BSIZE, 72)?;
        let superblock = parse_superblock(sb_block);

        if superblock.magic != QRVFS_MAGIC {
            return Err(Error::BadMagic {
                found: superblock.magic,
            });
        }
        if superblock.version != QRVFS_VERSION {
            return Err(Error::UnsupportedVersion {
                found: superblock.version,
            });
        }

        Ok(Self { bytes, superblock })
    }

    pub fn superblock(&self) -> Superblock {
        self.superblock
    }

    pub fn read_inode(&self, inum: u32) -> Result<Inode> {
        if u64::from(inum) >= self.superblock.ninodes {
            return Err(Error::InvalidInode { inum });
        }

        let block = u64::from(inum) / QRVFS_IPB + self.superblock.inodestart;
        let index = (u64::from(inum) % QRVFS_IPB) as usize;
        let block = self.read_block(block)?;
        parse_inode(read_at(block, index * 128, 128)?)
    }

    pub fn inspect(&self) -> Result<Inspection> {
        let mut entries = Vec::new();
        let mut directories = 0;
        let mut files = 0;

        self.collect_dir(
            QRVFS_ROOTINO,
            "",
            &mut entries,
            &mut directories,
            &mut files,
        )?;

        Ok(Inspection {
            superblock: self.superblock,
            entries,
            directories,
            files,
        })
    }

    pub fn format_tree(&self, image_path: &str) -> Result<String> {
        let mut output = format!(
            "{}  [qrvfs v{}, {} blocks, {} inodes]\n",
            image_path, self.superblock.version, self.superblock.size, self.superblock.ninodes
        );
        let mut directories = 0;
        let mut files = 0;

        self.format_dir(QRVFS_ROOTINO, "", &mut output, &mut directories, &mut files)?;

        output.push('\n');
        output.push_str(&format!("{directories} directories, {files} files\n"));
        Ok(output)
    }

    fn collect_dir(
        &self,
        inum: u32,
        parent: &str,
        out: &mut Vec<TreeEntry>,
        directories: &mut usize,
        files: &mut usize,
    ) -> Result<()> {
        for entry in self.read_dir_entries(inum)? {
            let child = self.read_inode(entry.inum)?;
            let path = if parent.is_empty() {
                entry.name.clone()
            } else {
                format!("{parent}/{}", entry.name)
            };

            out.push(TreeEntry {
                path: path.clone(),
                inum: entry.inum,
                type_: child.type_,
                mode: child.mode,
                size: child.size,
            });

            if child.type_ == QRVFS_T_DIR {
                *directories += 1;
                self.collect_dir(entry.inum, &path, out, directories, files)?;
            } else {
                *files += 1;
            }
        }

        Ok(())
    }

    fn format_dir(
        &self,
        inum: u32,
        prefix: &str,
        output: &mut String,
        directories: &mut usize,
        files: &mut usize,
    ) -> Result<()> {
        let entries = self.read_dir_entries(inum)?;

        for (i, entry) in entries.iter().enumerate() {
            let child = self.read_inode(entry.inum)?;
            let is_last = i == entries.len() - 1;
            let connector = if is_last {
                "\u{2514}\u{2500}\u{2500} "
            } else {
                "\u{251c}\u{2500}\u{2500} "
            };

            output.push_str(prefix);
            output.push_str(connector);
            output.push_str(&format!(
                "[{} {:>7}]  {}",
                mode_string(child.type_, child.mode),
                child.size,
                entry.name
            ));

            if child.type_ == QRVFS_T_DIR {
                *directories += 1;
                output.push('\n');
                let extension = if is_last { "    " } else { "\u{2502}   " };
                self.format_dir(
                    entry.inum,
                    &format!("{prefix}{extension}"),
                    output,
                    directories,
                    files,
                )?;
            } else {
                *files += 1;
                if child.type_ == QRVFS_T_SLINK {
                    if let Some(target) = self.symlink_target(&child)? {
                        output.push_str(" -> ");
                        output.push_str(&target);
                    }
                }
                output.push('\n');
            }
        }

        Ok(())
    }

    fn read_dir_entries(&self, inum: u32) -> Result<Vec<DirEntry>> {
        let inode = self.read_inode(inum)?;
        if inode.type_ != QRVFS_T_DIR {
            return Ok(Vec::new());
        }

        let mut entries = Vec::new();
        let nblocks = inode.size.div_ceil(QRVFS_BSIZE as u64);

        for b in 0..nblocks.min(QRVFS_NDIRECT as u64) {
            let addr = inode.addrs[b as usize];
            if addr != 0 {
                self.read_dir_block(addr, &mut entries)?;
            }
        }

        if nblocks > QRVFS_NDIRECT as u64 && inode.addrs[QRVFS_SINGLE_IDX] != 0 {
            let indirect = self.read_block(inode.addrs[QRVFS_SINGLE_IDX])?;
            let extra = (nblocks - QRVFS_NDIRECT as u64).min(QRVFS_NINDIRECT as u64);
            for b in 0..extra {
                let offset = b as usize * 8;
                let addr = read_u64(read_at(indirect, offset, 8)?);
                if addr != 0 {
                    self.read_dir_block(addr, &mut entries)?;
                }
            }
        }

        Ok(entries)
    }

    fn read_dir_block(&self, block: u64, entries: &mut Vec<DirEntry>) -> Result<()> {
        let data = self.read_block(block)?;
        for idx in 0..QRVFS_DPB {
            let offset = idx * 256;
            let inum = read_u32(read_at(data, offset, 4)?);
            if inum == 0 {
                continue;
            }

            let name = parse_name(read_at(data, offset + 4, QRVFS_NAMESIZ)?)?;
            if name == "." || name == ".." {
                continue;
            }

            entries.push(DirEntry {
                inum,
                name: name.to_owned(),
            });
        }

        Ok(())
    }

    fn symlink_target(&self, inode: &Inode) -> Result<Option<String>> {
        if inode.addrs[0] == 0 {
            return Ok(None);
        }

        let block = self.read_block(inode.addrs[0])?;
        let len = (inode.size as usize).min(QRVFS_BSIZE.saturating_sub(1));
        let target = str::from_utf8(read_at(block, 0, len)?).map_err(|_| Error::InvalidUtf8Name)?;
        Ok(Some(target.to_owned()))
    }

    fn read_block(&self, block: u64) -> Result<&'a [u8]> {
        let block_usize = usize::try_from(block).map_err(|_| Error::ArithmeticOverflow)?;
        let offset = block_usize
            .checked_mul(QRVFS_BSIZE)
            .ok_or(Error::ArithmeticOverflow)?;
        read_at(self.bytes, offset, QRVFS_BSIZE)
    }
}

pub fn mode_string(type_: u16, mode: u32) -> String {
    let mut out = String::with_capacity(10);
    out.push(match type_ {
        QRVFS_T_DIR => 'd',
        QRVFS_T_SLINK => 'l',
        QRVFS_T_DEV => 'c',
        _ => '-',
    });

    for bit in [
        0o400, 0o200, 0o100, 0o040, 0o020, 0o010, 0o004, 0o002, 0o001,
    ] {
        out.push(match (mode & bit, bit) {
            (0, _) => '-',
            (_, 0o400 | 0o040 | 0o004) => 'r',
            (_, 0o200 | 0o020 | 0o002) => 'w',
            _ => 'x',
        });
    }

    out
}

fn parse_superblock(bytes: &[u8]) -> Superblock {
    Superblock {
        magic: read_u32(&bytes[0..4]),
        version: read_u32(&bytes[4..8]),
        size: read_u64(&bytes[8..16]),
        nblocks: read_u64(&bytes[16..24]),
        ninodes: read_u64(&bytes[24..32]),
        nlog: read_u64(&bytes[32..40]),
        logstart: read_u64(&bytes[40..48]),
        inodestart: read_u64(&bytes[48..56]),
        bmapstart: read_u64(&bytes[56..64]),
        datastart: read_u64(&bytes[64..72]),
    }
}

fn parse_inode(bytes: &[u8]) -> Result<Inode> {
    let mut addrs = [0; QRVFS_NADDRS];
    for (idx, addr) in addrs.iter_mut().enumerate() {
        let offset = 48 + idx * 8;
        *addr = read_u64(read_at(bytes, offset, 8)?);
    }

    Ok(Inode {
        type_: read_u16(read_at(bytes, 0, 2)?),
        nlink: read_u16(read_at(bytes, 2, 2)?),
        mode: read_u32(read_at(bytes, 4, 4)?),
        uid: read_u32(read_at(bytes, 8, 4)?),
        gid: read_u32(read_at(bytes, 12, 4)?),
        size: read_u64(read_at(bytes, 16, 8)?),
        atime: read_u64(read_at(bytes, 24, 8)?),
        mtime: read_u64(read_at(bytes, 32, 8)?),
        ctime: read_u64(read_at(bytes, 40, 8)?),
        addrs,
    })
}

fn parse_name(bytes: &[u8]) -> Result<&str> {
    let len = bytes.iter().position(|b| *b == 0).unwrap_or(bytes.len());
    str::from_utf8(&bytes[..len]).map_err(|_| Error::InvalidUtf8Name)
}

fn read_at(bytes: &[u8], offset: usize, len: usize) -> Result<&[u8]> {
    let end = offset.checked_add(len).ok_or(Error::ArithmeticOverflow)?;
    bytes
        .get(offset..end)
        .ok_or(Error::Truncated { offset, len })
}

fn read_u16(bytes: &[u8]) -> u16 {
    u16::from_le_bytes(bytes.try_into().expect("u16 slice length"))
}

fn read_u32(bytes: &[u8]) -> u32 {
    u32::from_le_bytes(bytes.try_into().expect("u32 slice length"))
}

fn read_u64(bytes: &[u8]) -> u64 {
    u64::from_le_bytes(bytes.try_into().expect("u64 slice length"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_minimal_image() {
        let image = minimal_image();
        let qrvfs = Image::parse(&image).expect("parse qrvfs");
        let inspection = qrvfs.inspect().expect("inspect qrvfs");

        assert_eq!(inspection.superblock.version, QRVFS_VERSION);
        assert_eq!(inspection.superblock.size, 8);
        assert_eq!(inspection.superblock.ninodes, 8);
        assert_eq!(inspection.directories, 0);
        assert_eq!(inspection.files, 1);
        assert_eq!(inspection.entries.len(), 1);
        assert_eq!(inspection.entries[0].path, "hello");
        assert_eq!(inspection.entries[0].size, 5);
    }

    #[test]
    fn formats_treeqrvfs_style_output() {
        let image = minimal_image();
        let qrvfs = Image::parse(&image).expect("parse qrvfs");
        let tree = qrvfs.format_tree("fixture.img").expect("format tree");

        assert_eq!(
            tree,
            concat!(
                "fixture.img  [qrvfs v2, 8 blocks, 8 inodes]\n",
                "\u{2514}\u{2500}\u{2500} [-rw-r--r--       5]  hello\n",
                "\n",
                "0 directories, 1 files\n",
            )
        );
    }

    fn minimal_image() -> Vec<u8> {
        let mut image = vec![0; QRVFS_BSIZE * 8];

        put_u32(&mut image, QRVFS_BSIZE, QRVFS_MAGIC);
        put_u32(&mut image, QRVFS_BSIZE + 4, QRVFS_VERSION);
        put_u64(&mut image, QRVFS_BSIZE + 8, 8);
        put_u64(&mut image, QRVFS_BSIZE + 16, 3);
        put_u64(&mut image, QRVFS_BSIZE + 24, 8);
        put_u64(&mut image, QRVFS_BSIZE + 32, 0);
        put_u64(&mut image, QRVFS_BSIZE + 40, 2);
        put_u64(&mut image, QRVFS_BSIZE + 48, 2);
        put_u64(&mut image, QRVFS_BSIZE + 56, 3);
        put_u64(&mut image, QRVFS_BSIZE + 64, 4);

        write_inode(
            &mut image,
            1,
            TestInode {
                type_: QRVFS_T_DIR,
                nlink: 1,
                mode: 0o755,
                size: 3 * 256,
                addrs: [4, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            },
        );
        write_inode(
            &mut image,
            2,
            TestInode {
                type_: 2,
                nlink: 1,
                mode: 0o644,
                size: 5,
                addrs: [5, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            },
        );

        write_dirent(&mut image, 4, 0, 1, ".");
        write_dirent(&mut image, 4, 1, 1, "..");
        write_dirent(&mut image, 4, 2, 2, "hello");

        image
    }

    struct TestInode {
        type_: u16,
        nlink: u16,
        mode: u32,
        size: u64,
        addrs: [u64; QRVFS_NADDRS],
    }

    fn write_inode(image: &mut [u8], inum: u32, inode: TestInode) {
        let offset = QRVFS_BSIZE * 2 + inum as usize * 128;
        put_u16(image, offset, inode.type_);
        put_u16(image, offset + 2, inode.nlink);
        put_u32(image, offset + 4, inode.mode);
        put_u64(image, offset + 16, inode.size);
        for (idx, addr) in inode.addrs.iter().enumerate() {
            put_u64(image, offset + 48 + idx * 8, *addr);
        }
    }

    fn write_dirent(image: &mut [u8], block: usize, index: usize, inum: u32, name: &str) {
        let offset = QRVFS_BSIZE * block + index * 256;
        put_u32(image, offset, inum);
        image[offset + 4..offset + 4 + name.len()].copy_from_slice(name.as_bytes());
    }

    fn put_u16(image: &mut [u8], offset: usize, value: u16) {
        image[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
    }

    fn put_u32(image: &mut [u8], offset: usize, value: u32) {
        image[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
    }

    fn put_u64(image: &mut [u8], offset: usize, value: u64) {
        image[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
    }
}
