#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(elf) = qsoe_elf::ElfFile::parse(data) {
        let _ = elf.header();

        for section in elf.sections().take(32) {
            if let Ok(section) = section {
                if section.is_relocation() {
                    if let Ok(entries) = elf.relocation_entries(section) {
                        for relocation in entries.take(32) {
                            let _ = relocation;
                        }
                    }
                }
            }
        }

        for relocation in elf.relocations().take(64) {
            let _ = relocation;
        }
    }
});
