#!/usr/bin/env bash
set -euo pipefail

# scripts/skypilot_cleanup.sh
# Cleans up SkyPilot clusters after job completion or failure.
# Same interface as runpod_cleanup.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"

usage() {
  cat <<'EOF'
Usage:
  scripts/skypilot_cleanup.sh --job-id JOB_ID [--action stop|down|terminate|none] [--reason TEXT] [--dry-run]

Notes:
  - Reads lease metadata from registry/spool/<job_id>_lease.json
  - "terminate" is accepted as an alias for "down" (SkyPilot vocabulary)
  - Defaults to the lease's cleanup policy
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
require_cmd sky

log_event() {
  "$SCRIPT_DIR/log_controller_event.sh" "$@" >/dev/null 2>&1 || true
}

announce() {
  local label="${CONTROLLER_LOG_LABEL:-$job_id}"
  printf '[%s][%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$label" "$*"
}

# ---------------------------------------------------------------------------
# Load lease metadata
# ---------------------------------------------------------------------------

lease_file="$REPO_ROOT/registry/spool/${job_id}_lease.json"
cluster_id=""
profile_key=""
default_action="stop"
failure_action="down"

if [[ -f "$lease_file" ]]; then
  cluster_id="$(jq -r '.cluster_id // .pod_id // empty' "$lease_file")"
  profile_key="$(jq -r '.profile_key // empty' "$lease_file")"
  default_action="$(jq -r '.cleanup.default_action // "stop"' "$lease_file")"
  failure_action="$(jq -r '.cleanup.failure_action // "down"' "$lease_file")"
fi

if [[ -z "$cluster_id" && -f "$REPO_ROOT/registry/spool/${job_id}_pod_id.txt" ]]; then
  cluster_id="$(<"$REPO_ROOT/registry/spool/${job_id}_pod_id.txt")"
fi

if [[ -z "$cluster_id" ]]; then
  echo "Error: unable to resolve cluster ID for $job_id" >&2
  exit 1
fi

# Map "terminate" to "down" for SkyPilot vocabulary
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

# Normalize
case "$action" in
  terminate) action="down" ;;
  stop|down|none) ;;
  *)
    echo "Error: invalid --action $action" >&2
    exit 2
    ;;
esac

# ---------------------------------------------------------------------------
# Check cluster status
# ---------------------------------------------------------------------------

cluster_status_before="UNKNOWN"
cluster_status_before="$(sky status "$cluster_id" 2>/dev/null \
  | awk -v name="$cluster_id" 'NR > 1 && $1 == name { print $3; exit }' || echo "MISSING")"
cluster_status_before="${cluster_status_before:-MISSING}"
action_applied="$action"

announce "Cleanup for $job_id on cluster $cluster_id ($cluster_status_before), action=$action, reason=$reason"

# ---------------------------------------------------------------------------
# Apply action
# ---------------------------------------------------------------------------

if [[ "$dry_run" -eq 0 ]]; then
  case "$action" in
    stop)
      if [[ "$cluster_status_before" == "MISSING" || "$cluster_status_before" == "STOPPED" ]]; then
        action_applied="none"
      elif sky stop "$cluster_id" --yes 2>/dev/null; then
        action_applied="stop"
      else
        if [[ "$failure_action" == "down" ]]; then
          sky down "$cluster_id" --yes 2>/dev/null || true
          action_applied="down_after_stop_failure"
        else
          announce "Error: stop failed for cluster $cluster_id" >&2
          exit 1
        fi
      fi
      ;;
    down)
      if [[ "$cluster_status_before" == "MISSING" ]]; then
        action_applied="none"
      else
        sky down "$cluster_id" --yes 2>/dev/null || true
        action_applied="down"
      fi
      ;;
    none)
      ;;
  esac
fi

# Check status after action
cluster_status_after="$(sky status "$cluster_id" 2>/dev/null \
  | awk -v name="$cluster_id" 'NR > 1 && $1 == name { print $3; exit }' || echo "MISSING")"
cluster_status_after="${cluster_status_after:-MISSING}"
released_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ "$dry_run" -eq 1 ]]; then
  announce "Dry run only; lease metadata was not updated."
  exit 0
fi

# ---------------------------------------------------------------------------
# Update lease metadata
# ---------------------------------------------------------------------------

python3 - "$lease_file" "$job_id" "$cluster_id" "$profile_key" "$action_applied" "$reason" "$cluster_status_before" "$cluster_status_after" "$released_at" <<'PY'
import json
import pathlib
import sys

lease_path = pathlib.Path(sys.argv[1])
job_id = sys.argv[2]
cluster_id = sys.argv[3]
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
payload.setdefault("cluster_id", cluster_id)
payload.setdefault("pod_id", cluster_id)
payload.setdefault("backend", "skypilot")
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

log_event \
  --event "pod_cleaned" \
  --job-id "$job_id" \
  --pod-id "$cluster_id" \
  --pod-name "$cluster_id" \
  --reason "$reason" \
  --status "$action_applied" \
  --message "cluster status ${cluster_status_before} -> ${cluster_status_after}"

announce "Cleanup complete for $job_id; cluster status is now $cluster_status_after."
