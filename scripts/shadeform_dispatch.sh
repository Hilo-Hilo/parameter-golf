#!/usr/bin/env bash
set -euo pipefail

# scripts/shadeform_dispatch.sh
# Dispatches training jobs via direct Shadeform REST API.
# Same contract as runpod_dispatch.sh: takes job_spec.json, writes lease + SSH spool files.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
PROFILE_FILE="$REPO_ROOT/config/shadeform_profiles.json"
SHADEFORM_API_KEY="${SHADEFORM_API_KEY:-$(cat ~/.shadeform/api_key 2>/dev/null || echo '')}"
SHADEFORM_API="https://api.shadeform.ai/v1"

if [ -z "$SHADEFORM_API_KEY" ]; then
  echo "Error: SHADEFORM_API_KEY not set and ~/.shadeform/api_key not found." >&2
  exit 1
fi

usage() { echo "Usage: $0 <job_spec.json>" >&2; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Error: missing $1" >&2; exit 1; }; }

[ "$#" -lt 1 ] && { usage; exit 1; }
JOB_SPEC="$1"
[ ! -f "$JOB_SPEC" ] && { echo "Error: $JOB_SPEC not found." >&2; exit 1; }

require_cmd jq; require_cmd python3; require_cmd ssh; require_cmd scp; require_cmd curl

log_event() { "$SCRIPT_DIR/log_controller_event.sh" "$@" >/dev/null 2>&1 || true; }
announce() { printf '[%s][%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${CONTROLLER_LOG_LABEL:-$JOB_ID}" "$*"; }

# ---------------------------------------------------------------------------
# Parse job spec (identical to skypilot_dispatch)
# ---------------------------------------------------------------------------
BRANCH="$(jq -r '.branch' "$JOB_SPEC")"
COMMIT_SHA="$(jq -r '.commit_sha' "$JOB_SPEC")"
JOB_ID="$(jq -r '.job_id' "$JOB_SPEC")"
REQ_GPU_COUNT="$(jq -r '.resource_profile.gpu_count // empty' "$JOB_SPEC")"
ENV_OVERRIDES_JSON="$(jq -c '.env_overrides // {}' "$JOB_SPEC")"
RUN_ARGV_JSON="$(jq -c '.run_argv // []' "$JOB_SPEC")"
RUN_ARGV_SH="$(python3 -c "import json,shlex,sys; print(' '.join(shlex.quote(a) for a in json.loads(sys.argv[1])))" "$RUN_ARGV_JSON")"
REMOTE_ENV_SH="$(python3 -c "
import json,re,shlex,sys
p=json.loads(sys.argv[1])
parts=[f'{k}={shlex.quote(str(v))}' for k,v in sorted(p.items()) if re.match(r'^[A-Za-z_]\w*$',k)]
print(' '.join(parts))
" "$ENV_OVERRIDES_JSON")"

[ -z "$REQ_GPU_COUNT" ] || [ "$REQ_GPU_COUNT" = "null" ] && { echo "Error: missing gpu_count" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Load profile
# ---------------------------------------------------------------------------
POD_PREFIX="pg-exp"
[ "$REQ_GPU_COUNT" = "8" ] && POD_PREFIX="pg-rec"
PROFILE_KEY="$POD_PREFIX"

SHADE_INSTANCE_TYPE="$(jq -r --arg k "$PROFILE_KEY" '.[$k].shade_instance_type' "$PROFILE_FILE")"
CLOUD="$(jq -r --arg k "$PROFILE_KEY" '.[$k].cloud' "$PROFILE_FILE")"
REGION="$(jq -r --arg k "$PROFILE_KEY" '.[$k].region' "$PROFILE_FILE")"
OS_IMAGE="$(jq -r --arg k "$PROFILE_KEY" '.[$k].os // "ubuntu22.04_cuda12.8_shade_os"' "$PROFILE_FILE")"
SSH_KEY_ID="$(jq -r --arg k "$PROFILE_KEY" '.[$k].ssh_key_id // empty' "$PROFILE_FILE")"
IDLE_ACTION="$(jq -r --arg k "$PROFILE_KEY" '.[$k].idle_action // "none"' "$PROFILE_FILE")"
FAILURE_ACTION="$(jq -r --arg k "$PROFILE_KEY" '.[$k].failure_action // "down"' "$PROFILE_FILE")"
LEASE_TTL_MINUTES="$(jq -r --arg k "$PROFILE_KEY" '.[$k].lease_ttl_minutes // 60' "$PROFILE_FILE")"

if [ -z "$SSH_KEY_ID" ]; then
  echo "Error: ssh_key_id not set in $PROFILE_FILE for profile $PROFILE_KEY." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Build instance name
# ---------------------------------------------------------------------------
build_instance_name() {
  python3 - "$POD_PREFIX" "$JOB_ID" "$(date -u +%H%M%S)" <<'PY'
import re, sys
prefix, job_id, suffix = sys.argv[1], sys.argv[2], sys.argv[3]
slug = re.sub(r"[^a-z0-9]+", "-", job_id.lower()).strip("-") or "job"
max_len = 63 - len(prefix) - len(suffix) - 2
slug = slug[:max(max_len, 1)].rstrip("-") or "job"
print(f"{prefix}-{slug}-{suffix}")
PY
}

# ---------------------------------------------------------------------------
# Shadeform API helpers
# ---------------------------------------------------------------------------
sf_api() {
  local method="$1" path="$2"
  shift 2
  curl -s -X "$method" "$SHADEFORM_API$path" \
    -H "X-API-KEY: $SHADEFORM_API_KEY" \
    -H "Content-Type: application/json" "$@"
}

sf_create_instance() {
  local name="$1"
  sf_api POST "/instances/create" -d "{
    \"cloud\": \"$CLOUD\",
    \"region\": \"$REGION\",
    \"shade_instance_type\": \"$SHADE_INSTANCE_TYPE\",
    \"shade_cloud\": true,
    \"name\": \"$name\",
    \"os\": \"$OS_IMAGE\",
    \"ssh_key_id\": \"$SSH_KEY_ID\"
  }"
}

sf_get_instance() { sf_api GET "/instances/$1/info"; }
sf_delete_instance() { sf_api POST "/instances/$1/delete"; }
sf_list_instances() { sf_api GET "/instances"; }

# ---------------------------------------------------------------------------
# Active leased instances (reuse from skypilot pattern)
# ---------------------------------------------------------------------------
active_leased_instances() {
  python3 - "$REPO_ROOT/registry/spool" <<'PY'
import json, pathlib, sys
spool = pathlib.Path(sys.argv[1])
if not spool.exists(): raise SystemExit(0)
for lp in spool.glob("*_lease.json"):
    try: p = json.loads(lp.read_text())
    except: continue
    if p.get("cleanup",{}).get("released_at"): continue
    iid = p.get("instance_id") or p.get("cluster_id") or p.get("pod_id")
    if iid: print(iid)
PY
}

# ---------------------------------------------------------------------------
# Atomic reservation (identical pattern)
# ---------------------------------------------------------------------------
reserve_instance_or_fail() {
  local instance_id="$1" job_id="$2"
  python3 - "$REPO_ROOT/registry" "$instance_id" "$job_id" <<'PY'
import fcntl, json, pathlib, sys
from datetime import datetime, timezone
reg = pathlib.Path(sys.argv[1]); iid = sys.argv[2]; jid = sys.argv[3]
spool = reg / "spool"; lock_path = reg / ".pod_dispatch.lock"
spool.mkdir(parents=True, exist_ok=True); lock_path.touch(exist_ok=True)
lease_path = spool / f"{jid}_lease.json"
with lock_path.open("a+") as lf:
    fcntl.flock(lf.fileno(), fcntl.LOCK_EX)
    for ep in spool.glob("*_lease.json"):
        try: p = json.loads(ep.read_text())
        except: continue
        if p.get("cleanup",{}).get("released_at"): continue
        eid = p.get("instance_id") or p.get("cluster_id") or p.get("pod_id")
        if eid == iid: print("CONFLICT"); fcntl.flock(lf.fileno(), fcntl.LOCK_UN); raise SystemExit(0)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lease_path.write_text(json.dumps({"job_id":jid,"instance_id":iid,"pod_id":iid,"reserved_at":now,"backend":"shadeform","cleanup":{}}, sort_keys=True)+"\n")
    print("RESERVED"); fcntl.flock(lf.fileno(), fcntl.LOCK_UN)
PY
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
INSTANCE_ID=""
INSTANCE_NAME=""
INSTANCE_IP=""
INSTANCE_SOURCE="created"
SSH_USER_API=""

# ---------------------------------------------------------------------------
# Cleanup trap
# ---------------------------------------------------------------------------
dispatch_cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$INSTANCE_ID" ]; then
    announce "Dispatch failed; deleting instance $INSTANCE_ID ($FAILURE_ACTION)." >&2
    local res_lease="$REPO_ROOT/registry/spool/${JOB_ID}_lease.json"
    [ -f "$res_lease" ] && rm -f "$res_lease"
    if [ "$FAILURE_ACTION" = "down" ]; then
      sf_delete_instance "$INSTANCE_ID" >/dev/null 2>&1 || true
    fi
    log_event --event "dispatch_failed" --job-id "$JOB_ID" --pod-id "$INSTANCE_ID" \
      --branch "$BRANCH" --status "$FAILURE_ACTION" --message "shadeform dispatch failed"
  fi
}
trap dispatch_cleanup EXIT

# ---------------------------------------------------------------------------
# Find or create instance
# ---------------------------------------------------------------------------

# Check for reusable active instance (same prefix, not leased)
LEASED_IDS="$(active_leased_instances | paste -sd, -)"
INSTANCE_ID="$(sf_list_instances | python3 -c "
import json, sys
leased = set('$LEASED_IDS'.split(',')) - {''}
data = json.load(sys.stdin)
for inst in data.get('instances', []):
    if inst.get('status') == 'active' and inst.get('name','').startswith('$POD_PREFIX'):
        iid = inst.get('id','')
        if iid not in leased:
            print(iid); raise SystemExit(0)
" 2>/dev/null || echo "")"

if [ -n "$INSTANCE_ID" ]; then
  INSTANCE_SOURCE="existing"
  INSTANCE_INFO="$(sf_get_instance "$INSTANCE_ID")"
  INSTANCE_IP="$(echo "$INSTANCE_INFO" | jq -r '.ip // empty')"
  INSTANCE_NAME="$(echo "$INSTANCE_INFO" | jq -r '.name // empty')"
  SSH_USER_API="$(echo "$INSTANCE_INFO" | jq -r '.ssh_user // empty')"
  announce "Reusing existing instance $INSTANCE_ID ($INSTANCE_NAME)"
else
  INSTANCE_NAME="$(build_instance_name)"
  announce "Creating new instance $INSTANCE_NAME ($SHADE_INSTANCE_TYPE on $CLOUD)..."
  CREATE_RESP="$(sf_create_instance "$INSTANCE_NAME")"
  INSTANCE_ID="$(echo "$CREATE_RESP" | jq -r '.id // empty')"
  if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "null" ]; then
    echo "Error: failed to create instance. Response: $CREATE_RESP" >&2
    exit 1
  fi
  announce "Instance $INSTANCE_ID created. Waiting for active..."
fi

# Reserve atomically
RESERVE_RESULT="$(reserve_instance_or_fail "$INSTANCE_ID" "$JOB_ID")"
if [ "$RESERVE_RESULT" = "CONFLICT" ]; then
  announce "Instance $INSTANCE_ID claimed by another worker." >&2
  INSTANCE_ID=""
  exit 1
fi

log_event --event "pod_selected" --job-id "$JOB_ID" --pod-id "$INSTANCE_ID" \
  --pod-name "$INSTANCE_NAME" --branch "$BRANCH" --reason "$INSTANCE_SOURCE" \
  --message "selected shadeform instance"

# ---------------------------------------------------------------------------
# Poll for active status + IP
# ---------------------------------------------------------------------------
if [ -z "$INSTANCE_IP" ]; then
  for i in $(seq 1 36); do
    INFO="$(sf_get_instance "$INSTANCE_ID")"
    STATUS="$(echo "$INFO" | jq -r '.status // "unknown"')"
    INSTANCE_IP="$(echo "$INFO" | jq -r '.ip // empty')"
    SSH_USER_API="$(echo "$INFO" | jq -r '.ssh_user // empty')"
    if [ "$STATUS" = "active" ] && [ -n "$INSTANCE_IP" ] && [ "$INSTANCE_IP" != "null" ]; then
      announce "Instance active at $INSTANCE_IP"
      break
    fi
    if [ "$STATUS" = "error" ] || [ "$STATUS" = "deleted" ]; then
      announce "Error: instance entered $STATUS state." >&2
      exit 1
    fi
    sleep 10
  done
fi

if [ -z "$INSTANCE_IP" ] || [ "$INSTANCE_IP" = "null" ]; then
  announce "Error: instance did not become active within 6 min." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# SSH readiness
# ---------------------------------------------------------------------------
# Use ssh_user from Shadeform API (typically "shadeform" on Hyperstack).
SSH_USER="${SSH_USER_API:-shadeform}"
SSH_PORT="22"
SSH_KEY_FILE="${SHADEFORM_SSH_KEY_FILE:-$HOME/.shadeform/ssh_key}"

if [ ! -f "$SSH_KEY_FILE" ]; then
  echo "Error: SSH private key not found at $SSH_KEY_FILE." >&2
  echo "Save the Shadeform Managed Key private key there (chmod 600) or set SHADEFORM_SSH_KEY_FILE." >&2
  exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
ssh_remote() {
  # shellcheck disable=SC2086
  ssh $SSH_OPTS -i "$SSH_KEY_FILE" -p "$SSH_PORT" "${SSH_USER}@${INSTANCE_IP}" "$@"
}
scp_to_remote() {
  # shellcheck disable=SC2086
  scp $SSH_OPTS -i "$SSH_KEY_FILE" -P "$SSH_PORT" "$1" "${SSH_USER}@${INSTANCE_IP}:$2"
}

announce "Waiting for SSH on ${SSH_USER}@${INSTANCE_IP}..."
for i in $(seq 1 42); do
  if ssh_remote "echo SSH_READY" 2>/tmp/ssh_ready_err; then break; fi
  [ "$i" -eq 1 ] && announce "SSH attempt 1 error: $(cat /tmp/ssh_ready_err 2>/dev/null | head -3)"
  sleep 10
done
if ! ssh_remote "echo SSH_READY" >/dev/null 2>&1; then
  announce "Error: SSH not ready after 7 minutes. Last error: $(cat /tmp/ssh_ready_err 2>/dev/null | head -3)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Setup (only on fresh instance)
# ---------------------------------------------------------------------------
if [ "$INSTANCE_SOURCE" = "created" ]; then
  # Match the official OpenAI competition template environment:
  # matotezitanka/proteus-pytorch:2.11.0-cuda12.8
  # PyTorch 2.11.0, CUDA 12.8, FlashAttention 3 (Hopper).
  announce "Installing dependencies to match official competition template (torch 2.11.0, cu128, FA3)..."
  ssh_remote "sudo mkdir -p /workspace && sudo chmod 777 /workspace" 2>/dev/null || true
  ssh_remote "sudo apt-get update -qq && sudo apt-get install -y -qq git jq tmux rsync 2>/dev/null || true"
  ssh_remote "sudo pip3 install --no-cache-dir torch==2.11.0 --index-url https://download.pytorch.org/whl/cu128 2>&1 | tail -2"
  ssh_remote "sudo pip3 install --no-cache-dir flash-attn sentencepiece huggingface_hub numpy zstandard psutil 2>&1 | tail -2"
  ssh_remote "python3 -c 'import torch; print(f\"torch={torch.__version__} cuda={torch.version.cuda}\"); from flash_attn import flash_attn_func; import flash_attn; print(f\"flash-attn={flash_attn.__version__} OK\")'"
  announce "Setup complete."
else
  ssh_remote "sudo mkdir -p /workspace && sudo chmod 777 /workspace" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Bootstrap + launch (identical to skypilot_dispatch)
# ---------------------------------------------------------------------------
ssh_remote "mkdir -p /workspace/scripts"
scp_to_remote "$SCRIPT_DIR/runpod_bootstrap_remote.sh" "/workspace/scripts/runpod_bootstrap_remote.sh"
ssh_remote "chmod +x /workspace/scripts/runpod_bootstrap_remote.sh"

announce "Bootstrapping commit $COMMIT_SHA..."
BOOTSTRAP_CMD="RUNPOD_BOOTSTRAP_ALLOW_APT_FALLBACK=1 /workspace/scripts/runpod_bootstrap_remote.sh $JOB_ID $BRANCH $COMMIT_SHA"
[ -n "$REMOTE_ENV_SH" ] && BOOTSTRAP_CMD="RUNPOD_BOOTSTRAP_ALLOW_APT_FALLBACK=1 $REMOTE_ENV_SH /workspace/scripts/runpod_bootstrap_remote.sh $JOB_ID $BRANCH $COMMIT_SHA"
ssh_remote "$BOOTSTRAP_CMD"

REMOTE_RUN_SCRIPT="/workspace/jobs/$JOB_ID/scripts/runpod_run_remote.sh"
REQ_GPU_SUBSTRING="$(jq -r '.resource_profile.gpu_type // "H100"' "$JOB_SPEC")"
REMOTE_RUN_CMD="$REMOTE_RUN_SCRIPT $JOB_ID $REQ_GPU_COUNT $(printf '%q' "$REQ_GPU_SUBSTRING") $RUN_ARGV_SH"
[ -n "$REMOTE_ENV_SH" ] && REMOTE_RUN_CMD="$REMOTE_ENV_SH $REMOTE_RUN_SCRIPT $JOB_ID $REQ_GPU_COUNT $(printf '%q' "$REQ_GPU_SUBSTRING") $RUN_ARGV_SH"

announce "Launching remote job..."
ssh_remote "$REMOTE_RUN_CMD"

# ---------------------------------------------------------------------------
# Write lease + spool files
# ---------------------------------------------------------------------------
SSH_TARGET="${SSH_USER}@${INSTANCE_IP}"
mkdir -p "$REPO_ROOT/registry/spool"
printf '%s\n' "$SSH_TARGET" > "$REPO_ROOT/registry/spool/${JOB_ID}_ssh_target.txt"
printf '%s\n' "$SSH_PORT" > "$REPO_ROOT/registry/spool/${JOB_ID}_ssh_port.txt"
printf '%s\n' "$INSTANCE_ID" > "$REPO_ROOT/registry/spool/${JOB_ID}_pod_id.txt"

DISPATCHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
LEASE_EXPIRES_AT="$(python3 -c "
from datetime import datetime,timedelta,timezone; import sys
d=datetime.strptime(sys.argv[1],'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
print((d+timedelta(minutes=int(sys.argv[2]))).strftime('%Y-%m-%dT%H:%M:%SZ'))
" "$DISPATCHED_AT" "$LEASE_TTL_MINUTES")"

jq -n \
  --arg job_id "$JOB_ID" --arg branch "$BRANCH" --arg commit_sha "$COMMIT_SHA" \
  --arg instance_id "$INSTANCE_ID" --arg pod_id "$INSTANCE_ID" \
  --arg pod_name "$INSTANCE_NAME" --arg profile_key "$PROFILE_KEY" \
  --arg ssh_host "$SSH_TARGET" --argjson ssh_port "$SSH_PORT" \
  --arg dispatched_at "$DISPATCHED_AT" --arg lease_expires_at "$LEASE_EXPIRES_AT" \
  --arg idle_action "$IDLE_ACTION" --arg failure_action "$FAILURE_ACTION" \
  --argjson lease_ttl_minutes "$LEASE_TTL_MINUTES" \
  --argjson run_argv "$RUN_ARGV_JSON" \
  '{job_id:$job_id, branch:$branch, commit_sha:$commit_sha,
    instance_id:$instance_id, pod_id:$pod_id, pod_name:$pod_name,
    profile_key:$profile_key, backend:"shadeform",
    ssh:{host:$ssh_host, port:$ssh_port},
    dispatched_at:$dispatched_at, lease_expires_at:$lease_expires_at,
    run_argv:$run_argv,
    cleanup:{default_action:$idle_action, failure_action:$failure_action, lease_ttl_minutes:$lease_ttl_minutes}
  }' > "$REPO_ROOT/registry/spool/${JOB_ID}_lease.json"

log_event --event "job_dispatched" --job-id "$JOB_ID" --pod-id "$INSTANCE_ID" \
  --pod-name "$INSTANCE_NAME" --branch "$BRANCH" --ssh-host "$SSH_TARGET" \
  --ssh-port "$SSH_PORT" --status "lease_active" --message "shadeform dispatch complete"

trap - EXIT
announce "Job dispatched successfully."
