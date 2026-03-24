#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import signal
import subprocess
def normalize_returncode(returncode: int) -> int:
    if returncode >= 0:
        return returncode
    return 128 + abs(returncode)


def main() -> int:
    parser = argparse.ArgumentParser(description="Portable timeout wrapper with TERM/KILL escalation.")
    parser.add_argument("--kill-after", type=float, default=30.0, help="Seconds to wait after TERM before KILL.")
    parser.add_argument("timeout_seconds", type=float, help="Hard timeout in seconds.")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="Command to execute after --.")
    args = parser.parse_args()

    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        parser.error("missing command after timeout_seconds")

    process = subprocess.Popen(command, start_new_session=True)

    try:
        return normalize_returncode(process.wait(timeout=args.timeout_seconds))
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=args.kill_after)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        return 124


if __name__ == "__main__":
    raise SystemExit(main())
