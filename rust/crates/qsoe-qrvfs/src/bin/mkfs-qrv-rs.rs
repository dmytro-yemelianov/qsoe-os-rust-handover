use std::env;
use std::path::PathBuf;
use std::process;

use qsoe_qrvfs::writer::{
    build_image, write_image_to_path, TargetInitialization, WriterConfig, DEFAULT_NINODES,
    DEFAULT_SIZE_MB,
};

fn main() {
    if let Err(err) = run() {
        eprintln!("mkfs-qrv-rs: {err}");
        process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut args = env::args();
    let prog = args.next().unwrap_or_else(|| "mkfs-qrv-rs".to_owned());
    let mut size_mb = DEFAULT_SIZE_MB;
    let mut ninodes = DEFAULT_NINODES;
    let mut positional = Vec::new();

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-s" => {
                let value = args
                    .next()
                    .ok_or_else(|| usage(&prog, "missing value for -s"))?;
                size_mb = parse_u64(&prog, "-s", &value)?;
            }
            "-n" => {
                let value = args
                    .next()
                    .ok_or_else(|| usage(&prog, "missing value for -n"))?;
                ninodes = parse_u64(&prog, "-n", &value)?;
            }
            "-h" | "--help" => {
                println!("{}", usage(&prog, ""));
                return Ok(());
            }
            _ if arg.starts_with('-') => {
                return Err(usage(&prog, &format!("unknown option {arg}")));
            }
            _ => positional.push(PathBuf::from(arg)),
        }
    }

    if positional.is_empty() || positional.len() > 2 {
        return Err(usage(
            &prog,
            "expected image path and optional populate dir",
        ));
    }

    let image_path = &positional[0];
    let populate_dir = positional.get(1).map(PathBuf::as_path);
    let config = WriterConfig { size_mb, ninodes };
    let built = build_image(populate_dir, config).map_err(|err| err.to_string())?;
    let report = write_image_to_path(image_path, &built)
        .map_err(|err| format!("{}: {err}", image_path.display()))?;

    println!(
        "mkfs-qrvfs-rs: {}: {} MB ({} blocks)",
        image_path.display(),
        size_mb,
        built.layout.total_blocks
    );
    println!(
        "  layout: log={} inodes={}({} blocks) bmap={} data={}({} blocks)",
        built.layout.logstart,
        built.layout.ninodes,
        built.layout.ninode_blocks,
        built.layout.bmapstart,
        built.layout.datastart,
        built.layout.data_blocks
    );
    match report.initialization {
        TargetInitialization::SparseFile { total_bytes } => {
            println!("  init: sparse file, {total_bytes} bytes (holes read as zeros)");
        }
        TargetInitialization::BlockZeroOut { metadata_bytes } => {
            println!("  init: BLKZEROOUT {metadata_bytes} metadata bytes (data area left as-is)");
        }
        TargetInitialization::BlockZeroOutFallback {
            error,
            metadata_blocks,
        } => {
            println!(
                "  init: BLKZEROOUT unavailable ({error}); writing {metadata_blocks} metadata blocks"
            );
        }
    }
    println!(
        "mkfs-qrvfs-rs: done. Root inode={}, {} data blocks used.",
        built.root_inode, built.data_blocks_used
    );

    Ok(())
}

fn parse_u64(prog: &str, opt: &str, value: &str) -> Result<u64, String> {
    value
        .parse::<u64>()
        .map_err(|_| usage(prog, &format!("invalid value for {opt}: {value}")))
}

fn usage(prog: &str, message: &str) -> String {
    let prefix = if message.is_empty() {
        String::new()
    } else {
        format!("{message}\n")
    };
    format!("{prefix}Usage: {prog} [-s size_mb] [-n ninodes] image [populate_dir]")
}
