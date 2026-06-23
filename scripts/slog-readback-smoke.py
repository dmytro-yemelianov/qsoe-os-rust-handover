#!/usr/bin/env python3
"""Boot QSOE/L and verify /dev/slog can be read through sloginfo."""

from __future__ import annotations

import argparse
import datetime as dt
import pathlib
import sys

try:
    import pexpect
except ImportError as exc:  # pragma: no cover - depends on host setup.
    raise SystemExit(
        "slog-readback-smoke.py: python3-pexpect is required"
    ) from exc


ROOT = pathlib.Path(__file__).resolve().parents[1]


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
    return parser.parse_args()


def tail(path: pathlib.Path, lines: int = 80) -> str:
    try:
        return "\n".join(path.read_text(errors="replace").splitlines()[-lines:])
    except OSError:
        return "(log unavailable)"


def expect(child: pexpect.spawn, pattern: str, label: str, log: pathlib.Path, timeout: int) -> None:
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


def main() -> int:
    args = parse_args()
    if args.timeout <= 0:
        print("slog-readback-smoke.py: timeout must be positive", file=sys.stderr)
        return 2

    log = args.log
    if log is None:
        stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        log = ROOT / "build" / f"slog-readback-smoke-lq-{stamp}.log"
    elif not log.is_absolute():
        log = ROOT / log

    log.parent.mkdir(parents=True, exist_ok=True)
    child: pexpect.spawn | None = None

    print(f"slog-readback-smoke.py: variant=lq timeout={args.timeout}s log={log}")
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

            expect(child, r"\[slogger\] alive", "slogger startup", log, args.timeout)
            expect(child, r"\[pci-server\] alive", "pci-server startup", log, args.timeout)
            expect(child, r"root filesystem unavailable", "rescue shell handoff", log, args.timeout)
            expect(child, r"\[[^\r\n]*\]# ", "qsh prompt", log, args.timeout)

            child.sendline("/bin/sloginfo")
            expect(child, r"pci-server:", "sloginfo pci-server readback", log, 20)
            expect(child, r"\[[^\r\n]*\]# ", "qsh prompt after sloginfo", log, 20)
        finally:
            cleanup(child)

    print("slog-readback-smoke.py: observed pci-server slog entry via /bin/sloginfo")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
