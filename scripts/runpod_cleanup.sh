#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"

usage() {
  cat <<'EOF'
Usage:
  scripts/runpod_cleanup.sh --job-id JOB_ID [--action stop|terminate|none] [--reason TEXT] [--dry-run]

Notes:
  - Reads pod lease metadata from registry/spool/<job_id>_lease.json
  - Defaults to the lease's cleanup policy
  - Uses "none" to mark a lease released without issuing a pod command
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: missing required command: $1" >&2
    exit 1
  fi
}

job_id=""
action=""
reason="manual"
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --job-id)
      job_id="${2:-}"
      shift 2
      ;;
    --action)
      action="${2:-}"
      shift 2
      ;;
    --reason)
      reason="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
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

if [[ -z "$job_id" ]]; then
  echo "Error: --job-id is required" >&2
  usage >&2
  exit 2
fi

require_cmd jq
require_cmd python3
require_cmd runpodctl

log_event() {
  "$SCRIPT_DIR/log_controller_event.sh" "$@" >/dev/null 2>&1 || true
}

announce() {
  local label="${CONTROLLER_LOG_LABEL:-$job_id}"
  printf '[%s][%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$label" "$*"
}

pod_status_from_output() {
  python3 - "${1:-}" <<'PY'
import sys

text = sys.argv[1]
lines = [line for line in text.splitlines() if line.strip()]
if len(lines) < 2:
    print("MISSING")
    raise SystemExit(0)

header = [cell.strip() for cell in lines[0].split("\t")]
row = [cell.strip() for cell in lines[1].split("\t")]

try:
    idx = header.index("STATUS")
except ValueError:
    print("MISSING")
    raise SystemExit(0)

if idx >= len(row):
    print("MISSING")
else:
    print(row[idx] or "MISSING")
PY
}

lease_file="$REPO_ROOT/registry/spool/${job_id}_lease.json"
pod_id=""
profile_key=""
default_action="stop"
failure_action="stop"

if [[ -f "$lease_file" ]]; then
  pod_id="$(jq -r '.pod_id // empty' "$lease_file")"
  profile_key="$(jq -r '.profile_key // empty' "$lease_file")"
  default_action="$(jq -r '.cleanup.default_action // "stop"' "$lease_file")"
  failure_action="$(jq -r '.cleanup.failure_action // "stop"' "$lease_file")"
fi

if [[ -z "$pod_id" && -f "$REPO_ROOT/registry/spool/${job_id}_pod_id.txt" ]]; then
  pod_id="$(<"$REPO_ROOT/registry/spool/${job_id}_pod_id.txt")"
fi

if [[ -z "$pod_id" ]]; then
  echo "Error: unable to resolve pod ID for $job_id" >&2
  exit 1
fi

if [[ -z "$action" ]]; then
  case "$reason" in
    controller_exit|dispatch_failed|controller_ttl_exceeded|reconcile_ttl_exceeded|collect_failed|job_failed)
      action="$failure_action"
      ;;
    *)
      action="$default_action"
      ;;
  esac
fi

case "$action" in
  stop|terminate|none) ;;
  *)
    echo "Error: invalid --action $action" >&2
    exit 2
    ;;
esac

pod_info_before="$(runpodctl get pod "$pod_id" --allfields 2>/dev/null || true)"
pod_status_before="$(pod_status_from_output "$pod_info_before")"
pod_status_before="${pod_status_before:-MISSING}"
action_applied="$action"

announce "Cleanup for $job_id on pod $pod_id ($pod_status_before), action=$action, reason=$reason"

if [[ "$dry_run" -eq 0 ]]; then
  case "$action" in
    stop)
      if [[ "$pod_status_before" == "MISSING" || "$pod_status_before" == "EXITED" ]]; then
        action_applied="none"
      elif runpodctl stop pod "$pod_id"; then
        action_applied="stop"
      else
        fallback_action="${RUNPOD_STOP_FALLBACK_ACTION:-$failure_action}"
        if [[ "$fallback_action" == "terminate" ]]; then
          runpodctl remove pod "$pod_id"
          action_applied="terminate_after_stop_failure"
        else
          announce "Error: stop failed for pod $pod_id and no terminate fallback is configured" >&2
          exit 1
        fi
      fi
      ;;
    terminate)
      if [[ "$pod_status_before" == "MISSING" ]]; then
        action_applied="none"
      else
        runpodctl remove pod "$pod_id"
        action_applied="terminate"
      fi
      ;;
    none)
      ;;
  esac
fi

pod_info_after="$(runpodctl get pod "$pod_id" --allfields 2>/dev/null || true)"
pod_status_after="$(pod_status_from_output "$pod_info_after")"
pod_status_after="${pod_status_after:-MISSING}"
released_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ "$dry_run" -eq 1 ]]; then
  announce "Dry run only; lease metadata was not updated."
  exit 0
fi

python3 - "$lease_file" "$job_id" "$pod_id" "$profile_key" "$action_applied" "$reason" "$pod_status_before" "$pod_status_after" "$released_at" <<'PY'
import json
import pathlib
import sys

lease_path = pathlib.Path(sys.argv[1])
job_id = sys.argv[2]
pod_id = sys.argv[3]
profile_key = sys.argv[4]
action_applied = sys.argv[5]
reason = sys.argv[6]
status_before = sys.argv[7]
status_after = sys.argv[8]
released_at = sys.argv[9]

payload = {}
if lease_path.exists():
    try:
        payload = json.loads(lease_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        payload = {}

payload.setdefault("job_id", job_id)
payload.setdefault("pod_id", pod_id)
if profile_key:
    payload.setdefault("profile_key", profile_key)
payload.setdefault("cleanup", {})
payload["cleanup"]["last_action"] = action_applied
payload["cleanup"]["last_reason"] = reason
payload["cleanup"]["pod_status_before"] = status_before
payload["cleanup"]["pod_status_after"] = status_after
payload["cleanup"]["released_at"] = released_at

lease_path.parent.mkdir(parents=True, exist_ok=True)
lease_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

pod_name="$(jq -r '.pod_name // empty' "$lease_file" 2>/dev/null || echo "")"
log_event \
  --event "pod_cleaned" \
  --job-id "$job_id" \
  --pod-id "$pod_id" \
  --pod-name "$pod_name" \
  --reason "$reason" \
  --status "$action_applied" \
  --message "pod status ${pod_status_before} -> ${pod_status_after}"

announce "Cleanup complete for $job_id; pod status is now $pod_status_after."
