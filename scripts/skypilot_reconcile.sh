#!/usr/bin/env bash
set -euo pipefail

# scripts/skypilot_reconcile.sh
# Reconciles stale SkyPilot leases. Only processes leases with backend=="skypilot".
# Same role as runpod_reconcile.sh but uses `sky status` instead of `runpodctl`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"

dry_run=0
filter_job_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --job-id) filter_job_id="${2:-}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) shift ;;
  esac
done

if ! command -v sky >/dev/null 2>&1; then
  exit 0
fi

lease_epoch() {
  python3 -c "
from datetime import datetime, timezone
import sys
try:
    dt = datetime.strptime(sys.argv[1], '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
    print(int(dt.timestamp()))
except:
    print(0)
" "${1:-}" 2>/dev/null || echo 0
}

NOW_EPOCH="$(date -u +%s)"

for lease_file in "$REPO_ROOT"/registry/spool/*_lease.json; do
  [ -f "$lease_file" ] || continue

  backend="$(jq -r '.backend // "runpod"' "$lease_file" 2>/dev/null)"
  [ "$backend" = "skypilot" ] || continue

  job_id="$(jq -r '.job_id // empty' "$lease_file")"
  [ -n "$job_id" ] || continue
  if [ -n "$filter_job_id" ] && [ "$job_id" != "$filter_job_id" ]; then
    continue
  fi

  released_at="$(jq -r '.cleanup.released_at // empty' "$lease_file")"
  if [[ -n "$released_at" ]]; then
    continue
  fi

  cluster_id="$(jq -r '.cluster_id // .pod_id // empty' "$lease_file")"
  ssh_host="$(jq -r '.ssh.host // empty' "$lease_file")"
  ssh_port="$(jq -r '.ssh.port // 22' "$lease_file")"
  lease_expires_at="$(jq -r '.lease_expires_at // empty' "$lease_file")"
  expiry_epoch="$(lease_epoch "$lease_expires_at")"

  # Check cluster status via sky
  cluster_status="$(sky status "$cluster_id" 2>/dev/null \
    | awk -v name="$cluster_id" 'NR > 1 && $1 == name { print $3; exit }' || echo "MISSING")"
  cluster_status="${cluster_status:-MISSING}"

  echo "Reconciling $job_id on cluster $cluster_id (status=$cluster_status)..."

  # Cluster gone or stopped
  if [[ "$cluster_status" == "MISSING" || "$cluster_status" == "STOPPED" ]]; then
    if [[ "$dry_run" -eq 0 ]]; then
      "$SCRIPT_DIR/skypilot_cleanup.sh" --job-id "$job_id" --action none --reason "reconcile_${cluster_status,,}"
    fi
    continue
  fi

  # Check tmux session via SSH
  session_state="unknown"
  if [[ -n "$ssh_host" ]]; then
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$ssh_port" "$ssh_host" "tmux has-session -t job_${job_id} 2>/dev/null" >/dev/null 2>&1; then
      session_state="running"
    elif ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$ssh_port" "$ssh_host" "true" >/dev/null 2>&1; then
      session_state="finished"
    else
      # Try SkyPilot cluster name as SSH target
      if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$cluster_id" "tmux has-session -t job_${job_id} 2>/dev/null" >/dev/null 2>&1; then
        session_state="running"
      elif ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$cluster_id" "true" >/dev/null 2>&1; then
        session_state="finished"
      else
        session_state="unreachable"
      fi
    fi
  fi

  # Finished session: collect and cleanup
  if [[ "$session_state" == "finished" ]]; then
    echo "Finished session detected for $job_id."
    if [[ "$dry_run" -eq 0 ]]; then
      "$SCRIPT_DIR/runpod_collect.sh" "$job_id" "$ssh_host" "$ssh_port" 2>/dev/null || true
      "$SCRIPT_DIR/skypilot_cleanup.sh" --job-id "$job_id" --reason "reconcile_completed"
    fi
    continue
  fi

  # TTL expired: force cleanup
  if [[ "$expiry_epoch" -gt 0 && "$NOW_EPOCH" -gt "$expiry_epoch" ]]; then
    echo "Lease TTL expired for $job_id."
    if [[ "$dry_run" -eq 0 ]]; then
      "$SCRIPT_DIR/skypilot_cleanup.sh" --job-id "$job_id" --reason "reconcile_ttl_exceeded"
    fi
    continue
  fi

  # Orphaned reservation (no SSH info, older than 10 min)
  if [[ -z "$ssh_host" ]]; then
    reserved_at="$(jq -r '.reserved_at // empty' "$lease_file")"
    if [[ -n "$reserved_at" ]]; then
      reserved_epoch="$(lease_epoch "$reserved_at")"
      if [[ "$((NOW_EPOCH - reserved_epoch))" -gt 600 ]]; then
        echo "Orphaned reservation detected for $job_id."
        if [[ "$dry_run" -eq 0 ]]; then
          "$SCRIPT_DIR/skypilot_cleanup.sh" --job-id "$job_id" --action down --reason "reconcile_orphaned_reservation"
        fi
        continue
      fi
    fi
  fi

  echo "Lease for $job_id is still active (session_state=$session_state)."
done
