#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/watch_swarm.sh [options]

Options:
  --follow            Refresh the view continuously.
  --interval N        Refresh interval in seconds when --follow is set. Default: 5
  --node-id NODE_ID   Show only a specific controller node.
  --job-id JOB_ID     Show only a specific child job/branch node.
  --log               Include a tail of the mirrored live run log when available.
  --events N          Number of controller events to show. Default: 8
  -h, --help          Show this help.
EOF
}

FOLLOW=0
INTERVAL=5
NODE_ID=""
JOB_ID=""
SHOW_LOG=0
EVENT_LIMIT=8

while [[ $# -gt 0 ]]; do
  case "$1" in
    --follow)
      FOLLOW=1
      shift
      ;;
    --interval)
      INTERVAL="${2:-}"
      shift 2
      ;;
    --node-id)
      NODE_ID="${2:-}"
      shift 2
      ;;
    --job-id)
      JOB_ID="${2:-}"
      shift 2
      ;;
    --log)
      SHOW_LOG=1
      shift
      ;;
    --events)
      EVENT_LIMIT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 1 ]]; then
  echo "Error: --interval must be a positive integer." >&2
  exit 2
fi

if ! [[ "$EVENT_LIMIT" =~ ^[0-9]+$ ]] || [[ "$EVENT_LIMIT" -lt 0 ]]; then
  echo "Error: --events must be a non-negative integer." >&2
  exit 2
fi

REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
OBS_NODE_DIR="$REPO_ROOT/registry/observability/nodes"
OBS_JOB_DIR_ROOT="$REPO_ROOT/registry/observability/jobs"
EVENTS_FILE="$REPO_ROOT/registry/controller_events.jsonl"

render_view() {
  python3 - "$OBS_NODE_DIR" "$OBS_JOB_DIR_ROOT" "$EVENTS_FILE" "$NODE_ID" "$JOB_ID" "$SHOW_LOG" "$EVENT_LIMIT" <<'PY'
from datetime import datetime, timezone
import json
import pathlib
import sys

node_dir = pathlib.Path(sys.argv[1])
job_root = pathlib.Path(sys.argv[2])
events_file = pathlib.Path(sys.argv[3])
node_filter = sys.argv[4]
job_filter = sys.argv[5]
show_log = sys.argv[6] == "1"
event_limit = int(sys.argv[7])

def load_json(path: pathlib.Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}

def load_statuses():
    if not node_dir.exists():
        return []
    statuses = []
    for path in sorted(node_dir.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True):
        payload = load_json(path)
        if isinstance(payload, dict) and payload:
            payload["_status_path"] = str(path)
            statuses.append(payload)
    return statuses

def fmt_duration(seconds):
    if seconds is None:
        return "unknown"
    try:
        total = int(seconds)
    except (TypeError, ValueError):
        return str(seconds)
    sign = "-" if total < 0 else ""
    total = abs(total)
    mins, secs = divmod(total, 60)
    hours, mins = divmod(mins, 60)
    if hours:
        return f"{sign}{hours}h{mins:02d}m{secs:02d}s"
    if mins:
        return f"{sign}{mins}m{secs:02d}s"
    return f"{sign}{secs}s"

def print_status(payload):
    print("=" * 100)
    print(f"Node:        {payload.get('node_id', '?')}")
    print(f"Phase:       {payload.get('phase', '?')}")
    print(f"Status:      {payload.get('status', '?')}")
    if payload.get("child_node_id"):
        print(f"Child job:   {payload['child_node_id']}")
    if payload.get("branch"):
        print(f"Branch:      {payload['branch']}")
    if payload.get("commit"):
        print(f"Commit:      {payload['commit']}")
    if payload.get("pod_name") or payload.get("pod_id"):
        pod_text = payload.get("pod_name") or payload.get("pod_id")
        if payload.get("pod_name") and payload.get("pod_id"):
            pod_text = f"{payload['pod_name']} ({payload['pod_id']})"
        print(f"Pod:         {pod_text}")
    if payload.get("ssh_host"):
        ssh_port = payload.get("ssh_port", "22")
        print(f"SSH:         {payload['ssh_host']}:{ssh_port}")
    if payload.get("updated_at"):
        print(f"Updated:     {payload['updated_at']}")
    if payload.get("last_heartbeat"):
        heartbeat_age = fmt_duration(payload.get("heartbeat_age_seconds"))
        print(f"Heartbeat:   {payload['last_heartbeat']} ({heartbeat_age} ago)")
    if "controller_ttl_remaining_seconds" in payload:
        print(f"TTL remain:  {fmt_duration(payload.get('controller_ttl_remaining_seconds'))}")
    if payload.get("message"):
        print(f"Message:     {payload['message']}")
    if payload.get("last_log_line"):
        print(f"Last log:    {payload['last_log_line']}")
    if payload.get("phase_log_dir"):
        print(f"Phase logs:  {payload['phase_log_dir']}")
    if payload.get("live_run_log_path"):
        print(f"Live log:    {payload['live_run_log_path']}")
    if payload.get("final_state"):
        final_state = payload["final_state"]
        exit_code = final_state.get("exit_code")
        finished_at = final_state.get("timestamp")
        print(f"Final state: exit_code={exit_code} timestamp={finished_at}")
    cleanup = payload.get("cleanup")
    if isinstance(cleanup, dict) and cleanup:
        last_action = cleanup.get("last_action")
        last_reason = cleanup.get("last_reason")
        released_at = cleanup.get("released_at")
        if last_action or last_reason or released_at:
            print(f"Cleanup:     action={last_action or '-'} reason={last_reason or '-'} released_at={released_at or '-'}")

def tail_lines(path_str, line_limit=20):
    if not path_str:
        return []
    path = pathlib.Path(path_str)
    if not path.exists() or not path.is_file():
        return []
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    return lines[-line_limit:]

statuses = load_statuses()

if job_filter:
    job_status_path = job_root / job_filter / "status.json"
    if job_status_path.exists():
        payload = load_json(job_status_path)
        statuses = [payload] if payload else []
    else:
        statuses = [payload for payload in statuses if payload.get("child_node_id") == job_filter]
elif node_filter:
    statuses = [payload for payload in statuses if payload.get("node_id") == node_filter]

selected_node_ids = {payload.get("node_id") for payload in statuses if payload.get("node_id")}
selected_job_ids = {payload.get("child_node_id") for payload in statuses if payload.get("child_node_id")}

print(f"Swarm observability snapshot @ {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}")
if node_filter:
    print(f"Filter node: {node_filter}")
if job_filter:
    print(f"Filter job:  {job_filter}")

if not statuses:
    print("No observability state files found for the requested scope.")
else:
    for payload in statuses:
        print_status(payload)

events = []
if events_file.exists():
    for raw_line in events_file.read_text(encoding="utf-8").splitlines():
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        try:
            payload = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        if node_filter and payload.get("node_id") != node_filter:
            continue
        if job_filter and payload.get("job_id") != job_filter:
            continue
        if (not node_filter and not job_filter) and (selected_node_ids or selected_job_ids):
            if payload.get("node_id") not in selected_node_ids and payload.get("job_id") not in selected_job_ids:
                continue
        events.append(payload)

print("-" * 100)
print("Recent controller events")
if not events:
    print("(no matching controller events)")
else:
    for payload in events[-event_limit:] if event_limit else []:
        parts = [payload.get("timestamp", "?"), payload.get("event", "?")]
        if payload.get("phase"):
            parts.append(f"phase={payload['phase']}")
        if payload.get("branch"):
            parts.append(f"branch={payload['branch']}")
        if payload.get("status"):
            parts.append(f"status={payload['status']}")
        if payload.get("message"):
            parts.append(payload["message"])
        print(" | ".join(parts))

if show_log:
    print("-" * 100)
    print("Live log tail")
    target_payload = statuses[0] if len(statuses) == 1 else None
    if target_payload is None:
        print("(select a single node or job with --node-id or --job-id to show the log tail)")
    else:
        lines = tail_lines(target_payload.get("live_run_log_path", ""), line_limit=20)
        if lines:
            for line in lines:
                print(line)
        else:
            print("(no mirrored live log available yet)")
PY
}

while true; do
  if [[ "$FOLLOW" -eq 1 ]]; then
    printf '\033[2J\033[H'
  fi

  render_view

  if [[ "$FOLLOW" -eq 0 ]]; then
    break
  fi

  sleep "$INTERVAL"
done
