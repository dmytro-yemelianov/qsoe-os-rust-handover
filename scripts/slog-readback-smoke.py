#!/usr/bin/env python3
"""Boot QSOE/L and verify /dev/slog can be read through sloginfo."""

from __future__ import annotations

import argparse
import datetime as dt
import os
import pathlib
import subprocess
import sys

try:
    import pexpect
except ImportError as exc:  # pragma: no cover - depends on host setup.
    raise SystemExit(
        "slog-readback-smoke.py: python3-pexpect is required"
    ) from exc


ROOT = pathlib.Path(__file__).resolve().parents[1]
MAKE = os.environ.get("MAKE", "make")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Boot QSOE/L rescue shell and verify sloginfo reads /dev/slog."
    )
    parser.add_argument(
        "-t",
        "--timeout",
        type=int,
        default=180,
        help="overall milestone timeout in seconds, default: 180",
    )
    parser.add_argument(
        "-o",
        "--log",
        type=pathlib.Path,
        help="log path, default: build/slog-readback-smoke-lq-<timestamp>.log",
    )
    parser.add_argument(
        "--rust-slogger",
        action="store_true",
        help="build and boot an opt-in LQ image with slogger-rs selected",
    )
    return parser.parse_args()


def tail(path: pathlib.Path, lines: int = 80) -> str:
    try:
        return "\n".join(path.read_text(errors="replace").splitlines()[-lines:])
    except OSError:
        return "(log unavailable)"


def expect(
    child: pexpect.spawn,
    pattern: str,
    label: str,
    log: pathlib.Path,
    timeout: int,
) -> None:
    try:
        child.expect(pattern, timeout=timeout)
    except (pexpect.TIMEOUT, pexpect.EOF) as exc:
        print(f"slog-readback-smoke.py: missing {label}: {pattern}", file=sys.stderr)
        print(f"slog-readback-smoke.py: log={log}", file=sys.stderr)
        print("slog-readback-smoke.py: last log lines:", file=sys.stderr)
        print(tail(log), file=sys.stderr)
        raise SystemExit(1) from exc


def cleanup(child: pexpect.spawn | None) -> None:
    if child is None or not child.isalive():
        return
    child.terminate(force=True)


def run_command(argv: list[str]) -> None:
    try:
        subprocess.run(argv, cwd=ROOT, check=True)
    except subprocess.CalledProcessError as exc:
        raise SystemExit(exc.returncode) from exc


def prepare_c_slogger_image() -> None:
    workdir = ROOT / "build" / "slog-readback"
    c_cpio = workdir / "modpkg-lq-c-slogger.cpio"
    lq_libc = ROOT / "lq" / "build" / "libc" / "libc.so"
    lq_rtld = ROOT / "lq" / "build" / "rtld" / "ld-qsoe.so.1"

    workdir.mkdir(parents=True, exist_ok=True)
    run_command(
        [
            MAKE,
            "-C",
            str(ROOT / "lq"),
            "libc",
            "rtld",
            "libtaskman",
            "--no-print-directory",
        ]
    )
    run_command(
        [
            MAKE,
            "-C",
            str(ROOT / "quser"),
            "cpio",
            "--no-print-directory",
            f"MODPKG_CPIO={c_cpio}",
            f"LIBC_SO={lq_libc}",
            f"RTLD_SO={lq_rtld}",
            f"DYNLIBC_SO={lq_libc}",
        ]
    )
    c_cpio.touch()
    run_command(
        [
            MAKE,
            "-C",
            str(ROOT / "lq"),
            f"MODPKG_CPIO={c_cpio}",
            "--no-print-directory",
        ]
    )


def prepare_rust_slogger_image() -> None:
    run_command(
        [str(ROOT / "scripts" / "rust-slogger-boot-smoke.sh"), "--prepare-only"]
    )


def main() -> int:
    args = parse_args()
    if args.timeout <= 0:
        print("slog-readback-smoke.py: timeout must be positive", file=sys.stderr)
        return 2

    log = args.log
    slogger_mode = "rust-slogger" if args.rust_slogger else "c-slogger"
    if log is None:
        stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        log = (
            ROOT
            / "build"
            / f"slog-readback-smoke-lq-{slogger_mode}-{stamp}.log"
        )
    elif not log.is_absolute():
        log = ROOT / log

    startup_pattern = (
        r"\[slogger-rs\] alive" if args.rust_slogger else r"\[slogger\] alive"
    )
    if args.rust_slogger:
        prepare_rust_slogger_image()
    else:
        prepare_c_slogger_image()

    log.parent.mkdir(parents=True, exist_ok=True)
    child: pexpect.spawn | None = None

    print(
        f"slog-readback-smoke.py: variant=lq slogger={slogger_mode} "
        f"timeout={args.timeout}s log={log}"
    )
    with log.open("w", encoding="utf-8", errors="replace") as log_file:
        try:
            child = pexpect.spawn(
                str(ROOT / "lq" / "emu.sh"),
                ["-no-virtio"],
                cwd=str(ROOT / "lq"),
                encoding="utf-8",
                timeout=args.timeout,
            )
            child.logfile = log_file

            expect(child, startup_pattern, "slogger startup", log, args.timeout)
            expect(
                child, r"\[pci-server\] alive", "pci-server startup", log, args.timeout
            )
            expect(
                child,
                r"root filesystem unavailable",
                "rescue shell handoff",
                log,
                args.timeout,
            )
            expect(child, r"\[[^\r\n]*\]# ", "qsh prompt", log, args.timeout)

            child.sendline("/bin/sloginfo")
            expect(child, r"pci-server:", "sloginfo pci-server readback", log, 20)
            expect(child, r"\[[^\r\n]*\]# ", "qsh prompt after sloginfo", log, 20)
        finally:
            cleanup(child)

    print(
        "slog-readback-smoke.py: observed pci-server slog entry via "
        f"/bin/sloginfo with {slogger_mode}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
