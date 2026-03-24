#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"

usage() {
  cat <<'EOF'
Usage:
  scripts/runpod_reconcile.sh [--job-id JOB_ID] [--dry-run]

Notes:
  - Scans registry/spool/*_lease.json for unreleased controller leases
  - Collects artifacts for finished tmux sessions and applies the lease cleanup policy
  - Forces cleanup when a lease TTL has expired, covering controller crash recovery
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: missing required command: $1" >&2
    exit 1
  fi
}

job_filter=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --job-id)
      job_filter="${2:-}"
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

require_cmd jq
require_cmd python3
require_cmd runpodctl
require_cmd ssh

log_event() {
  "$SCRIPT_DIR/log_controller_event.sh" "$@" >/dev/null 2>&1 || true
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

lease_epoch() {
  python3 - "$1" <<'PY'
from datetime import datetime, timezone
import sys

text = sys.argv[1]
if not text:
    print("0")
else:
    print(int(datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()))
PY
}

shopt -s nullglob
lease_files=("$REPO_ROOT"/registry/spool/*_lease.json)
shopt -u nullglob

if [[ ${#lease_files[@]} -eq 0 ]]; then
  echo "No active RunPod leases found."
  exit 0
fi

now_epoch="$(date -u +%s)"

for lease_file in "${lease_files[@]}"; do
  job_id="$(jq -r '.job_id // empty' "$lease_file")"
  if [[ -z "$job_id" ]]; then
    continue
  fi

  if [[ -n "$job_filter" && "$job_filter" != "$job_id" ]]; then
    continue
  fi

  released_at="$(jq -r '.cleanup.released_at // empty' "$lease_file")"
  if [[ -n "$released_at" ]]; then
    continue
  fi

  pod_id="$(jq -r '.pod_id // empty' "$lease_file")"
  ssh_host="$(jq -r '.ssh.host // empty' "$lease_file")"
  ssh_port="$(jq -r '.ssh.port // 22' "$lease_file")"
  lease_expires_at="$(jq -r '.lease_expires_at // empty' "$lease_file")"
  expiry_epoch="$(lease_epoch "$lease_expires_at")"

  pod_info="$(runpodctl get pod "$pod_id" --allfields 2>/dev/null || true)"
  pod_status="$(pod_status_from_output "$pod_info")"
  pod_status="${pod_status:-MISSING}"

  echo "Reconciling $job_id on pod $pod_id (status=$pod_status)..."

  if [[ "$pod_status" == "MISSING" || "$pod_status" == "EXITED" ]]; then
    if [[ "$dry_run" -eq 0 ]]; then
      status_reason="$(printf '%s' "$pod_status" | tr '[:upper:]' '[:lower:]')"
      "$SCRIPT_DIR/runpod_cleanup.sh" --job-id "$job_id" --action none --reason "reconcile_${status_reason}"
    fi
    continue
  fi

  session_state="unknown"
  if [[ -n "$ssh_host" ]]; then
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$ssh_port" "$ssh_host" "tmux has-session -t job_${job_id} 2>/dev/null" >/dev/null 2>&1; then
      session_state="running"
    elif ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$ssh_port" "$ssh_host" "true" >/dev/null 2>&1; then
      session_state="finished"
    else
      session_state="unreachable"
    fi
  fi

  if [[ "$session_state" == "finished" ]]; then
    echo "Finished session detected for $job_id."
    if [[ "$dry_run" -eq 0 ]]; then
      "$SCRIPT_DIR/runpod_collect.sh" "$ssh_host" "$ssh_port" "$job_id" || true
      "$SCRIPT_DIR/runpod_cleanup.sh" --job-id "$job_id" --reason "reconcile_completed"
    fi
    continue
  fi

  if [[ "$expiry_epoch" -gt 0 && "$now_epoch" -ge "$expiry_epoch" ]]; then
    echo "Lease TTL exceeded for $job_id."
    if [[ "$dry_run" -eq 0 ]]; then
      log_event \
        --event "lease_ttl_exceeded" \
        --job-id "$job_id" \
        --pod-id "$pod_id" \
        --reason "reconcile_ttl_exceeded" \
        --status "cleanup_pending" \
        --message "reconcile detected an expired controller lease"
      "$SCRIPT_DIR/runpod_cleanup.sh" --job-id "$job_id" --reason "reconcile_ttl_exceeded"
    fi
    continue
  fi

  echo "Lease for $job_id is still active (session_state=$session_state)."
done
