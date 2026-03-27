#!/usr/bin/env bash
set -euo pipefail

# scripts/shadeform_cleanup.sh
# Cleans up Shadeform instances via REST API.
# Same interface as runpod_cleanup.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
SHADEFORM_API_KEY="${SHADEFORM_API_KEY:-$(cat ~/.shadeform/api_key 2>/dev/null || echo '')}"
SHADEFORM_API="https://api.shadeform.ai/v1"

usage() { cat <<'EOF'
Usage: scripts/shadeform_cleanup.sh --job-id JOB_ID [--action down|none] [--reason TEXT] [--dry-run]
EOF
}

job_id=""; action=""; reason="manual"; dry_run=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --job-id) job_id="${2:-}"; shift 2 ;;
    --action) action="${2:-}"; shift 2 ;;
    --reason) reason="${2:-}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) shift ;;
  esac
done
[[ -z "$job_id" ]] && { echo "Error: --job-id required" >&2; exit 2; }

log_event() { "$SCRIPT_DIR/log_controller_event.sh" "$@" >/dev/null 2>&1 || true; }
announce() { printf '[%s][%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${CONTROLLER_LOG_LABEL:-$job_id}" "$*"; }

# Load lease
lease_file="$REPO_ROOT/registry/spool/${job_id}_lease.json"
instance_id=""; default_action="none"; failure_action="down"
if [[ -f "$lease_file" ]]; then
  instance_id="$(jq -r '.instance_id // .pod_id // empty' "$lease_file")"
  default_action="$(jq -r '.cleanup.default_action // "none"' "$lease_file")"
  failure_action="$(jq -r '.cleanup.failure_action // "down"' "$lease_file")"
fi
[[ -z "$instance_id" ]] && { echo "Error: no instance_id for $job_id" >&2; exit 1; }

# Determine action
if [[ -z "$action" ]]; then
  case "$reason" in
    controller_exit|dispatch_failed|controller_ttl_exceeded|collect_failed|job_failed) action="$failure_action" ;;
    *) action="$default_action" ;;
  esac
fi
case "$action" in stop) action="none" ;; terminate) action="down" ;; esac

# Check instance status via API
status_before="unknown"
if [[ -n "$SHADEFORM_API_KEY" ]]; then
  status_before="$(curl -s -H "X-API-KEY: $SHADEFORM_API_KEY" "$SHADEFORM_API/instances/$instance_id/info" 2>/dev/null | jq -r '.status // "unknown"' || echo "unknown")"
fi
action_applied="$action"

announce "Cleanup $job_id instance=$instance_id ($status_before), action=$action, reason=$reason"

if [[ "$dry_run" -eq 0 ]]; then
  case "$action" in
    down)
      if [[ "$status_before" = "deleted" ]] || [[ "$status_before" = "unknown" ]]; then
        action_applied="none"
      else
        curl -s -X POST -H "X-API-KEY: $SHADEFORM_API_KEY" "$SHADEFORM_API/instances/$instance_id/delete" >/dev/null 2>&1 || true
        action_applied="down"
      fi
      ;;
    none) ;;
  esac
fi

# Check status after
status_after="$(curl -s -H "X-API-KEY: $SHADEFORM_API_KEY" "$SHADEFORM_API/instances/$instance_id/info" 2>/dev/null | jq -r '.status // "unknown"' || echo "unknown")"
released_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

[[ "$dry_run" -eq 1 ]] && { announce "Dry run; no changes."; exit 0; }

# Update lease
python3 - "$lease_file" "$job_id" "$instance_id" "$action_applied" "$reason" "$status_before" "$status_after" "$released_at" <<'PY'
import json, pathlib, sys
lp = pathlib.Path(sys.argv[1])
payload = json.loads(lp.read_text()) if lp.exists() else {}
payload.setdefault("job_id", sys.argv[2])
payload.setdefault("instance_id", sys.argv[3])
payload.setdefault("pod_id", sys.argv[3])
payload.setdefault("backend", "shadeform")
payload.setdefault("cleanup", {})
payload["cleanup"]["last_action"] = sys.argv[4]
payload["cleanup"]["last_reason"] = sys.argv[5]
payload["cleanup"]["pod_status_before"] = sys.argv[6]
payload["cleanup"]["pod_status_after"] = sys.argv[7]
payload["cleanup"]["released_at"] = sys.argv[8]
lp.parent.mkdir(parents=True, exist_ok=True)
lp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

log_event --event "pod_cleaned" --job-id "$job_id" --pod-id "$instance_id" \
  --reason "$reason" --status "$action_applied" --message "instance $status_before -> $status_after"
announce "Cleanup complete; instance $status_after."
