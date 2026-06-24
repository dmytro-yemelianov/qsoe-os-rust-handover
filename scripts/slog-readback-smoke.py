#!/usr/bin/env python3
"""Boot QSOE/L and verify /dev/slog can be read through sloginfo."""

from __future__ import annotations

import argparse
import datetime as dt
import os
import pathlib
import subprocess
import sys
from collections.abc import Callable

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
    parser.add_argument(
        "--slogger-rc",
        action="store_true",
        help="build and boot the slogger Rust-default release-candidate image",
    )
    parser.add_argument(
        "--slogger-rc-rollback",
        action="store_true",
        help="build and boot the slogger release-candidate C rollback image",
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


def run_command(argv: list[str], env: dict[str, str] | None = None) -> None:
    try:
        subprocess.run(argv, cwd=ROOT, check=True, env=env)
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


def prepare_slogger_rc_image(*, rollback: bool) -> None:
    env = os.environ.copy()
    env["QSOE_SLOGGER_RC_ROLLBACK"] = "1" if rollback else "0"
    run_command(
        [str(ROOT / "scripts" / "slogger-rc-boot-smoke.sh"), "--prepare-only"],
        env=env,
    )


def main() -> int:
    args = parse_args()
    if args.timeout <= 0:
        print("slog-readback-smoke.py: timeout must be positive", file=sys.stderr)
        return 2

    slogger_modes: dict[str, tuple[str, str, Callable[[], None]]] = {
        "rust_slogger": (
            "rust-slogger",
            r"\[slogger-rs\] alive",
            prepare_rust_slogger_image,
        ),
        "slogger_rc": (
            "slogger-rc-rust-default",
            r"\[slogger-rs\] alive",
            lambda: prepare_slogger_rc_image(rollback=False),
        ),
        "slogger_rc_rollback": (
            "slogger-rc-c-rollback",
            r"\[slogger\] alive",
            lambda: prepare_slogger_rc_image(rollback=True),
        ),
    }
    selected_modes = [
        mode for mode in slogger_modes if getattr(args, mode)
    ]
    if len(selected_modes) > 1:
        print(
            "slog-readback-smoke.py: select only one slogger mode",
            file=sys.stderr,
        )
        return 2

    log = args.log
    default_mode = ("c-slogger", r"\[slogger\] alive", prepare_c_slogger_image)
    slogger_mode, startup_pattern, prepare_image = (
        slogger_modes[selected_modes[0]] if selected_modes else default_mode
    )

    if log is None:
        stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        log = (
            ROOT
            / "build"
            / f"slog-readback-smoke-lq-{slogger_mode}-{stamp}.log"
        )
    elif not log.is_absolute():
        log = ROOT / log

    prepare_image()

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
