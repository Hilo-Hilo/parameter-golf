#!/usr/bin/env bash
set -euo pipefail

# scripts/skypilot_dispatch.sh
# Dispatches a training job via SkyPilot (Shadeform, RunPod, or other backends).
# Same contract as runpod_dispatch.sh: takes job_spec.json, writes lease + SSH spool files.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
PROFILE_FILE="$REPO_ROOT/config/skypilot_profiles.json"

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
require_cmd sky
require_cmd ssh
require_cmd scp

log_event() {
  "$SCRIPT_DIR/log_controller_event.sh" "$@" >/dev/null 2>&1 || true
}

announce() {
  local label="${CONTROLLER_LOG_LABEL:-$JOB_ID}"
  printf '[%s][%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$label" "$*"
}

# ---------------------------------------------------------------------------
# Parse job spec
# ---------------------------------------------------------------------------

BRANCH="$(jq -r '.branch' "$JOB_SPEC")"
COMMIT_SHA="$(jq -r '.commit_sha' "$JOB_SPEC")"
JOB_ID="$(jq -r '.job_id' "$JOB_SPEC")"
REQ_GPU_COUNT="$(jq -r '.resource_profile.gpu_count // empty' "$JOB_SPEC")"
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

# ---------------------------------------------------------------------------
# Load SkyPilot profile
# ---------------------------------------------------------------------------

POD_PREFIX="pg-exp"
if [ "$REQ_GPU_COUNT" = "8" ]; then
  POD_PREFIX="pg-rec"
fi
PROFILE_KEY="$POD_PREFIX"

ACCELERATORS="$(jq -r --arg key "$PROFILE_KEY" '.[$key].accelerators' "$PROFILE_FILE")"
INFRA="$(jq -r --arg key "$PROFILE_KEY" '.[$key].infra // "shadeform"' "$PROFILE_FILE")"
DISK_SIZE="$(jq -r --arg key "$PROFILE_KEY" '.[$key].disk_size // 100' "$PROFILE_FILE")"
IDLE_ACTION="$(jq -r --arg key "$PROFILE_KEY" '.[$key].idle_action // "stop"' "$PROFILE_FILE")"
FAILURE_ACTION="$(jq -r --arg key "$PROFILE_KEY" '.[$key].failure_action // "down"' "$PROFILE_FILE")"
IDLE_GRACE_MINUTES="$(jq -r --arg key "$PROFILE_KEY" '.[$key].idle_grace_minutes // 30' "$PROFILE_FILE")"
LEASE_TTL_MINUTES="$(jq -r --arg key "$PROFILE_KEY" '.[$key].lease_ttl_minutes // 45' "$PROFILE_FILE")"

# ---------------------------------------------------------------------------
# Build cluster name (DNS-safe, max 63 chars)
# ---------------------------------------------------------------------------

CLUSTER_NAME=""

build_cluster_name() {
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

max_total_len = 63
reserved = len(prefix) + len(suffix) + 2
max_slug_len = max(max_total_len - reserved, 1)
slug = slug[:max_slug_len].rstrip("-") or "job"

print(f"{prefix}-{slug}-{suffix}")
PY
}

# ---------------------------------------------------------------------------
# Active leased clusters (to avoid double-booking)
# ---------------------------------------------------------------------------

active_leased_clusters() {
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
    cluster_id = payload.get("cluster_id") or payload.get("pod_id")
    if cluster_id:
        leased.add(cluster_id)

for cid in sorted(leased):
    print(cid)
PY
}

# ---------------------------------------------------------------------------
# Atomic reservation (same pattern as runpod_dispatch.sh)
# ---------------------------------------------------------------------------

reserve_cluster_or_fail() {
  local cluster_id="$1"
  local job_id="$2"
  python3 - "$REPO_ROOT/registry" "$cluster_id" "$job_id" <<'PY'
import fcntl
import json
import pathlib
import sys

registry_dir = pathlib.Path(sys.argv[1])
cluster_id = sys.argv[2]
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
        existing_cid = payload.get("cluster_id") or payload.get("pod_id")
        if existing_cid == cluster_id:
            print("CONFLICT")
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            raise SystemExit(0)

    from datetime import datetime, timezone
    reserved_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lease_path.write_text(
        json.dumps({"job_id": job_id, "cluster_id": cluster_id, "pod_id": cluster_id, "reserved_at": reserved_at, "backend": "skypilot", "cleanup": {}}, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print("RESERVED")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
PY
}

# ---------------------------------------------------------------------------
# Dispatch cleanup trap
# ---------------------------------------------------------------------------

dispatch_cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$CLUSTER_NAME" ]; then
    log_event \
      --event "dispatch_failed" \
      --job-id "$JOB_ID" \
      --pod-id "$CLUSTER_NAME" \
      --branch "$BRANCH" \
      --reason "dispatch_exit" \
      --status "$FAILURE_ACTION" \
      --message "SkyPilot dispatch failed before lease handoff"
    announce "Dispatch failed for $JOB_ID; cleaning up cluster $CLUSTER_NAME with action $FAILURE_ACTION." >&2
    local reservation_lease="$REPO_ROOT/registry/spool/${JOB_ID}_lease.json"
    if [ -f "$reservation_lease" ]; then
      rm -f "$reservation_lease"
    fi
    case "$FAILURE_ACTION" in
      down|terminate)
        sky down "$CLUSTER_NAME" --yes >/dev/null 2>&1 || true
        ;;
      stop)
        sky stop "$CLUSTER_NAME" --yes >/dev/null 2>&1 || true
        ;;
    esac
  fi
}

trap dispatch_cleanup EXIT

# ---------------------------------------------------------------------------
# Find or create a SkyPilot cluster
# ---------------------------------------------------------------------------

CLUSTER_SOURCE="existing"

# Check for existing idle clusters matching our prefix
ACTIVE_LEASED="$(active_leased_clusters | paste -sd, -)"
CLUSTER_NAME="$(
  sky status 2>/dev/null \
    | awk -v prefix="$POD_PREFIX" -v leased="$ACTIVE_LEASED" '
        BEGIN {
          n = split(leased, rows, ",")
          for (i = 1; i <= n; i++) {
            if (rows[i] != "") busy[rows[i]] = 1
          }
        }
        NR > 1 && $1 ~ ("^" prefix) && ($3 == "STOPPED" || $3 == "UP") && !busy[$1] { print $1; exit }
      ' || true
)"

if [ -z "$CLUSTER_NAME" ]; then
  CLUSTER_NAME="$(build_cluster_name)"
  CLUSTER_SOURCE="created"
  announce "No existing $POD_PREFIX cluster found. Will create $CLUSTER_NAME..."
fi

# Reserve the cluster atomically
RESERVE_RESULT="$(reserve_cluster_or_fail "$CLUSTER_NAME" "$JOB_ID")"
if [ "$RESERVE_RESULT" = "CONFLICT" ]; then
  announce "Cluster $CLUSTER_NAME was claimed by another worker. Aborting dispatch." >&2
  CLUSTER_NAME=""
  exit 1
fi

announce "Using cluster $CLUSTER_NAME for $JOB_ID ($CLUSTER_SOURCE)"
log_event \
  --event "pod_selected" \
  --job-id "$JOB_ID" \
  --pod-id "$CLUSTER_NAME" \
  --pod-name "$CLUSTER_NAME" \
  --branch "$BRANCH" \
  --reason "$CLUSTER_SOURCE" \
  --message "selected SkyPilot cluster for dispatch"

# ---------------------------------------------------------------------------
# Generate SkyPilot task YAML
# ---------------------------------------------------------------------------

TASK_YAML="$(mktemp /tmp/skypilot_task_XXXXXXXXXX).yaml"
cat > "$TASK_YAML" <<YAML
resources:
  accelerators: $ACCELERATORS
  disk_size: $DISK_SIZE
  infra: $INFRA

setup: |
  # Ensure /workspace exists and is writable
  sudo mkdir -p /workspace && sudo chmod 777 /workspace
  # System tools
  sudo apt-get update -qq && sudo apt-get install -y -qq git jq tmux rsync || true
  # IMPORTANT: Install to system Python (not the SkyPilot venv) so SSH sessions can find them.
  # Deactivate any venv first, then use sudo pip3 to install system-wide.
  deactivate 2>/dev/null || true
  sudo /usr/bin/pip3 install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cu128 || \
    sudo /usr/bin/pip3 install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cu124 || \
    sudo /usr/bin/pip3 install --no-cache-dir torch
  sudo /usr/bin/pip3 install --no-cache-dir sentencepiece huggingface_hub numpy zstandard || true
  # Flash Attention 3 (required by SOTA PR #549 train_gpt.py)
  sudo /usr/bin/pip3 install --no-cache-dir flash-attn --no-build-isolation 2>/dev/null || \
    sudo /usr/bin/pip3 install --no-cache-dir flash-attn 2>/dev/null || \
    echo "WARNING: flash-attn install failed — SOTA recipe may not work"
  # Verify system python can import torch
  /usr/bin/python3 -c "import torch; print(f'System torch={torch.__version__}, cuda={torch.cuda.is_available()}')"
  # Ensure torchrun is on PATH (sudo pip installs to /usr/local/bin)
  which torchrun || echo "WARNING: torchrun not found on PATH"
YAML

# ---------------------------------------------------------------------------
# Launch or reuse the cluster
# ---------------------------------------------------------------------------

if [ "$CLUSTER_SOURCE" = "created" ]; then
  announce "Creating new SkyPilot cluster $CLUSTER_NAME..."
  sky launch -c "$CLUSTER_NAME" "$TASK_YAML" --yes 2>&1 | tail -5
else
  # Check if cluster is stopped
  CLUSTER_STATUS="$(sky status "$CLUSTER_NAME" 2>/dev/null | awk -v name="$CLUSTER_NAME" 'NR > 1 && $1 == name { print $3; exit }' || echo "UNKNOWN")"
  if [ "$CLUSTER_STATUS" = "STOPPED" ]; then
    announce "Starting stopped cluster $CLUSTER_NAME..."
    sky start "$CLUSTER_NAME" --yes 2>&1 | tail -3
  fi
  announce "Running setup on existing cluster $CLUSTER_NAME..."
  sky exec "$CLUSTER_NAME" "$TASK_YAML" --detach 2>&1 | tail -3
fi

rm -f "$TASK_YAML"

# ---------------------------------------------------------------------------
# Extract SSH connection details from SkyPilot's SSH config
# ---------------------------------------------------------------------------

SSH_USER=""
SSH_HOST=""
SSH_PORT="22"

announce "Extracting SSH details for $CLUSTER_NAME..."
for _ in {1..18}; do
  # SkyPilot writes ~/.ssh/config entries after launch. Parse them.
  SSH_HOST="$(ssh -G "$CLUSTER_NAME" 2>/dev/null | awk '/^hostname / { print $2 }' || true)"
  SSH_PORT="$(ssh -G "$CLUSTER_NAME" 2>/dev/null | awk '/^port / { print $2 }' || echo "22")"
  SSH_USER="$(ssh -G "$CLUSTER_NAME" 2>/dev/null | awk '/^user / { print $2 }' || echo "root")"
  if [ -n "$SSH_HOST" ] && [ "$SSH_HOST" != "$CLUSTER_NAME" ]; then
    break
  fi
  SSH_HOST=""
  sleep 10
done

if [ -z "$SSH_HOST" ]; then
  announce "Error: unable to resolve SSH host for cluster $CLUSTER_NAME" >&2
  exit 1
fi

SSH_TARGET="${SSH_USER}@${SSH_HOST}"

# ---------------------------------------------------------------------------
# Wait for SSH readiness
# ---------------------------------------------------------------------------

# Use the SkyPilot cluster name as SSH target (leverages ~/.ssh/config with
# proxy commands, identity files, etc. that SkyPilot configures).
ssh_remote() {
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$CLUSTER_NAME" "$@"
}

scp_to_remote() {
  scp -o StrictHostKeyChecking=no "$1" "$CLUSTER_NAME:$2"
}

announce "Waiting for SSH on $SSH_TARGET:$SSH_PORT (via $CLUSTER_NAME)..."
for _ in {1..18}; do
  if ssh_remote "echo SSH_READY" >/dev/null 2>&1; then
    break
  fi
  sleep 10
done

if ! ssh_remote "echo SSH_READY" >/dev/null 2>&1; then
  announce "Error: SSH did not become ready for cluster $CLUSTER_NAME" >&2
  exit 1
fi

# Ensure /workspace exists and is writable (Shadeform instances may not have it)
ssh_remote "sudo mkdir -p /workspace && sudo chmod 777 /workspace" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Bootstrap and launch (reuse existing remote scripts)
# ---------------------------------------------------------------------------

ssh_remote "mkdir -p /workspace/scripts"
scp_to_remote "$SCRIPT_DIR/runpod_bootstrap_remote.sh" "/workspace/scripts/runpod_bootstrap_remote.sh"
ssh_remote "chmod +x /workspace/scripts/runpod_bootstrap_remote.sh"

announce "Bootstrapping exact commit $COMMIT_SHA..."
# SkyPilot PATH prefix: pip-installed binaries live in ~/.local/bin on non-root instances
SKY_PATH_PREFIX="export PATH=\$PATH:\$HOME/.local/bin"
# Allow apt fallback since Shadeform instances may lack tools
BOOTSTRAP_CMD="$SKY_PATH_PREFIX && RUNPOD_BOOTSTRAP_ALLOW_APT_FALLBACK=1 /workspace/scripts/runpod_bootstrap_remote.sh $JOB_ID $BRANCH $COMMIT_SHA"
if [ -n "$REMOTE_ENV_SH" ]; then
  BOOTSTRAP_CMD="$SKY_PATH_PREFIX && RUNPOD_BOOTSTRAP_ALLOW_APT_FALLBACK=1 $REMOTE_ENV_SH /workspace/scripts/runpod_bootstrap_remote.sh $JOB_ID $BRANCH $COMMIT_SHA"
fi
ssh_remote "$BOOTSTRAP_CMD"

REMOTE_RUN_SCRIPT="/workspace/jobs/$JOB_ID/scripts/runpod_run_remote.sh"
REQ_GPU_SUBSTRING="$(jq -r '.resource_profile.gpu_type // "H100"' "$JOB_SPEC")"
REMOTE_RUN_CMD="$SKY_PATH_PREFIX && $REMOTE_RUN_SCRIPT $JOB_ID $REQ_GPU_COUNT $(printf '%q' "$REQ_GPU_SUBSTRING") $RUN_ARGV_SH"
if [ -n "$REMOTE_ENV_SH" ]; then
  REMOTE_RUN_CMD="$SKY_PATH_PREFIX && $REMOTE_ENV_SH $REMOTE_RUN_SCRIPT $JOB_ID $REQ_GPU_COUNT $(printf '%q' "$REQ_GPU_SUBSTRING") $RUN_ARGV_SH"
fi

announce "Launching remote job..."
ssh_remote "$REMOTE_RUN_CMD"

# ---------------------------------------------------------------------------
# Write lease and spool files
# ---------------------------------------------------------------------------

mkdir -p "$REPO_ROOT/registry/spool"
# Use the SkyPilot cluster name as SSH target (not raw IP). SkyPilot's
# ~/.ssh/config entry for the cluster has the correct identity key, user,
# and proxy config. Raw ssh user@ip fails without the key.
printf '%s\n' "$CLUSTER_NAME" > "$REPO_ROOT/registry/spool/${JOB_ID}_ssh_target.txt"
printf '%s\n' "22" > "$REPO_ROOT/registry/spool/${JOB_ID}_ssh_port.txt"
printf '%s\n' "$CLUSTER_NAME" > "$REPO_ROOT/registry/spool/${JOB_ID}_pod_id.txt"

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
  --arg cluster_id "$CLUSTER_NAME" \
  --arg pod_id "$CLUSTER_NAME" \
  --arg pod_name "$CLUSTER_NAME" \
  --arg profile_key "$PROFILE_KEY" \
  --arg ssh_host "$CLUSTER_NAME" \
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
    cluster_id: $cluster_id,
    pod_id: $pod_id,
    pod_name: $pod_name,
    profile_key: $profile_key,
    backend: "skypilot",
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
  --pod-id "$CLUSTER_NAME" \
  --pod-name "$CLUSTER_NAME" \
  --branch "$BRANCH" \
  --ssh-host "root@$SSH_HOST" \
  --ssh-port "$SSH_PORT" \
  --status "lease_active" \
  --message "SkyPilot bootstrap and tmux launch completed"

trap - EXIT
announce "Job dispatched successfully."
