#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(page) = qsoe_sysview::sysmap::Page::parse(data) {
        let _ = page.header();
        let _ = page.raminfo();
        let _ = page.initrd();
        let _ = page.mtime_hz();
        let _ = page.cmdline();

        for tlv in page.tlvs().take(32) {
            if let Ok(tlv) = tlv {
                let _ = tlv.u32_at(0, "fuzz sysmap u32");
                let _ = tlv.u64_at(0, "fuzz sysmap u64");
                let _ = tlv.range("fuzz sysmap range");
                let _ = tlv.cstr("fuzz sysmap string");
            }
        }
    }
});
