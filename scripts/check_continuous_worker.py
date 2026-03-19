#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import time
from pathlib import Path


def pid_alive(pid: int | None) -> bool:
    if not pid or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def newest_mtime(paths: list[Path]) -> float | None:
    mtimes = []
    for path in paths:
        try:
            mtimes.append(path.stat().st_mtime)
        except FileNotFoundError:
            continue
    return max(mtimes) if mtimes else None


def main() -> int:
    parser = argparse.ArgumentParser(description="Check detached continuous worker health")
    parser.add_argument("--state-file", default=None)
    parser.add_argument("--channel", default="telegram")
    parser.add_argument("--account-id", default="clawd4")
    parser.add_argument("--to", default="8173956648")
    parser.add_argument("--touch-healthy", action="store_true")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    state_file = Path(args.state_file) if args.state_file else repo_root / "automation" / "state" / "continuous_worker.json"

    if not state_file.exists():
        print(json.dumps({"status": "missing", "reason": "state-file-missing", "stateFile": str(state_file)}, indent=2))
        return 0

    try:
        state = json.loads(state_file.read_text())
    except Exception as exc:
        print(json.dumps({"status": "missing", "reason": f"state-file-unreadable: {exc}", "stateFile": str(state_file)}, indent=2))
        return 0

    owner = state.get("owner", {})
    expected = {"channel": args.channel, "accountId": args.account_id, "to": args.to}
    if owner != expected:
        print(json.dumps({
            "status": "mismatch",
            "reason": "owner-mismatch",
            "expected": expected,
            "found": owner,
            "stateFile": str(state_file),
        }, indent=2))
        return 0

    pid = state.get("pid")
    pid_is_alive = pid_alive(int(pid)) if isinstance(pid, int) or (isinstance(pid, str) and str(pid).isdigit()) else False

    log_file = Path(state.get("logFile", repo_root / "automation" / "logs" / "continuous_worker.log"))
    results_file = repo_root / "results" / "results.tsv"
    last_activity = newest_mtime([log_file, results_file])
    now = time.time()
    activity_age = None if last_activity is None else max(0, int(now - last_activity))

    stale_after = int(state.get("staleAfterSeconds", 5400))
    dead_after = int(state.get("deadAfterSeconds", 1200))

    if pid_is_alive:
        status = "healthy"
        reason = "pid-alive"
        if activity_age is not None and activity_age > stale_after:
            status = "stale"
            reason = "pid-alive-but-activity-stale"
    else:
        if activity_age is not None and activity_age <= dead_after:
            status = "healthy"
            reason = "recent-activity-without-pid"
        else:
            status = "dead"
            reason = "pid-missing-and-no-recent-activity"

    if args.touch_healthy and status == "healthy":
        state["lastHealthyAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        state_file.write_text(json.dumps(state, indent=2) + "\n")

    payload = {
        "status": status,
        "reason": reason,
        "pid": pid,
        "pidAlive": pid_is_alive,
        "branch": state.get("branch"),
        "repoRoot": state.get("repoRoot"),
        "logFile": str(log_file),
        "resultsFile": str(results_file),
        "lastActivityAgeSeconds": activity_age,
        "staleAfterSeconds": stale_after,
        "deadAfterSeconds": dead_after,
        "restartCooldownSeconds": int(state.get("restartCooldownSeconds", 1200)),
        "lastRestartAt": state.get("lastRestartAt"),
        "lastHealthyAt": state.get("lastHealthyAt"),
        "restartCount": int(state.get("restartCount", 0)),
        "stateFile": str(state_file),
    }
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
