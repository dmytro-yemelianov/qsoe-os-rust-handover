#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(blob) = qsoe_sysview::syscfg::Blob::parse(data) {
        let _ = blob.find_u32(qsoe_sysview::syscfg::TAG_VERSION);
        let _ = blob.find_cstr(qsoe_sysview::syscfg::TAG_CMDLINE, "fuzz cmdline");

        for tag in blob.tags().take(32) {
            if let Ok(tag) = tag {
                let _ = tag.u32("fuzz syscfg u32");
                let _ = tag.u64("fuzz syscfg u64");
                let _ = tag.cstr("fuzz syscfg string");
            }
        }
    }
});
