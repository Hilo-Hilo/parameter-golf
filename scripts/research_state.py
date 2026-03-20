#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import subprocess
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path

from typing import Any

WORKER_STATE_FILE = Path("automation/state/continuous_worker.json")
RESEARCH_STATE_FILE = Path("automation/state/research_state.json")
DEFAULT_STRATEGY_VERSION = "state-v1.2026.03.20.directcopy01"
DEFAULT_PRIORITY = ["runpod", "dgx-spark", "local-mlx"]
RUN_ID_RE = re.compile(r"^\d{8}T\d{6}Z_(?P<name>.+)$")


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_ts(ts: str | None) -> float | None:
    if not ts:
        return None
    try:
        return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()
    except ValueError:
        return None


def read_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")


def merge_dicts(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            base[key] = merge_dicts(base[key], value)
        elif value is not None:
            base[key] = value
    return base


def default_research_state(repo_root: Path, branch: str | None = None) -> dict[str, Any]:
    branch_value = branch or ""
    return {
        "schemaVersion": 1,
        "repoRoot": str(repo_root),
        "strategyVersion": DEFAULT_STRATEGY_VERSION,
        "currentPriorityOrder": DEFAULT_PRIORITY,
        "activeHypothesis": "Directly reproduce the strongest public 10L Overtone sliding-window path first, then test minimal deltas from that baseline only.",
        "nextPlannedAction": "Run 10L MuonWD Overtone/10L sliding-window exact baseline now on RunPod H100, then avoid speculative sweeps until that run is complete and logged.",
        "upstream": {
            "lastCheckedAt": None,
            "lastSeenCommit": None,
            "lastCheckedBranch": branch_value,
        },
        "journal": {
            "lastEntryHeading": None,
            "lastEntryUpdatedAt": None,
            "lastPivot": None,
            "lastPivotAt": None,
        },
        "run": {
            "active": {
                "signature": None,
                "runId": None,
                "status": "idle",
                "startedAt": None,
                "attempt": 0,
            },
            "lastCompleted": {
                "signature": None,
                "runId": None,
                "status": None,
                "ts": None,
                "rowStatus": None,
                "updatedAt": None,
            },
            "recentAttemptSignatures": [],
        },
        "worker": {
            "stateFile": None,
            "pid": None,
            "status": "stopped",
            "logFile": None,
            "lastStartedAt": None,
            "lastHealthyAt": None,
            "lastTouchedAt": None,
            "lastStopAt": None,
            "lastStopReason": None,
        },
        "reconciliation": {
            "lastCheckedAt": None,
            "lastCheckedReason": None,
            "nextActionSignature": None,
        },
        "updatedAt": None,
    }


def ensure_research_state(
    state_path: Path,
    repo_root: Path,
    branch: str | None = None,
) -> dict[str, Any]:
    return merge_dicts(
        default_research_state(repo_root, branch=branch),
        read_json(state_path),
    )


def git_head_and_upstream(repo_root: Path) -> tuple[str | None, str | None]:
    def run_git(args: list[str]) -> str | None:
        try:
            proc = subprocess.run(
                ["git", "-C", str(repo_root), *args],
                check=False,
                text=True,
                capture_output=True,
            )
        except OSError:
            return None
        if proc.returncode != 0:
            return None
        return proc.stdout.strip() or None

    return run_git(["rev-parse", "HEAD"]), run_git(["rev-parse", "@{u}"])


def run_signature_from_payload(*parts: str | None) -> str:
    seed = "|".join((part or "").strip() for part in parts).strip("|")
    if not seed:
        seed = "unknown"
    return hashlib.sha1(seed.encode("utf-8")).hexdigest()[:16]


def run_signature_from_row(row: dict[str, Any]) -> str:
    candidate = (
        row.get("experiment_id")
        or row.get("run_id")
        or row.get("run_signature")
        or ""
    )
    m = RUN_ID_RE.match(str(candidate))
    if m:
        candidate = m.group("name")

    return run_signature_from_payload(
        str(row.get("branch", "")),
        str(row.get("trainer", "")),
        str(candidate),
        str(row.get("track", "")),
    )


def read_results_tail(results_file: Path, limit: int = 120) -> list[dict[str, str]]:
    if not results_file.exists():
        return []
    rows: list[dict[str, str]] = []
    with results_file.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        if not reader.fieldnames:
            return []
        for row in reader:
            rows.append({k: (v if v is not None else "") for k, v in row.items()})
    if limit <= 0:
        return rows
    if len(rows) <= limit:
        return rows
    return rows[-limit:]


def summarize_results(rows: list[dict[str, str]]) -> dict[str, Any]:
    summary: dict[str, Any] = {
        "hasRows": bool(rows),
        "totalRows": len(rows),
        "lastCompleted": None,
    }

    recent_sigs: list[str] = []
    for row in reversed(rows):
        sig = run_signature_from_row(row)
        if sig and sig not in recent_sigs:
            recent_sigs.append(sig)
            if len(recent_sigs) >= 15:
                break

    for row in reversed(rows):
        status = str(row.get("status", "")).lower().strip()
        if status and status != "crash":
            summary["lastCompleted"] = {
                "ts": row.get("ts_utc") or "",
                "runId": row.get("run_id") or row.get("experiment_id") or "",
                "signature": run_signature_from_row(row),
                "status": status,
                "rowStatus": status,
            }
            break

    summary["recentAttemptSignatures"] = recent_sigs
    return summary


def read_journal_tail(journal_file: Path, max_lines: int = 260) -> dict[str, str | None]:
    if not journal_file.exists():
        return {
            "lastEntryHeading": None,
            "lastPivot": None,
            "lastPivotAt": None,
            "tailLineCount": 0,
        }

    lines = deque(maxlen=max_lines)
    with journal_file.open("r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            lines.append(raw.rstrip("\n"))

    heading = None
    for i in range(len(lines) - 1, -1, -1):
        if lines[i].startswith("## "):
            heading = lines[i].strip()
            break

    pivot = None
    for line in reversed(lines):
        if "Hypothesis:" in line or "single hypothesis" in line.lower():
            pivot = line.strip().lstrip("- ")
            break

    return {
        "lastEntryHeading": heading,
        "lastPivot": pivot,
        "lastPivotAt": heading,
        "tailLineCount": len(lines),
    }


def pid_alive(pid: int | None) -> bool:
    if not pid or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def read_process_state(pid: int | None) -> dict[str, Any]:
    state = {"pid": pid, "alive": False, "cmdline": None}
    if not pid_alive(pid):
        return state
    state["alive"] = True
    try:
        proc = subprocess.run(
            ["ps", "-p", str(pid), "-o", "command="],
            check=False,
            text=True,
            capture_output=True,
        )
        if proc.returncode == 0:
            state["cmdline"] = proc.stdout.strip() or None
    except OSError:
        pass
    return state


def update_research_file_on_worker_start(
    state_path: Path,
    worker_state_file: Path,
    journal_file: Path,
    results_file: Path,
    branch: str,
    log_file: Path,
    pid: int,
    now: str,
) -> dict[str, Any]:
    state = ensure_research_state(state_path, log_file.parent.parent, branch=branch)
    state["worker"]["stateFile"] = str(worker_state_file)
    state["worker"]["pid"] = pid
    state["worker"]["logFile"] = str(log_file)
    state["worker"]["status"] = "running"
    state["worker"]["lastStartedAt"] = now
    state["worker"]["lastTouchedAt"] = now

    results_summary = summarize_results(read_results_tail(results_file))
    state["results"] = {
        "lastCompleted": results_summary.get("lastCompleted"),
        "lastCheckedAt": now,
        "recentAttemptSignatures": results_summary.get("recentAttemptSignatures", []),
    }
    state["run"]["lastCompleted"] = {
        "signature": None,
        "runId": None,
        "status": None,
        "ts": None,
        "rowStatus": None,
        "updatedAt": now,
    }
    if isinstance(results_summary.get("lastCompleted"), dict):
        state["run"]["lastCompleted"] = {
            "signature": results_summary["lastCompleted"].get("signature"),
            "runId": results_summary["lastCompleted"].get("runId"),
            "status": results_summary["lastCompleted"].get("status"),
            "ts": results_summary["lastCompleted"].get("ts"),
            "rowStatus": results_summary["lastCompleted"].get("rowStatus"),
            "updatedAt": now,
        }

    state["journal"] = merge_dicts(
        state.get("journal", {}),
        read_journal_tail(journal_file),
    )

    if state.get("nextPlannedAction"):
        state["run"]["active"]["signature"] = run_signature_from_payload(
            str(branch),
            str(state.get("nextPlannedAction", "")),
            str(state.get("activeHypothesis", "")),
        )
    else:
        state["run"]["active"]["signature"] = state.get("run", {}).get("active", {}).get("signature")

    state["run"]["active"]["status"] = "running"
    state["run"]["active"]["startedAt"] = now
    state["run"]["active"]["attempt"] = int(state.get("run", {}).get("active", {}).get("attempt", 0) or 0) + 1
    state["updatedAt"] = now
    state["reconciliation"]["lastCheckedAt"] = now
    state["reconciliation"]["nextActionSignature"] = state["run"]["active"]["signature"]
    write_json(state_path, state)
    return state


def mark_worker_stopped(
    state_path: Path,
    now: str,
    reason: str,
    repo_root: Path,
) -> dict[str, Any]:
    state = ensure_research_state(state_path, repo_root)
    state["worker"]["status"] = "stopped"
    state["worker"]["lastStopAt"] = now
    state["worker"]["lastStopReason"] = reason
    state["worker"]["lastTouchedAt"] = now
    state["run"]["active"]["status"] = "stopped"
    state["run"]["active"]["stoppedAt"] = now
    state["updatedAt"] = now
    write_json(state_path, state)
    return state


def mark_research_health(state_path: Path, now: str, repo_root: Path) -> dict[str, Any]:
    state = ensure_research_state(state_path, repo_root)
    state["worker"]["lastHealthyAt"] = now
    state["worker"]["lastTouchedAt"] = now
    state["updatedAt"] = now
    write_json(state_path, state)
    return state


def update_upstream(state_path: Path, branch: str, repo_root: Path, now: str) -> dict[str, Any]:
    state = ensure_research_state(state_path, repo_root, branch=branch)
    head, upstream = git_head_and_upstream(repo_root)
    state["upstream"]["lastCheckedBranch"] = branch
    state["upstream"]["lastCheckedAt"] = now
    state["upstream"]["lastSeenCommit"] = head or state["upstream"].get("lastSeenCommit")
    state["upstream"]["lastSeenUpstreamCommit"] = upstream or state["upstream"].get("lastSeenUpstreamCommit")
    write_json(state_path, state)
    return state


def reconcile_state(
    repo_root: Path,
    worker_state_file: Path,
    state_file: Path,
    journal_file: Path,
    results_file: Path,
    now: str,
    now_ts: float | None = None,
) -> dict[str, Any]:
    worker_state = read_json(worker_state_file)
    journal_state = read_journal_tail(journal_file)
    results_rows = read_results_tail(results_file)
    results_summary = summarize_results(results_rows)
    research_state = ensure_research_state(state_file, repo_root, branch=worker_state.get("branch"))

    pid = worker_state.get("pid")
    try:
        pid_int = int(pid) if isinstance(pid, str) or isinstance(pid, int) else None
    except ValueError:
        pid_int = None

    process = read_process_state(pid_int)
    log_file = Path(worker_state.get("logFile") or "")
    log_mtime = None
    log_age_seconds = None
    if log_file.exists():
        try:
            log_mtime = log_file.stat().st_mtime
            now_value = now_ts if now_ts is not None else time.time()
            log_age_seconds = max(0, int(now_value - log_mtime))
        except OSError:
            pass

    last_completed = results_summary.get("lastCompleted") or {}
    active = research_state.get("run", {}).get("active", {})
    active_signature = active.get("signature")
    last_completed_signature = last_completed.get("signature")

    duplicate_hold = False
    duplicate_reason = None
    if active_signature and last_completed_signature and active_signature == last_completed_signature:
        duplicate_hold = True
        duplicate_reason = "active-run-signature-already-completed-in-results"

    recent_attempt = research_state.get("run", {}).get("recentAttemptSignatures", [])
    if not isinstance(recent_attempt, list):
        recent_attempt = []

    should_restart = True
    if process["alive"] and active_signature and duplicate_hold:
        should_restart = False
        duplicate_reason = "active-run-signature-complete-and-process-alive"

    if not process["alive"] and duplicate_hold and active_signature in recent_attempt:
        should_restart = False
        duplicate_reason = "duplicate-active-run-detected-in-results"

    if not active_signature:
        duplicate_hold = False
        duplicate_reason = "no-active-run-signature-in-state"

    owner = worker_state.get("owner", {})

    payload: dict[str, Any] = {
        "status": "reconciled",
        "stateFile": str(state_file),
        "workerStateFile": str(worker_state_file),
        "lastCheckedAt": now,
        "strategyVersion": research_state.get("strategyVersion"),
        "strategyOrder": research_state.get("currentPriorityOrder", []),
        "worker": {
            "pid": pid_int,
            "alive": process["alive"],
            "cmdline": process["cmdline"],
            "logFile": str(log_file) if log_file else None,
            "logFileAgeSeconds": log_age_seconds,
            "status": worker_state.get("status"),
            "lastRestartAt": worker_state.get("lastRestartAt"),
            "owner": owner,
        },
        "journal": {
            "lastEntryHeading": journal_state.get("lastEntryHeading"),
            "lastPivot": journal_state.get("lastPivot"),
            "lastPivotAt": journal_state.get("lastPivotAt"),
        },
        "run": {
            "active": {
                "signature": active_signature,
                "status": active.get("status"),
                "startedAt": active.get("startedAt"),
                "attempt": active.get("attempt"),
            },
            "lastCompleted": {
                "signature": last_completed_signature,
                "status": last_completed.get("status"),
                "runId": last_completed.get("runId"),
                "ts": last_completed.get("ts"),
            },
            "recentAttemptSignatures": results_summary.get("recentAttemptSignatures", []),
        },
        "reconcile": {
            "duplicateHold": duplicate_hold,
            "duplicateReason": duplicate_reason,
            "shouldRestart": should_restart,
        },
    }
    payload["reconciliation"] = {
        "resultsRows": len(results_rows),
        "lastCompleted": payload["run"]["lastCompleted"],
        "lastAction": research_state.get("nextPlannedAction"),
        "upstream": {
            "commit": research_state.get("upstream", {}).get("lastSeenCommit"),
            "checkedAt": research_state.get("upstream", {}).get("lastCheckedAt"),
        },
        "journalEntryUpdated": payload["journal"].get("lastEntryHeading"),
        "updatedBy": "research_state.reconcile_state",
    }
    research_state["reconciliation"] = {
        "lastCheckedAt": now,
        "lastCheckedReason": payload["reconcile"].get("duplicateReason") or "none",
        "nextActionSignature": active_signature,
    }
    research_state["run"]["recentAttemptSignatures"] = payload["run"]["recentAttemptSignatures"]
    if isinstance(last_completed, dict):
        research_state["run"]["lastCompleted"] = {
            "signature": last_completed.get("signature"),
            "runId": last_completed.get("runId"),
            "status": last_completed.get("status"),
            "ts": last_completed.get("ts"),
            "rowStatus": last_completed.get("rowStatus"),
            "updatedAt": now,
        }
    write_json(state_file, research_state)
    return payload


def cmd_bootstrap(args: argparse.Namespace) -> dict[str, Any]:
    repo_root = Path(args.repo_root)
    research_state_path = Path(args.research_state_file)
    worker_state_path = Path(args.worker_state_file)
    now = args.now or now_utc()
    bootstrap_state = update_upstream(
        research_state_path,
        args.branch,
        repo_root,
        now,
    )
    if args.journal_file:
        journal_file = Path(args.journal_file)
    else:
        journal_file = repo_root / "journal.md"
    if args.results_file:
        results_file = Path(args.results_file)
    else:
        results_file = repo_root / "results" / "results.tsv"

    if args.log_file:
        log_file = Path(args.log_file)
    else:
        log_file = repo_root / "automation" / "logs" / "continuous_worker.log"

    bootstrap_state = update_research_file_on_worker_start(
        research_state_path,
        worker_state_path,
        journal_file,
        results_file,
        args.branch,
        log_file,
        args.worker_pid,
        now,
    )
    return bootstrap_state


def cmd_reconcile(args: argparse.Namespace) -> dict[str, Any]:
    repo_root = Path(args.repo_root)
    research_state_path = Path(args.research_state_file)
    worker_state_path = Path(args.worker_state_file)
    journal_file = Path(args.journal_file)
    results_file = Path(args.results_file)
    now = args.now or now_utc()
    return reconcile_state(
        repo_root=repo_root,
        worker_state_file=worker_state_path,
        state_file=research_state_path,
        journal_file=journal_file,
        results_file=results_file,
        now=now,
    )


def cmd_mark_stop(args: argparse.Namespace) -> dict[str, Any]:
    return mark_worker_stopped(
        state_path=Path(args.research_state_file),
        now=args.now or now_utc(),
        reason=args.reason,
        repo_root=Path(args.repo_root),
    )


def cmd_mark_healthy(args: argparse.Namespace) -> dict[str, Any]:
    return mark_research_health(
        state_path=Path(args.research_state_file),
        now=args.now or now_utc(),
        repo_root=Path(args.repo_root),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Research state reconciliation utilities")
    parser.add_argument("command", choices=["bootstrap", "reconcile", "mark-stop", "mark-healthy"])
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--research-state-file", default=str(RESEARCH_STATE_FILE))
    parser.add_argument("--worker-state-file", default=str(WORKER_STATE_FILE))
    parser.add_argument("--journal-file", default=str(Path("journal.md")))
    parser.add_argument("--results-file", default=str(Path("results") / "results.tsv"))
    parser.add_argument("--branch", default="research/continuous-mar18")
    parser.add_argument("--now", default="")
    parser.add_argument("--worker-pid", type=int, default=0)
    parser.add_argument("--log-file", default="")
    parser.add_argument("--reason", default="manual-stop")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.command == "bootstrap":
        state = cmd_bootstrap(args)
        print(json.dumps({"status": "ok", "action": "bootstrap", "stateFile": str(args.research_state_file), "state": state}, indent=2))
    elif args.command == "reconcile":
        payload = cmd_reconcile(args)
        print(json.dumps({"status": "ok", "action": "reconcile", "payload": payload}, indent=2))
    elif args.command == "mark-stop":
        state = cmd_mark_stop(args)
        print(json.dumps({"status": "ok", "action": "mark-stop", "state": state}, indent=2))
    elif args.command == "mark-healthy":
        state = cmd_mark_healthy(args)
        print(json.dumps({"status": "ok", "action": "mark-healthy", "state": state}, indent=2))
    else:
        raise ValueError(f"unknown command: {args.command}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
