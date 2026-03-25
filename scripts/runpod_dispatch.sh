#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
PROFILE_FILE="$REPO_ROOT/config/runpod_profiles.json"

usage() {
  echo "Usage: $0 <job_spec.json>" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: missing required command: $1" >&2
    exit 1
  fi
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

JOB_SPEC="$1"
if [ ! -f "$JOB_SPEC" ]; then
  echo "Error: job spec $JOB_SPEC not found." >&2
  exit 1
fi

require_cmd jq
require_cmd python3
require_cmd runpodctl
require_cmd ssh
require_cmd scp

log_event() {
  "$SCRIPT_DIR/log_controller_event.sh" "$@" >/dev/null 2>&1 || true
}

announce() {
  local label="${CONTROLLER_LOG_LABEL:-$JOB_ID}"
  printf '[%s][%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$label" "$*"
}

active_leased_pods() {
  python3 - "$REPO_ROOT/registry/spool" <<'PY'
import json
import pathlib
import sys

spool_dir = pathlib.Path(sys.argv[1])
if not spool_dir.exists():
    raise SystemExit(0)

leased = set()
for lease_path in spool_dir.glob("*_lease.json"):
    try:
        payload = json.loads(lease_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        continue
    cleanup = payload.get("cleanup", {})
    if cleanup.get("released_at"):
        continue
    pod_id = payload.get("pod_id")
    if pod_id:
        leased.add(pod_id)

for pod_id in sorted(leased):
    print(pod_id)
PY
}

# Atomically reserve a pod under an exclusive lock so concurrent dispatches
# cannot double-book the same pod.  Writes a minimal reservation lease that
# the full lease write later overwrites.
reserve_pod_or_fail() {
  local pod_id="$1"
  local job_id="$2"
  python3 - "$REPO_ROOT/registry" "$pod_id" "$job_id" <<'PY'
import fcntl
import json
import pathlib
import sys

registry_dir = pathlib.Path(sys.argv[1])
pod_id = sys.argv[2]
job_id = sys.argv[3]

spool_dir = registry_dir / "spool"
lock_path = registry_dir / ".pod_dispatch.lock"
lease_path = spool_dir / f"{job_id}_lease.json"

lock_path.parent.mkdir(parents=True, exist_ok=True)
spool_dir.mkdir(parents=True, exist_ok=True)
lock_path.touch(exist_ok=True)

with lock_path.open("a+", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

    for existing_lease in spool_dir.glob("*_lease.json"):
        try:
            payload = json.loads(existing_lease.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        if payload.get("cleanup", {}).get("released_at"):
            continue
        if payload.get("pod_id") == pod_id:
            print("CONFLICT")
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            raise SystemExit(0)

    from datetime import datetime, timezone
    reserved_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lease_path.write_text(
        json.dumps({"job_id": job_id, "pod_id": pod_id, "reserved_at": reserved_at, "cleanup": {}}, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print("RESERVED")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
PY
}

BRANCH="$(jq -r '.branch' "$JOB_SPEC")"
COMMIT_SHA="$(jq -r '.commit_sha' "$JOB_SPEC")"
JOB_ID="$(jq -r '.job_id' "$JOB_SPEC")"
REQ_GPU_COUNT="$(jq -r '.resource_profile.gpu_count // empty' "$JOB_SPEC")"
REQ_GPU_SUBSTRING="$(jq -r '.resource_profile.gpu_type // "H100"' "$JOB_SPEC")"
ENV_OVERRIDES_JSON="$(jq -c '.env_overrides // {}' "$JOB_SPEC")"

RUN_ARGV_JSON="$(jq -c '.run_argv // []' "$JOB_SPEC")"
RUN_ARGV_SH="$(python3 - "$RUN_ARGV_JSON" <<'PY'
import json
import shlex
import sys

argv = json.loads(sys.argv[1])
print(" ".join(shlex.quote(arg) for arg in argv))
PY
)"

REMOTE_ENV_SH="$(python3 - "$ENV_OVERRIDES_JSON" <<'PY'
import json
import re
import shlex
import sys

payload = json.loads(sys.argv[1])
parts = []
for key, value in sorted(payload.items()):
    if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", key):
        raise SystemExit(f"invalid env override key: {key}")
    parts.append(f"{key}={shlex.quote(str(value))}")
print(" ".join(parts))
PY
)"

if [ -z "$REQ_GPU_COUNT" ] || [ "$REQ_GPU_COUNT" = "null" ]; then
  echo "Error: job spec is missing resource_profile.gpu_count" >&2
  exit 1
fi

POD_PREFIX="pg-exp"
if [ "$REQ_GPU_COUNT" = "8" ]; then
  POD_PREFIX="pg-rec"
fi
PROFILE_KEY="$POD_PREFIX"

IDLE_ACTION="$(jq -r --arg key "$PROFILE_KEY" '.[$key].idle_action // "stop"' "$PROFILE_FILE")"
FAILURE_ACTION="$(jq -r --arg key "$PROFILE_KEY" '.[$key].failure_action // "terminate"' "$PROFILE_FILE")"
IDLE_GRACE_MINUTES="$(jq -r --arg key "$PROFILE_KEY" '.[$key].idle_grace_minutes // 30' "$PROFILE_FILE")"
LEASE_TTL_MINUTES="$(jq -r --arg key "$PROFILE_KEY" '.[$key].lease_ttl_minutes // 45' "$PROFILE_FILE")"
POD_ID=""
POD_NAME=""
POD_SOURCE="existing"

build_pod_name() {
  local suffix
  suffix="$(date -u +%H%M%S)"

  python3 - "$POD_PREFIX" "$JOB_ID" "$suffix" <<'PY'
import re
import sys

prefix = sys.argv[1]
job_id = sys.argv[2]
suffix = sys.argv[3]

slug = re.sub(r"[^a-z0-9]+", "-", job_id.lower())
slug = re.sub(r"-+", "-", slug).strip("-") or "job"

# Keep pod names concise and stable while preserving a timestamp suffix for uniqueness.
max_total_len = 63
reserved = len(prefix) + len(suffix) + 2  # two separators
max_slug_len = max(max_total_len - reserved, 1)
slug = slug[:max_slug_len].rstrip("-") or "job"

print(f"{prefix}-{slug}-{suffix}")
PY
}

dispatch_cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$POD_ID" ]; then
    log_event \
      --event "dispatch_failed" \
      --job-id "$JOB_ID" \
      --pod-id "$POD_ID" \
      --pod-name "$POD_NAME" \
      --branch "$BRANCH" \
      --reason "dispatch_exit" \
      --status "$FAILURE_ACTION" \
      --message "launch path failed before lease handoff completed"
    announce "Dispatch failed for $JOB_ID; cleaning up pod $POD_ID with action $FAILURE_ACTION." >&2
    # Remove the reservation lease so the pod is freed for other workers.
    local reservation_lease="$REPO_ROOT/registry/spool/${JOB_ID}_lease.json"
    if [ -f "$reservation_lease" ]; then
      rm -f "$reservation_lease"
    fi
    case "$FAILURE_ACTION" in
      terminate)
        runpodctl remove pod "$POD_ID" >/dev/null 2>&1 || true
        ;;
      stop)
        runpodctl stop pod "$POD_ID" >/dev/null 2>&1 || true
        ;;
    esac
  fi
}

trap dispatch_cleanup EXIT

if [ -n "${RUNPOD_POD_ID:-}" ]; then
  POD_ID="$RUNPOD_POD_ID"
  POD_SOURCE="override"
else
  # Convert leased pod IDs to a comma-separated string so macOS awk
  # can parse it without newline-in-variable issues.
  ACTIVE_LEASED_PODS="$(active_leased_pods | paste -sd, -)"
  POD_ID="$(
    runpodctl get pod \
      | awk -v prefix="$POD_PREFIX" -v leased="$ACTIVE_LEASED_PODS" '
          BEGIN {
            n = split(leased, rows, ",")
            for (i = 1; i <= n; i++) {
              if (rows[i] != "") busy[rows[i]] = 1
            }
          }
          NR > 1 && $2 ~ ("^" prefix) && !busy[$1] { print $1; exit }
        '
  )"
fi

if [ -z "$POD_ID" ]; then
  POD_NAME="$(build_pod_name)"
  announce "No existing $POD_PREFIX pod found. Creating $POD_NAME..."
  "$SCRIPT_DIR/runpod_pool.sh" create "$POD_NAME"
  sleep 10
  POD_SOURCE="created"
  POD_ID="$(
    runpodctl get pod \
      | awk -v name="$POD_NAME" 'NR > 1 && $2 == name { print $1; exit }'
  )"
fi

if [ -z "$POD_ID" ]; then
  echo "Error: unable to resolve a RunPod pod ID for this job." >&2
  exit 1
fi

# Atomically reserve the pod so concurrent dispatches cannot double-book it.
RESERVE_RESULT="$(reserve_pod_or_fail "$POD_ID" "$JOB_ID")"
if [ "$RESERVE_RESULT" = "CONFLICT" ]; then
  announce "Pod $POD_ID was claimed by another worker. Aborting dispatch." >&2
  POD_ID=""
  exit 1
fi

announce "Using pod $POD_ID for $JOB_ID"
if [ -z "$POD_NAME" ]; then
  POD_NAME="$(runpodctl get pod "$POD_ID" --allfields 2>/dev/null | awk 'NR == 2 { print $2 }')"
fi
log_event \
  --event "pod_selected" \
  --job-id "$JOB_ID" \
  --pod-id "$POD_ID" \
  --pod-name "$POD_NAME" \
  --branch "$BRANCH" \
  --reason "$POD_SOURCE" \
  --message "selected controller pod for dispatch"
runpodctl start pod "$POD_ID" >/dev/null 2>&1 || true

SSH_CONNECT=""
for _ in {1..18}; do
  SSH_CONNECT="$(runpodctl ssh connect "$POD_ID" 2>/dev/null || true)"
  if [[ "$SSH_CONNECT" == ssh\ * ]]; then
    break
  fi
  sleep 10
done

if [[ "$SSH_CONNECT" != ssh\ * ]]; then
  announce "Error: unable to resolve an SSH command for pod $POD_ID: $SSH_CONNECT" >&2
  exit 1
fi

SSH_HOST="$(printf '%s\n' "$SSH_CONNECT" | awk '{print $2}')"
SSH_PORT="$(printf '%s\n' "$SSH_CONNECT" | awk '{print $4}')"

if [ -z "$SSH_HOST" ] || [ -z "$SSH_PORT" ]; then
  announce "Error: unable to parse SSH details from: $SSH_CONNECT" >&2
  exit 1
fi

ssh_remote() {
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_HOST" "$@"
}

scp_to_remote() {
  scp -o StrictHostKeyChecking=no -P "$SSH_PORT" "$1" "$SSH_HOST:$2"
}

announce "Waiting for SSH on $SSH_HOST:$SSH_PORT..."
for _ in {1..18}; do
  if ssh_remote "echo SSH_READY" >/dev/null 2>&1; then
    break
  fi
  sleep 10
done

if ! ssh_remote "echo SSH_READY" >/dev/null 2>&1; then
  announce "Error: SSH did not become ready for pod $POD_ID" >&2
  exit 1
fi

ssh_remote "mkdir -p /workspace/scripts"
scp_to_remote "$SCRIPT_DIR/runpod_bootstrap_remote.sh" "/workspace/scripts/runpod_bootstrap_remote.sh"
ssh_remote "chmod +x /workspace/scripts/runpod_bootstrap_remote.sh"

announce "Bootstrapping exact commit $COMMIT_SHA..."
BOOTSTRAP_CMD="/workspace/scripts/runpod_bootstrap_remote.sh $JOB_ID $BRANCH $COMMIT_SHA"
if [ -n "$REMOTE_ENV_SH" ]; then
  BOOTSTRAP_CMD="$REMOTE_ENV_SH $BOOTSTRAP_CMD"
fi
ssh_remote "$BOOTSTRAP_CMD"

REMOTE_RUN_SCRIPT="/workspace/jobs/$JOB_ID/scripts/runpod_run_remote.sh"
REMOTE_RUN_CMD="$REMOTE_RUN_SCRIPT $JOB_ID $REQ_GPU_COUNT $(printf '%q' "$REQ_GPU_SUBSTRING") $RUN_ARGV_SH"
if [ -n "$REMOTE_ENV_SH" ]; then
  REMOTE_RUN_CMD="$REMOTE_ENV_SH $REMOTE_RUN_CMD"
fi

announce "Launching remote job..."
ssh_remote "$REMOTE_RUN_CMD"

mkdir -p "$REPO_ROOT/registry/spool"
printf '%s\n' "$SSH_HOST" > "$REPO_ROOT/registry/spool/${JOB_ID}_ssh_target.txt"
printf '%s\n' "$SSH_PORT" > "$REPO_ROOT/registry/spool/${JOB_ID}_ssh_port.txt"
printf '%s\n' "$POD_ID" > "$REPO_ROOT/registry/spool/${JOB_ID}_pod_id.txt"
DISPATCHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
LEASE_EXPIRES_AT="$(python3 - "$DISPATCHED_AT" "$LEASE_TTL_MINUTES" <<'PY'
from datetime import datetime, timedelta, timezone
import sys

dispatched_at = datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
lease_ttl_minutes = int(sys.argv[2])
print((dispatched_at + timedelta(minutes=lease_ttl_minutes)).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"

jq -n \
  --arg job_id "$JOB_ID" \
  --arg branch "$BRANCH" \
  --arg commit_sha "$COMMIT_SHA" \
  --arg pod_id "$POD_ID" \
  --arg pod_name "$POD_NAME" \
  --arg profile_key "$PROFILE_KEY" \
  --arg ssh_host "$SSH_HOST" \
  --argjson ssh_port "$SSH_PORT" \
  --arg dispatched_at "$DISPATCHED_AT" \
  --arg lease_expires_at "$LEASE_EXPIRES_AT" \
  --arg idle_action "$IDLE_ACTION" \
  --arg failure_action "$FAILURE_ACTION" \
  --argjson idle_grace_minutes "$IDLE_GRACE_MINUTES" \
  --argjson lease_ttl_minutes "$LEASE_TTL_MINUTES" \
  --argjson run_argv "$RUN_ARGV_JSON" \
  '{
    job_id: $job_id,
    branch: $branch,
    commit_sha: $commit_sha,
    pod_id: $pod_id,
    pod_name: $pod_name,
    profile_key: $profile_key,
    ssh: {
      host: $ssh_host,
      port: $ssh_port
    },
    dispatched_at: $dispatched_at,
    lease_expires_at: $lease_expires_at,
    run_argv: $run_argv,
    cleanup: {
      default_action: $idle_action,
      failure_action: $failure_action,
      idle_grace_minutes: $idle_grace_minutes,
      lease_ttl_minutes: $lease_ttl_minutes
    }
  }' > "$REPO_ROOT/registry/spool/${JOB_ID}_lease.json"

log_event \
  --event "job_dispatched" \
  --job-id "$JOB_ID" \
  --pod-id "$POD_ID" \
  --pod-name "$POD_NAME" \
  --branch "$BRANCH" \
  --ssh-host "$SSH_HOST" \
  --ssh-port "$SSH_PORT" \
  --status "lease_active" \
  --message "remote bootstrap and tmux launch completed"

trap - EXIT
announce "Job dispatched successfully."
