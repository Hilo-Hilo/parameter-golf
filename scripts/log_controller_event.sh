#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"

usage() {
  cat <<'EOF'
Usage:
  scripts/log_controller_event.sh --event EVENT [options]

Options:
  --event EVENT       Required controller event name.
  --job-id ID         Optional job identifier.
  --pod-id ID         Optional RunPod pod identifier.
  --pod-name NAME     Optional RunPod pod name.
  --branch NAME       Optional git branch associated with the event.
  --reason TEXT       Optional structured reason label.
  --status TEXT       Optional event status label.
  --ssh-host HOST     Optional SSH host used for the event.
  --ssh-port PORT     Optional SSH port used for the event.
  --message TEXT      Optional human-readable summary.
EOF
}

event=""
job_id=""
pod_id=""
pod_name=""
branch_name=""
reason=""
status=""
ssh_host=""
ssh_port=""
message=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event)
      event="${2:-}"
      shift 2
      ;;
    --job-id)
      job_id="${2:-}"
      shift 2
      ;;
    --pod-id)
      pod_id="${2:-}"
      shift 2
      ;;
    --pod-name)
      pod_name="${2:-}"
      shift 2
      ;;
    --branch)
      branch_name="${2:-}"
      shift 2
      ;;
    --reason)
      reason="${2:-}"
      shift 2
      ;;
    --status)
      status="${2:-}"
      shift 2
      ;;
    --ssh-host)
      ssh_host="${2:-}"
      shift 2
      ;;
    --ssh-port)
      ssh_port="${2:-}"
      shift 2
      ;;
    --message)
      message="${2:-}"
      shift 2
      ;;
    --help|-h)
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

if [[ -z "$event" ]]; then
  echo "Error: --event is required" >&2
  usage >&2
  exit 2
fi

python3 - \
  "$REPO_ROOT/registry/controller_events.jsonl" \
  "$REPO_ROOT/registry/.controller_events.lock" \
  "$event" \
  "$job_id" \
  "$pod_id" \
  "$pod_name" \
  "$branch_name" \
  "$reason" \
  "$status" \
  "$ssh_host" \
  "$ssh_port" \
  "$message" <<'PY'
from datetime import datetime, timezone
import fcntl
import json
import pathlib
import sys

ledger_path = pathlib.Path(sys.argv[1])
lock_path = pathlib.Path(sys.argv[2])

keys = [
    "event",
    "job_id",
    "pod_id",
    "pod_name",
    "branch",
    "reason",
    "status",
    "ssh_host",
    "ssh_port",
    "message",
]
values = sys.argv[3:]

payload = {
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "event": values[0],
}

for key, value in zip(keys[1:], values[1:]):
    if value:
        payload[key] = value

lock_path.parent.mkdir(parents=True, exist_ok=True)
ledger_path.parent.mkdir(parents=True, exist_ok=True)

with lock_path.open("a+", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    with ledger_path.open("a+", encoding="utf-8") as ledger:
        ledger.write(json.dumps(payload, sort_keys=True))
        ledger.write("\n")
        ledger.flush()
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
PY
