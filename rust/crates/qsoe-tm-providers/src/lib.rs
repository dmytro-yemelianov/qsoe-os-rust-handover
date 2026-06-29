#![no_std]

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    loop {
        core::hint::spin_loop();
    }
}

#[no_mangle]
pub extern "C" fn qsoe_tm_providers_archive_anchor() -> usize {
    #[cfg(not(any(
        feature = "tm-cpio",
        feature = "tm-cred",
        feature = "tm-elf",
        feature = "tm-fdt",
        feature = "tm-pathmgr",
        feature = "tm-procfs",
        feature = "tm-pseudodev",
        feature = "tm-rsrcdb",
        feature = "tm-script",
        feature = "tm-syscfg",
        feature = "tm-sysfs",
        feature = "tm-sysmap",
    )))]
    {
        0
    }

    #[cfg(any(
        feature = "tm-cpio",
        feature = "tm-cred",
        feature = "tm-elf",
        feature = "tm-fdt",
        feature = "tm-pathmgr",
        feature = "tm-procfs",
        feature = "tm-pseudodev",
        feature = "tm-rsrcdb",
        feature = "tm-script",
        feature = "tm-syscfg",
        feature = "tm-sysfs",
        feature = "tm-sysmap",
    ))]
    {
        let mut acc = 0usize;

        #[cfg(feature = "tm-cpio")]
        {
            acc ^= qsoe_tm_cpio::tm_cpio_check_valid as *const () as usize;
        }
        #[cfg(feature = "tm-cred")]
        {
            acc ^= qsoe_tm_cred::tm_cred_init as *const () as usize;
        }
        #[cfg(feature = "tm-elf")]
        {
            acc ^= qsoe_tm_elf::tm_elf_parse as *const () as usize;
        }
        #[cfg(feature = "tm-fdt")]
        {
            acc ^= qsoe_tm_fdt::tm_fdt_check as *const () as usize;
        }
        #[cfg(feature = "tm-pathmgr")]
        {
            acc ^= qsoe_tm_pathmgr::tm_pathmgr_init as *const () as usize;
        }
        #[cfg(feature = "tm-procfs")]
        {
            acc ^= qsoe_tm_procfs::tm_procfs_path_exists as *const () as usize;
        }
        #[cfg(feature = "tm-pseudodev")]
        {
            acc ^= qsoe_tm_pseudodev::tm_devnull_write as *const () as usize;
        }
        #[cfg(feature = "tm-rsrcdb")]
        {
            acc ^= qsoe_tm_rsrcdb::tm_rsrc_init as *const () as usize;
        }
        #[cfg(feature = "tm-script")]
        {
            acc ^= qsoe_tm_script::tm_script_parse_shebang as *const () as usize;
        }
        #[cfg(feature = "tm-syscfg")]
        {
            acc ^= qsoe_tm_syscfg::tm_syscfg_init as *const () as usize;
        }
        #[cfg(feature = "tm-sysfs")]
        {
            acc ^= qsoe_tm_sysfs::tm_sysfs_nentries as *const () as usize;
        }
        #[cfg(feature = "tm-sysmap")]
        {
            acc ^= qsoe_tm_sysmap::tm_sysmap_build as *const () as usize;
        }

        acc
    }
}
