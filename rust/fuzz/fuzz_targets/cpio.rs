#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(archive) = qsoe_cpio::Archive::parse(data) {
        let _ = archive.info();
        let _ = archive.entry(0);
        let _ = archive.file("sbin/init");
    }
});
