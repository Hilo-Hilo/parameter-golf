#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def run_json(cmd: list[str], cwd: Path) -> dict:
    proc = subprocess.run(cmd, cwd=str(cwd), text=True, capture_output=True)
    if proc.returncode != 0:
        return {
            "ok": False,
            "returncode": proc.returncode,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
        }
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        return {
            "ok": False,
            "returncode": 0,
            "stdout": proc.stdout,
            "stderr": f"json-decode-error: {exc}",
        }
    payload["ok"] = True
    return payload


def parse_iso8601(ts: str | None) -> datetime | None:
    if not ts:
        return None
    try:
        return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def cooldown_elapsed(last_restart_at: str | None, cooldown_seconds: int) -> bool:
    dt = parse_iso8601(last_restart_at)
    if dt is None:
        return True
    elapsed = (datetime.now(timezone.utc) - dt).total_seconds()
    return elapsed >= cooldown_seconds


def main() -> int:
    parser = argparse.ArgumentParser(description="One watchdog tick for the detached continuous worker")
    parser.add_argument("--channel", default="telegram")
    parser.add_argument("--account-id", default="clawd4")
    parser.add_argument("--to", default="8173956648")
    parser.add_argument("--branch", default="research/continuous-mar18")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    check_cmd = [
        sys.executable,
        str(repo_root / "scripts" / "check_continuous_worker.py"),
        "--channel",
        args.channel,
        "--account-id",
        args.account_id,
        "--to",
        args.to,
        "--touch-healthy",
    ]
    check = run_json(check_cmd, repo_root)
    if not check.get("ok"):
        print(json.dumps({"action": "error", "reason": "check-failed", "check": check}, indent=2))
        return 0

    status = check.get("status")
    cooldown_seconds = int(check.get("restartCooldownSeconds", 1200))
    if status in {"healthy", "mismatch"}:
        print(json.dumps({"action": "noop", "status": status, "check": check}, indent=2))
        return 0

    if status in {"dead", "stale", "missing"} and not cooldown_elapsed(check.get("lastRestartAt"), cooldown_seconds):
        print(json.dumps({"action": "cooldown", "status": status, "check": check}, indent=2))
        return 0

    if status == "stale":
        stop = run_json([str(repo_root / "scripts" / "stop_continuous_worker.sh")], repo_root)
        if not stop.get("ok"):
            print(json.dumps({"action": "error", "reason": "stop-failed", "check": check, "stop": stop}, indent=2))
            return 0
        start = run_json([
            str(repo_root / "scripts" / "start_continuous_worker.sh"),
            "--branch", args.branch,
            "--channel", args.channel,
            "--account-id", args.account_id,
            "--to", args.to,
            "--force-restart",
        ], repo_root)
    else:
        start = run_json([
            str(repo_root / "scripts" / "start_continuous_worker.sh"),
            "--branch", args.branch,
            "--channel", args.channel,
            "--account-id", args.account_id,
            "--to", args.to,
        ], repo_root)

    if not start.get("ok"):
        print(json.dumps({"action": "error", "reason": "start-failed", "check": check, "start": start}, indent=2))
        return 0

    print(json.dumps({"action": "restarted", "previousStatus": status, "check": check, "start": start}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
