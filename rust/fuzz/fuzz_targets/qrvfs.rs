#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(image) = qsoe_qrvfs::Image::parse(data) {
        let superblock = image.superblock();
        let _ = image.read_inode(qsoe_qrvfs::QRVFS_ROOTINO);

        if superblock.ninodes > 2 {
            let _ = image.read_inode(2);
        }
    }
});
