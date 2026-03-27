#!/usr/bin/env bash
set -euo pipefail

# scripts/shadeform_reconcile.sh
# Reconciles stale Shadeform leases via REST API.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
SHADEFORM_API_KEY="${SHADEFORM_API_KEY:-$(cat ~/.shadeform/api_key 2>/dev/null || echo '')}"
SHADEFORM_API="https://api.shadeform.ai/v1"

[ -z "$SHADEFORM_API_KEY" ] && exit 0

dry_run=0; filter_job_id=""
while [[ $# -gt 0 ]]; do
  case "$1" in --job-id) filter_job_id="${2:-}"; shift 2 ;; --dry-run) dry_run=1; shift ;; *) shift ;; esac
done

lease_epoch() {
  python3 -c "
from datetime import datetime,timezone; import sys
try: print(int(datetime.strptime(sys.argv[1],'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc).timestamp()))
except: print(0)
" "${1:-}" 2>/dev/null || echo 0
}

NOW_EPOCH="$(date -u +%s)"

for lease_file in "$REPO_ROOT"/registry/spool/*_lease.json; do
  [ -f "$lease_file" ] || continue
  backend="$(jq -r '.backend // "runpod"' "$lease_file" 2>/dev/null)"
  [ "$backend" = "shadeform" ] || continue

  job_id="$(jq -r '.job_id // empty' "$lease_file")"; [ -n "$job_id" ] || continue
  [ -n "$filter_job_id" ] && [ "$job_id" != "$filter_job_id" ] && continue

  released_at="$(jq -r '.cleanup.released_at // empty' "$lease_file")"
  [ -n "$released_at" ] && continue

  instance_id="$(jq -r '.instance_id // .pod_id // empty' "$lease_file")"
  ssh_host="$(jq -r '.ssh.host // empty' "$lease_file")"
  ssh_port="$(jq -r '.ssh.port // 22' "$lease_file")"
  lease_expires="$(jq -r '.lease_expires_at // empty' "$lease_file")"
  expiry_epoch="$(lease_epoch "$lease_expires")"

  # Check instance status via API
  inst_status="$(curl -s -H "X-API-KEY: $SHADEFORM_API_KEY" "$SHADEFORM_API/instances/$instance_id/info" 2>/dev/null | jq -r '.status // "unknown"' || echo "unknown")"
  echo "Reconciling $job_id instance=$instance_id ($inst_status)..."

  if [[ "$inst_status" = "deleted" ]] || [[ "$inst_status" = "unknown" ]]; then
    [ "$dry_run" -eq 0 ] && "$SCRIPT_DIR/shadeform_cleanup.sh" --job-id "$job_id" --action none --reason "reconcile_deleted"
    continue
  fi

  # Check SSH tmux session
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

  if [[ "$session_state" = "finished" ]]; then
    echo "Finished session for $job_id."
    [ "$dry_run" -eq 0 ] && {
      "$SCRIPT_DIR/runpod_collect.sh" "$ssh_host" "$ssh_port" "$job_id" 2>/dev/null || true
      "$SCRIPT_DIR/shadeform_cleanup.sh" --job-id "$job_id" --reason "reconcile_completed"
    }
    continue
  fi

  if [[ "$expiry_epoch" -gt 0 && "$NOW_EPOCH" -gt "$expiry_epoch" ]]; then
    echo "Lease TTL expired for $job_id."
    [ "$dry_run" -eq 0 ] && "$SCRIPT_DIR/shadeform_cleanup.sh" --job-id "$job_id" --reason "reconcile_ttl_exceeded"
    continue
  fi

  echo "Lease for $job_id still active (session=$session_state)."
done
