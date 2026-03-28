#!/usr/bin/env bash
set -euo pipefail

# scripts/shadeform_reconcile.sh
# Reconciles stale Shadeform leases via REST API.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
SHADEFORM_API_KEY="${SHADEFORM_API_KEY:-$(cat ~/.shadeform/api_key 2>/dev/null || echo '')}"
SHADEFORM_API="https://api.shadeform.ai/v1"

[ -z "$SHADEFORM_API_KEY" ] && exit 0

SSH_KEY_FILE="${SHADEFORM_SSH_KEY_FILE:-$HOME/.shadeform/ssh_key}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
SSH_ID_OPT=()
[ -f "$SSH_KEY_FILE" ] && SSH_ID_OPT=(-i "$SSH_KEY_FILE")

dry_run=0; filter_job_id=""
while [[ $# -gt 0 ]]; do
  case "$1" in --job-id) filter_job_id="${2:-}"; shift 2 ;; --dry-run) dry_run=1; shift ;; *) shift ;; esac
done

# Get the running Docker container ID on a Shadeform host VM.
get_container_id() {
  local ssh_host="$1" ssh_port="$2"
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "${SSH_ID_OPT[@]}" -p "$ssh_port" "$ssh_host" "docker ps --format '{{.ID}}' | head -1" 2>/dev/null || echo ''
}

# Copy experiment artifacts directly from the container to the Mac via tar pipe
# over SSH. Bypasses the host VM filesystem (which has no /workspace).
pre_collect_from_container() {
  local job_id="$1" ssh_host="$2" ssh_port="$3" cid="$4"
  [ -z "$cid" ] && return 0
  local local_exp_parent="$REPO_ROOT/experiments"
  local local_spool_dir="$REPO_ROOT/registry/spool"
  mkdir -p "$local_exp_parent" "$local_spool_dir"
  for src in "/workspace/parameter-golf/experiments/$job_id" \
             "/workspace/jobs/$job_id/experiments/$job_id"; do
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "${SSH_ID_OPT[@]}" -p "$ssh_port" "$ssh_host" \
      "docker exec \"$cid\" test -d \"$src\" 2>/dev/null && docker cp \"$cid\":\"$src\" - 2>/dev/null" \
      2>/dev/null | tar xf - -C "$local_exp_parent/" 2>/dev/null || true
  done
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "${SSH_ID_OPT[@]}" -p "$ssh_port" "$ssh_host" \
    "docker exec \"$cid\" test -f \"/workspace/parameter-golf/registry/spool/${job_id}.json\" 2>/dev/null && \
     docker cp \"$cid\":\"/workspace/parameter-golf/registry/spool/${job_id}.json\" - 2>/dev/null" \
    2>/dev/null | tar xf - -C "$local_spool_dir/" 2>/dev/null || true
}

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

  if [[ "$inst_status" = "deleted" ]]; then
    [ "$dry_run" -eq 0 ] && "$SCRIPT_DIR/shadeform_cleanup.sh" --job-id "$job_id" --action none --reason "reconcile_deleted"
    continue
  fi
  if [[ "$inst_status" = "unknown" ]]; then
    # API call failed transiently — skip this cycle rather than prematurely releasing the lease.
    echo "API returned unknown status for $job_id; skipping cycle."
    continue
  fi

  # Check tmux session inside the Docker container (SSH connects to host VM).
  session_state="unknown"
  container_id=""
  if [[ -n "$ssh_host" ]]; then
    # shellcheck disable=SC2086
    if ssh $SSH_OPTS "${SSH_ID_OPT[@]}" -p "$ssh_port" "$ssh_host" "true" >/dev/null 2>&1; then
      container_id="$(get_container_id "$ssh_host" "$ssh_port")"
      if [[ -n "$container_id" ]]; then
        # shellcheck disable=SC2086
        if ssh $SSH_OPTS "${SSH_ID_OPT[@]}" -p "$ssh_port" "$ssh_host" \
            "docker exec \"$container_id\" tmux has-session -t job_${job_id} 2>/dev/null" >/dev/null 2>&1; then
          session_state="running"
        else
          session_state="finished"
        fi
      else
        # Container not running — instance may be booting or crashed
        session_state="finished"
      fi
    else
      session_state="unreachable"
    fi
  fi

  if [[ "$session_state" = "finished" ]]; then
    echo "Finished session for $job_id."
    [ "$dry_run" -eq 0 ] && {
      pre_collect_from_container "$job_id" "$ssh_host" "$ssh_port" "$container_id"
      SSH_IDENTITY_FILE="$SSH_KEY_FILE" "$SCRIPT_DIR/runpod_collect.sh" "$ssh_host" "$ssh_port" "$job_id" 2>/dev/null || true
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
