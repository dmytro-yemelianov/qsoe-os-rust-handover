use std::fmt;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Seek, SeekFrom, Write};
use std::os::raw::{c_int, c_ulong};
use std::os::unix::fs::{FileTypeExt, PermissionsExt};
use std::os::unix::io::AsRawFd;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::{
    QRVFS_BPB, QRVFS_BSIZE, QRVFS_DOUBLE_IDX, QRVFS_IPB, QRVFS_MAGIC, QRVFS_NADDRS, QRVFS_NAMESIZ,
    QRVFS_NDIRECT, QRVFS_NINDIRECT, QRVFS_NINDIRECT2, QRVFS_NINDIRECT3, QRVFS_ROOTINO,
    QRVFS_SINGLE_IDX, QRVFS_TRIPLE_IDX, QRVFS_T_DIR, QRVFS_T_FILE, QRVFS_VERSION,
};

pub const DEFAULT_SIZE_MB: u64 = 8;
pub const DEFAULT_NINODES: u64 = 128;
const DEFAULT_NLOG: u64 = 0;
const INODE_SIZE: usize = 128;
const DIRENT_SIZE: usize = 256;
const SUPERBLOCK_SIZE: usize = 72;

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub struct WriterConfig {
    pub size_mb: u64,
    pub ninodes: u64,
}

impl Default for WriterConfig {
    fn default() -> Self {
        Self {
            size_mb: DEFAULT_SIZE_MB,
            ninodes: DEFAULT_NINODES,
        }
    }
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub struct Layout {
    pub total_blocks: u64,
    pub data_blocks: u64,
    pub ninodes: u64,
    pub nlog: u64,
    pub logstart: u64,
    pub inodestart: u64,
    pub bmapstart: u64,
    pub datastart: u64,
    pub ninode_blocks: u64,
    pub nbmap_blocks: u64,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct BuiltImage {
    pub bytes: Vec<u8>,
    pub layout: Layout,
    pub root_inode: u32,
    pub data_blocks_used: u64,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct TargetWriteReport {
    pub initialization: TargetInitialization,
    pub initialized_bytes: u64,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum TargetInitialization {
    SparseFile { total_bytes: u64 },
    BlockZeroOut { metadata_bytes: u64 },
    BlockZeroOutFallback { error: String, metadata_blocks: u64 },
}

#[derive(Debug)]
pub enum WriteError {
    Io(io::Error),
    InvalidConfig(&'static str),
    ImageTooLarge,
    OutOfInodes,
    OutOfBlocks,
    FileTooLarge,
    NameTooLong { name: String, len: usize },
    NonUtf8Name,
    ArithmeticOverflow,
}

impl fmt::Display for WriteError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(err) => write!(f, "{err}"),
            Self::InvalidConfig(msg) => write!(f, "invalid qrvfs writer config: {msg}"),
            Self::ImageTooLarge => write!(f, "qrvfs image is too large for this host"),
            Self::OutOfInodes => write!(f, "qrvfs image ran out of inodes"),
            Self::OutOfBlocks => write!(f, "qrvfs image ran out of data blocks"),
            Self::FileTooLarge => write!(f, "qrvfs file exceeds writer support"),
            Self::NameTooLong { name, len } => write!(
                f,
                "qrvfs name '{name}' ({len} bytes) exceeds QRVFS_NAMESIZ-1 ({})",
                QRVFS_NAMESIZ - 1
            ),
            Self::NonUtf8Name => write!(f, "qrvfs writer requires UTF-8 host names"),
            Self::ArithmeticOverflow => write!(f, "qrvfs writer offset arithmetic overflow"),
        }
    }
}

impl std::error::Error for WriteError {}

impl From<io::Error> for WriteError {
    fn from(err: io::Error) -> Self {
        Self::Io(err)
    }
}

pub type WriteResult<T> = Result<T, WriteError>;

pub fn build_image(populate_dir: Option<&Path>, config: WriterConfig) -> WriteResult<BuiltImage> {
    Writer::new(config)?.finish(populate_dir)
}

pub fn write_image_to_path(path: &Path, built: &BuiltImage) -> WriteResult<TargetWriteReport> {
    let total_bytes = block_count_bytes(built.layout.total_blocks)?;
    let metadata_bytes = block_count_bytes(built.layout.datastart)?;
    let initialized_blocks = built
        .layout
        .datastart
        .checked_add(built.data_blocks_used)
        .ok_or(WriteError::ArithmeticOverflow)?;
    let initialized_bytes = block_count_bytes(initialized_blocks)?;
    let initialized_len =
        usize::try_from(initialized_bytes).map_err(|_| WriteError::ImageTooLarge)?;

    if initialized_len > built.bytes.len() {
        return Err(WriteError::InvalidConfig(
            "initialized byte range exceeds image",
        ));
    }

    let mut file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(path)?;
    let file_type = file.metadata()?.file_type();
    let initialization = if file_type.is_block_device() {
        initialize_block_device_target(&mut file, metadata_bytes, built.layout.datastart)?
    } else {
        file.set_len(0)?;
        file.set_len(total_bytes)?;
        TargetInitialization::SparseFile { total_bytes }
    };

    file.seek(SeekFrom::Start(0))?;
    file.write_all(&built.bytes[..initialized_len])?;

    Ok(TargetWriteReport {
        initialization,
        initialized_bytes,
    })
}

#[derive(Debug, Clone, Eq, PartialEq)]
struct Dinode {
    type_: u16,
    nlink: u16,
    mode: u32,
    uid: u32,
    gid: u32,
    size: u64,
    atime: u64,
    mtime: u64,
    ctime: u64,
    addrs: [u64; QRVFS_NADDRS],
}

struct Writer {
    image: Vec<u8>,
    layout: Layout,
    free_inode: u32,
    free_block: u64,
    now: u64,
}

impl Writer {
    fn new(config: WriterConfig) -> WriteResult<Self> {
        if config.size_mb == 0 {
            return Err(WriteError::InvalidConfig("size_mb must be non-zero"));
        }
        if config.ninodes <= u64::from(QRVFS_ROOTINO) {
            return Err(WriteError::InvalidConfig(
                "ninodes must leave room for root inode",
            ));
        }

        let total_blocks = config
            .size_mb
            .checked_mul(1024 * 1024 / QRVFS_BSIZE as u64)
            .ok_or(WriteError::ArithmeticOverflow)?;
        let ninode_blocks = config.ninodes.div_ceil(QRVFS_IPB);
        let nbmap_blocks = total_blocks.div_ceil(QRVFS_BPB);
        let logstart = 2;
        let inodestart = logstart + DEFAULT_NLOG;
        let bmapstart = inodestart + ninode_blocks;
        let datastart = bmapstart + nbmap_blocks;
        if datastart >= total_blocks {
            return Err(WriteError::InvalidConfig("metadata consumes image"));
        }

        let image_len = usize::try_from(total_blocks)
            .ok()
            .and_then(|blocks| blocks.checked_mul(QRVFS_BSIZE))
            .ok_or(WriteError::ImageTooLarge)?;
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        Ok(Self {
            image: vec![0; image_len],
            layout: Layout {
                total_blocks,
                data_blocks: total_blocks - datastart,
                ninodes: config.ninodes,
                nlog: DEFAULT_NLOG,
                logstart,
                inodestart,
                bmapstart,
                datastart,
                ninode_blocks,
                nbmap_blocks,
            },
            free_inode: QRVFS_ROOTINO,
            free_block: datastart,
            now,
        })
    }

    fn finish(mut self, populate_dir: Option<&Path>) -> WriteResult<BuiltImage> {
        self.write_superblock()?;
        for block in 0..self.layout.datastart {
            self.mark_block(block)?;
        }

        let root_inode = self.alloc_inode(QRVFS_T_DIR, 0o755)?;
        if root_inode != QRVFS_ROOTINO {
            return Err(WriteError::InvalidConfig("root inode allocation drifted"));
        }

        self.add_dirent(root_inode, root_inode, ".")?;
        self.add_dirent(root_inode, root_inode, "..")?;
        let mut root = self.read_inode(root_inode)?;
        root.nlink = 2;
        self.write_inode(root_inode, &root)?;

        if let Some(dir) = populate_dir {
            self.populate(root_inode, dir)?;
        }

        let data_blocks_used = self
            .free_block
            .checked_sub(self.layout.datastart)
            .ok_or(WriteError::ArithmeticOverflow)?;
        Ok(BuiltImage {
            bytes: self.image,
            layout: self.layout,
            root_inode,
            data_blocks_used,
        })
    }

    fn populate(&mut self, parent_inum: u32, hostdir: &Path) -> WriteResult<()> {
        let mut entries = fs::read_dir(hostdir)?.collect::<Result<Vec<_>, io::Error>>()?;
        entries.sort_by_key(|entry| entry.file_name());

        for entry in entries {
            let path = entry.path();
            let metadata = fs::symlink_metadata(&path)?;
            let file_type = metadata.file_type();
            if !file_type.is_file() && !file_type.is_dir() {
                continue;
            }

            let name = entry
                .file_name()
                .into_string()
                .map_err(|_| WriteError::NonUtf8Name)?;
            let mode = metadata.permissions().mode() & 0o7777;
            if file_type.is_dir() {
                self.add_directory(parent_inum, &path, &name, mode)?;
            } else {
                self.add_regular_file(parent_inum, &path, &name, mode)?;
            }
        }

        Ok(())
    }

    fn add_directory(
        &mut self,
        parent_inum: u32,
        hostpath: &Path,
        name: &str,
        mode: u32,
    ) -> WriteResult<()> {
        let inum = self.alloc_inode(QRVFS_T_DIR, mode)?;
        self.add_dirent(parent_inum, inum, name)?;
        self.add_dirent(inum, inum, ".")?;
        self.add_dirent(inum, parent_inum, "..")?;

        let mut child = self.read_inode(inum)?;
        child.nlink = 2;
        self.write_inode(inum, &child)?;

        let mut parent = self.read_inode(parent_inum)?;
        parent.nlink = parent
            .nlink
            .checked_add(1)
            .ok_or(WriteError::ArithmeticOverflow)?;
        self.write_inode(parent_inum, &parent)?;

        self.populate(inum, hostpath)
    }

    fn add_regular_file(
        &mut self,
        parent_inum: u32,
        hostpath: &Path,
        name: &str,
        mode: u32,
    ) -> WriteResult<()> {
        let inum = self.alloc_inode(QRVFS_T_FILE, mode)?;
        self.add_dirent(parent_inum, inum, name)?;
        let data = fs::read(hostpath)?;
        self.iappend(inum, &data)
    }

    fn alloc_inode(&mut self, type_: u16, mode: u32) -> WriteResult<u32> {
        if u64::from(self.free_inode) >= self.layout.ninodes {
            return Err(WriteError::OutOfInodes);
        }

        let inum = self.free_inode;
        self.free_inode = self
            .free_inode
            .checked_add(1)
            .ok_or(WriteError::ArithmeticOverflow)?;
        self.write_inode(
            inum,
            &Dinode {
                type_,
                nlink: 1,
                mode,
                uid: 0,
                gid: 0,
                size: 0,
                atime: self.now,
                mtime: self.now,
                ctime: self.now,
                addrs: [0; QRVFS_NADDRS],
            },
        )?;
        Ok(inum)
    }

    fn add_dirent(&mut self, parent_inum: u32, child_inum: u32, name: &str) -> WriteResult<()> {
        let name_bytes = name.as_bytes();
        if name_bytes.len() >= QRVFS_NAMESIZ {
            return Err(WriteError::NameTooLong {
                name: name.to_owned(),
                len: name_bytes.len(),
            });
        }

        let mut dirent = [0; DIRENT_SIZE];
        dirent[0..4].copy_from_slice(&child_inum.to_le_bytes());
        dirent[4..4 + name_bytes.len()].copy_from_slice(name_bytes);
        self.iappend(parent_inum, &dirent)
    }

    fn iappend(&mut self, inum: u32, data: &[u8]) -> WriteResult<()> {
        let mut inode = self.read_inode(inum)?;
        let mut off = usize::try_from(inode.size).map_err(|_| WriteError::ImageTooLarge)?;
        let mut pos = 0;

        while pos < data.len() {
            let fbn = off / QRVFS_BSIZE;
            let bno = self.data_block_for(&mut inode, fbn)?;
            let boff = off % QRVFS_BSIZE;
            let chunk = (QRVFS_BSIZE - boff).min(data.len() - pos);
            let dst = self.block_offset(bno)? + boff;
            self.image[dst..dst + chunk].copy_from_slice(&data[pos..pos + chunk]);
            off += chunk;
            pos += chunk;
        }

        inode.size = u64::try_from(off).map_err(|_| WriteError::ImageTooLarge)?;
        self.write_inode(inum, &inode)
    }

    fn data_block_for(&mut self, inode: &mut Dinode, fbn: usize) -> WriteResult<u64> {
        if fbn < QRVFS_NDIRECT {
            return self.walk_indirect(&mut inode.addrs[fbn], 0, 0);
        }

        let fbn = fbn - QRVFS_NDIRECT;
        if fbn < QRVFS_NINDIRECT {
            return self.walk_indirect(&mut inode.addrs[QRVFS_SINGLE_IDX], 1, fbn);
        }

        let fbn = fbn - QRVFS_NINDIRECT;
        if fbn < QRVFS_NINDIRECT2 {
            return self.walk_indirect(&mut inode.addrs[QRVFS_DOUBLE_IDX], 2, fbn);
        }

        let fbn = fbn - QRVFS_NINDIRECT2;
        if fbn < QRVFS_NINDIRECT3 {
            return self.walk_indirect(&mut inode.addrs[QRVFS_TRIPLE_IDX], 3, fbn);
        }

        Err(WriteError::FileTooLarge)
    }

    fn walk_indirect(&mut self, slot: &mut u64, level: usize, fbn: usize) -> WriteResult<u64> {
        if *slot == 0 {
            *slot = self.alloc_block()?;
        }

        if level == 0 {
            return Ok(*slot);
        }

        let fanout = (0..(level - 1)).fold(1usize, |acc, _| acc * QRVFS_NINDIRECT);
        let idx = fbn / fanout;
        if idx >= QRVFS_NINDIRECT {
            return Err(WriteError::FileTooLarge);
        }
        let rem = fbn % fanout;
        let child_offset = self.block_offset(*slot)? + idx * 8;
        let mut child_slot = read_u64(&self.image[child_offset..child_offset + 8]);
        let data_block = self.walk_indirect(&mut child_slot, level - 1, rem)?;
        self.image[child_offset..child_offset + 8].copy_from_slice(&child_slot.to_le_bytes());
        Ok(data_block)
    }

    fn alloc_block(&mut self) -> WriteResult<u64> {
        if self.free_block >= self.layout.total_blocks {
            return Err(WriteError::OutOfBlocks);
        }
        let block = self.free_block;
        self.free_block = self
            .free_block
            .checked_add(1)
            .ok_or(WriteError::ArithmeticOverflow)?;
        self.mark_block(block)?;
        Ok(block)
    }

    fn mark_block(&mut self, block: u64) -> WriteResult<()> {
        let bitmap_block = block / QRVFS_BPB + self.layout.bmapstart;
        let bitmap_offset = self.block_offset(bitmap_block)?;
        let bit = block % QRVFS_BPB;
        let byte_offset = bitmap_offset + (bit / 8) as usize;
        let bit_mask = 1u8 << (bit % 8);
        self.image[byte_offset] |= bit_mask;
        Ok(())
    }

    fn write_superblock(&mut self) -> WriteResult<()> {
        let offset = QRVFS_BSIZE;
        self.image[offset..offset + SUPERBLOCK_SIZE].fill(0);
        put_u32(&mut self.image, offset, QRVFS_MAGIC);
        put_u32(&mut self.image, offset + 4, QRVFS_VERSION);
        put_u64(&mut self.image, offset + 8, self.layout.total_blocks);
        put_u64(&mut self.image, offset + 16, self.layout.data_blocks);
        put_u64(&mut self.image, offset + 24, self.layout.ninodes);
        put_u64(&mut self.image, offset + 32, self.layout.nlog);
        put_u64(&mut self.image, offset + 40, self.layout.logstart);
        put_u64(&mut self.image, offset + 48, self.layout.inodestart);
        put_u64(&mut self.image, offset + 56, self.layout.bmapstart);
        put_u64(&mut self.image, offset + 64, self.layout.datastart);
        Ok(())
    }

    fn read_inode(&self, inum: u32) -> WriteResult<Dinode> {
        let offset = self.inode_offset(inum)?;
        let mut addrs = [0; QRVFS_NADDRS];
        for (idx, addr) in addrs.iter_mut().enumerate() {
            let start = offset + 48 + idx * 8;
            *addr = read_u64(&self.image[start..start + 8]);
        }

        Ok(Dinode {
            type_: read_u16(&self.image[offset..offset + 2]),
            nlink: read_u16(&self.image[offset + 2..offset + 4]),
            mode: read_u32(&self.image[offset + 4..offset + 8]),
            uid: read_u32(&self.image[offset + 8..offset + 12]),
            gid: read_u32(&self.image[offset + 12..offset + 16]),
            size: read_u64(&self.image[offset + 16..offset + 24]),
            atime: read_u64(&self.image[offset + 24..offset + 32]),
            mtime: read_u64(&self.image[offset + 32..offset + 40]),
            ctime: read_u64(&self.image[offset + 40..offset + 48]),
            addrs,
        })
    }

    fn write_inode(&mut self, inum: u32, inode: &Dinode) -> WriteResult<()> {
        let offset = self.inode_offset(inum)?;
        self.image[offset..offset + INODE_SIZE].fill(0);
        put_u16(&mut self.image, offset, inode.type_);
        put_u16(&mut self.image, offset + 2, inode.nlink);
        put_u32(&mut self.image, offset + 4, inode.mode);
        put_u32(&mut self.image, offset + 8, inode.uid);
        put_u32(&mut self.image, offset + 12, inode.gid);
        put_u64(&mut self.image, offset + 16, inode.size);
        put_u64(&mut self.image, offset + 24, inode.atime);
        put_u64(&mut self.image, offset + 32, inode.mtime);
        put_u64(&mut self.image, offset + 40, inode.ctime);
        for (idx, addr) in inode.addrs.iter().enumerate() {
            put_u64(&mut self.image, offset + 48 + idx * 8, *addr);
        }
        Ok(())
    }

    fn inode_offset(&self, inum: u32) -> WriteResult<usize> {
        if u64::from(inum) >= self.layout.ninodes {
            return Err(WriteError::OutOfInodes);
        }

        let block = u64::from(inum) / QRVFS_IPB + self.layout.inodestart;
        let index = (u64::from(inum) % QRVFS_IPB) as usize;
        self.block_offset(block)?
            .checked_add(index * INODE_SIZE)
            .ok_or(WriteError::ArithmeticOverflow)
    }

    fn block_offset(&self, block: u64) -> WriteResult<usize> {
        if block >= self.layout.total_blocks {
            return Err(WriteError::OutOfBlocks);
        }
        usize::try_from(block)
            .ok()
            .and_then(|block| block.checked_mul(QRVFS_BSIZE))
            .ok_or(WriteError::ArithmeticOverflow)
    }
}

fn initialize_block_device_target(
    file: &mut File,
    metadata_bytes: u64,
    metadata_blocks: u64,
) -> WriteResult<TargetInitialization> {
    match blkzeroout_metadata(file, metadata_bytes) {
        Ok(()) => Ok(TargetInitialization::BlockZeroOut { metadata_bytes }),
        Err(err) => {
            let error = err.to_string();
            write_zero_blocks(file, metadata_blocks)?;
            Ok(TargetInitialization::BlockZeroOutFallback {
                error,
                metadata_blocks,
            })
        }
    }
}

#[cfg(target_os = "linux")]
fn blkzeroout_metadata(file: &File, metadata_bytes: u64) -> io::Result<()> {
    const BLKZEROOUT: c_ulong = 0x127f;

    extern "C" {
        fn ioctl(fd: c_int, request: c_ulong, ...) -> c_int;
    }

    let mut range = [0_u64, metadata_bytes];
    // SAFETY: BLKZEROOUT expects a valid file descriptor and a pointer to two
    // u64 values: byte offset and byte length. Both live for the ioctl call.
    let rc = unsafe { ioctl(file.as_raw_fd(), BLKZEROOUT, range.as_mut_ptr()) };
    if rc == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

#[cfg(not(target_os = "linux"))]
fn blkzeroout_metadata(_file: &File, _metadata_bytes: u64) -> io::Result<()> {
    Err(io::Error::new(
        io::ErrorKind::Unsupported,
        "BLKZEROOUT is only available on Linux",
    ))
}

fn write_zero_blocks(file: &mut File, blocks: u64) -> io::Result<()> {
    let zeroes = [0_u8; QRVFS_BSIZE];
    file.seek(SeekFrom::Start(0))?;
    for _ in 0..blocks {
        file.write_all(&zeroes)?;
    }
    Ok(())
}

fn block_count_bytes(blocks: u64) -> WriteResult<u64> {
    blocks
        .checked_mul(QRVFS_BSIZE as u64)
        .ok_or(WriteError::ArithmeticOverflow)
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
    use std::collections::BTreeSet;

    use super::*;
    use crate::Image;

    #[test]
    fn builds_fixture_image_readable_by_parser() {
        let root = temp_fixture_dir();
        fs::create_dir_all(root.join("bin")).expect("bin dir");
        fs::create_dir_all(root.join("conf")).expect("conf dir");
        fs::create_dir_all(root.join("home/user")).expect("home dir");
        fs::write(root.join("bin/hello"), b"hello from rust qrvfs\n").expect("hello");
        fs::write(
            root.join("conf/passwd"),
            b"root:x:0:0:root:/root:/bin/qsh\n",
        )
        .expect("passwd");
        fs::write(root.join("home/user/profile"), b"PATH=/bin:/sbin\n").expect("profile");

        let built = build_image(
            Some(&root),
            WriterConfig {
                size_mb: 2,
                ninodes: 64,
            },
        )
        .expect("build image");
        let image = Image::parse(&built.bytes).expect("parse generated image");
        let inspection = image.inspect().expect("inspect generated image");
        let paths = inspection
            .entries
            .iter()
            .map(|entry| entry.path.as_str())
            .collect::<BTreeSet<_>>();

        assert_eq!(inspection.superblock.size, 512);
        assert_eq!(inspection.superblock.ninodes, 64);
        assert_eq!(inspection.directories, 4);
        assert_eq!(inspection.files, 3);
        assert!(paths.contains("bin/hello"));
        assert!(paths.contains("conf/passwd"));
        assert!(paths.contains("home/user/profile"));
        assert_eq!(built.root_inode, QRVFS_ROOTINO);
        assert!(built.data_blocks_used >= 7);

        fs::remove_dir_all(root).expect("remove fixture");
    }

    #[test]
    fn rejects_overlong_names() {
        let root = temp_fixture_dir();
        fs::create_dir_all(&root).expect("root dir");
        let long_name = "x".repeat(QRVFS_NAMESIZ);
        fs::write(root.join(long_name), b"too long").expect("long file");

        let err = build_image(
            Some(&root),
            WriterConfig {
                size_mb: 2,
                ninodes: 64,
            },
        )
        .expect_err("long name must fail");

        assert!(matches!(err, WriteError::NameTooLong { .. }));
        fs::remove_dir_all(root).expect("remove fixture");
    }

    #[test]
    fn writes_files_past_single_indirect() {
        let root = temp_fixture_dir();
        fs::create_dir_all(&root).expect("root dir");
        let large_len = (QRVFS_NDIRECT + QRVFS_NINDIRECT + 3) * QRVFS_BSIZE + 123;
        let large = patterned_bytes(large_len);
        fs::write(root.join("large.bin"), &large).expect("large file");

        let built = build_image(
            Some(&root),
            WriterConfig {
                size_mb: 4,
                ninodes: 64,
            },
        )
        .expect("build large image");
        let image = Image::parse(&built.bytes).expect("parse generated image");
        let inspection = image.inspect().expect("inspect generated image");
        let entry = inspection
            .entries
            .iter()
            .find(|entry| entry.path == "large.bin")
            .expect("large entry");
        let inode = image.read_inode(entry.inum).expect("large inode");

        assert_eq!(entry.size, large_len as u64);
        assert_ne!(inode.addrs[QRVFS_SINGLE_IDX], 0);
        assert_ne!(inode.addrs[QRVFS_DOUBLE_IDX], 0);

        for fbn in [
            0,
            QRVFS_NDIRECT,
            QRVFS_NDIRECT + QRVFS_NINDIRECT,
            QRVFS_NDIRECT + QRVFS_NINDIRECT + 2,
            large_len / QRVFS_BSIZE,
        ] {
            let expected_start = fbn * QRVFS_BSIZE;
            let expected_end = (expected_start + QRVFS_BSIZE).min(large.len());
            let block = logical_block(&built.bytes, &inode, fbn);
            assert_eq!(
                &block[..expected_end - expected_start],
                &large[expected_start..expected_end]
            );
        }

        fs::remove_dir_all(root).expect("remove fixture");
    }

    #[test]
    fn writes_sparse_regular_target_over_stale_file() {
        let root = temp_fixture_dir();
        fs::create_dir_all(&root).expect("root dir");
        fs::write(root.join("hello"), b"hello\n").expect("hello");

        let built = build_image(
            Some(&root),
            WriterConfig {
                size_mb: 2,
                ninodes: 64,
            },
        )
        .expect("build image");

        let image_path = root.join("stale.img");
        fs::write(&image_path, vec![0xa5; 3 * 1024 * 1024]).expect("stale image");
        let report = write_image_to_path(&image_path, &built).expect("write target");
        assert_eq!(
            report.initialization,
            TargetInitialization::SparseFile {
                total_bytes: built.layout.total_blocks * QRVFS_BSIZE as u64,
            }
        );

        let written = fs::read(&image_path).expect("read image");
        assert_eq!(written.len(), QRVFS_BSIZE * 512);
        let initialized_len = usize::try_from(report.initialized_bytes).expect("initialized len");
        assert_eq!(&written[..initialized_len], &built.bytes[..initialized_len]);
        assert!(written[initialized_len..].iter().all(|byte| *byte == 0));
        Image::parse(&written).expect("parse written image");

        fs::remove_dir_all(root).expect("remove fixture");
    }

    fn patterned_bytes(len: usize) -> Vec<u8> {
        (0..len)
            .map(|idx| ((idx / QRVFS_BSIZE + idx % 251) & 0xff) as u8)
            .collect()
    }

    fn logical_block<'a>(image: &'a [u8], inode: &crate::Inode, fbn: usize) -> &'a [u8] {
        let bno = logical_block_number(image, inode, fbn);
        block(image, bno)
    }

    fn logical_block_number(image: &[u8], inode: &crate::Inode, fbn: usize) -> u64 {
        if fbn < QRVFS_NDIRECT {
            return inode.addrs[fbn];
        }

        let fbn = fbn - QRVFS_NDIRECT;
        if fbn < QRVFS_NINDIRECT {
            return read_index_block(image, inode.addrs[QRVFS_SINGLE_IDX], fbn);
        }

        let fbn = fbn - QRVFS_NINDIRECT;
        let level1 = read_index_block(image, inode.addrs[QRVFS_DOUBLE_IDX], fbn / QRVFS_NINDIRECT);
        read_index_block(image, level1, fbn % QRVFS_NINDIRECT)
    }

    fn read_index_block(image: &[u8], bno: u64, idx: usize) -> u64 {
        let bytes = block(image, bno);
        read_u64(&bytes[idx * 8..idx * 8 + 8])
    }

    fn block(image: &[u8], bno: u64) -> &[u8] {
        let offset = bno as usize * QRVFS_BSIZE;
        &image[offset..offset + QRVFS_BSIZE]
    }

    fn temp_fixture_dir() -> std::path::PathBuf {
        let mut path = std::env::temp_dir();
        path.push(format!(
            "qsoe-qrvfs-writer-test-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        ));
        path
    }
}
