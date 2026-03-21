#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import time
from pathlib import Path

from research_state import cmd_reconcile, mark_research_health


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


def _extract_reconcile_payload(payload: dict[str, object]) -> dict[str, object]:
    return payload.get("payload", payload) if isinstance(payload.get("payload"), dict) else payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Check detached continuous worker health")
    parser.add_argument("--state-file", default=None)
    parser.add_argument("--research-state-file", default=None)
    parser.add_argument("--channel", default="telegram")
    parser.add_argument("--account-id", default="clawd4")
    parser.add_argument("--to", default="8173956648")
    parser.add_argument("--touch-healthy", action="store_true")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    state_file = Path(args.state_file) if args.state_file else repo_root / "automation" / "state" / "continuous_worker.json"
    research_state_file = Path(args.research_state_file) if args.research_state_file else repo_root / "automation" / "state" / "research_state.json"
    journal_file = repo_root / "journal.md"
    results_file = repo_root / "results" / "results.tsv"

    legacy_state: dict[str, object] = {}
    if state_file.exists():
        try:
            legacy_state = json.loads(state_file.read_text())
        except Exception as exc:
            print(json.dumps({"status": "missing", "reason": f"state-file-unreadable: {exc}", "stateFile": str(state_file)}, indent=2))
            return 0

    owner = legacy_state.get("owner", {})
    expected = {"channel": args.channel, "accountId": args.account_id, "to": args.to}
    if owner != expected and owner:
        print(json.dumps({
            "status": "mismatch",
            "reason": "owner-mismatch",
            "expected": expected,
            "found": owner,
            "stateFile": str(state_file),
        }, indent=2))
        return 0

    now = time.time()
    now_utc = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now))

    log_file = Path(legacy_state.get("logFile", repo_root / "automation" / "logs" / "continuous_worker.log"))
    last_activity = newest_mtime([log_file, results_file])
    activity_age = None if last_activity is None else max(0, int(now - last_activity))

    stale_after = int(legacy_state.get("staleAfterSeconds", 5400))
    dead_after = int(legacy_state.get("deadAfterSeconds", 1200))

    pid = legacy_state.get("pid")
    pid_is_alive = pid_alive(int(pid)) if isinstance(pid, int) or (isinstance(pid, str) and str(pid).isdigit()) else False

    status = "healthy"
    reason = "pid-alive"
    if not pid_is_alive:
        if activity_age is not None and activity_age <= dead_after:
            status = "healthy"
            reason = "recent-activity-without-pid"
        elif activity_age is not None and activity_age > dead_after:
            status = "dead"
            reason = "pid-missing-and-no-recent-activity"
        else:
            status = "dead"
            reason = "pid-missing-and-no-activity-metadata"
    else:
        if activity_age is not None and activity_age > stale_after:
            status = "stale"
            reason = "pid-alive-but-activity-stale"

    reconcile_payload: dict[str, object] = {}
    reconcile_should_restart = status in {"dead", "stale", "missing"}
    reconcile_reason = None
    if state_file.exists():
        try:
            reconcile_payload = cmd_reconcile(
                type(
                    "args",
                    (),
                    {
                        "repo_root": str(repo_root),
                        "research_state_file": str(research_state_file),
                        "worker_state_file": str(state_file),
                        "journal_file": str(journal_file),
                        "results_file": str(results_file),
                        "now": now_utc,
                    },
                )
            )
            reconcile_detail = _extract_reconcile_payload(reconcile_payload)
            if isinstance(reconcile_detail, dict):
                reconcile = reconcile_detail.get("reconcile")
                if isinstance(reconcile, dict):
                    reconcile_should_restart = bool(reconcile.get("shouldRestart", True))
                    reconcile_reason = reconcile.get("duplicateReason")
                    if reconcile_reason is None:
                        reconcile_reason = reconcile.get("status")
        except Exception as exc:
            reconcile_payload = {
                "status": "error",
                "reason": f"reconcile-failed: {exc}",
                "shouldRestart": True,
                "payload": {},
            }
            reconcile_should_restart = True
            reconcile_reason = reconcile_payload.get("reason")
    else:
        reconcile_payload = {
            "status": "missing",
            "reason": "state-file-missing",
            "shouldRestart": True,
            "payload": {},
        }

    if args.touch_healthy and status == "healthy":
        legacy_state["lastHealthyAt"] = now_utc
        state_file.write_text(json.dumps(legacy_state, indent=2) + "\n")
        try:
            mark_research_health(research_state_file, now_utc, repo_root)
        except Exception:
            pass

    payload = {
        "status": status,
        "reason": reason,
        "pid": pid,
        "pidAlive": pid_is_alive,
        "branch": legacy_state.get("branch"),
        "repoRoot": legacy_state.get("repoRoot") or str(repo_root),
        "logFile": str(log_file),
        "resultsFile": str(results_file),
        "lastActivityAgeSeconds": activity_age,
        "staleAfterSeconds": stale_after,
        "deadAfterSeconds": dead_after,
        "restartCooldownSeconds": int(legacy_state.get("restartCooldownSeconds", 1200)),
        "lastRestartAt": legacy_state.get("lastRestartAt"),
        "lastHealthyAt": legacy_state.get("lastHealthyAt"),
        "restartCount": int(legacy_state.get("restartCount", 0)),
        "stateFile": str(state_file),
        "researchStateFile": str(research_state_file),
        "reconcile": {
            "status": _extract_reconcile_payload(reconcile_payload).get("status", "missing"),
            "reason": reconcile_reason or reconcile_payload.get("reason"),
            "shouldRestart": reconcile_should_restart,
            "payload": reconcile_payload,
        },
    }
    payload["shouldRestart"] = bool(status in {"dead", "stale", "missing"} and reconcile_should_restart)

    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
