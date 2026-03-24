#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"

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

BRANCH="$(jq -r '.branch' "$JOB_SPEC")"
COMMIT_SHA="$(jq -r '.commit_sha' "$JOB_SPEC")"
JOB_ID="$(jq -r '.job_id' "$JOB_SPEC")"
REQ_GPU_COUNT="$(jq -r '.resource_profile.gpu_count // empty' "$JOB_SPEC")"
REQ_GPU_SUBSTRING="$(jq -r '.resource_profile.gpu_type // "H100"' "$JOB_SPEC")"

RUN_ARGV_JSON="$(jq -c '.run_argv // []' "$JOB_SPEC")"
RUN_ARGV_SH="$(python3 - "$RUN_ARGV_JSON" <<'PY'
import json
import shlex
import sys

argv = json.loads(sys.argv[1])
print(" ".join(shlex.quote(arg) for arg in argv))
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

if [ -n "${RUNPOD_POD_ID:-}" ]; then
  POD_ID="$RUNPOD_POD_ID"
else
  POD_ID="$(
    runpodctl get pod \
      | awk -v prefix="$POD_PREFIX" 'NR > 1 && $2 ~ ("^" prefix) { print $1; exit }'
  )"
fi

if [ -z "$POD_ID" ]; then
  POD_NAME="${POD_PREFIX}-smoke-$(date -u +%H%M%S)"
  echo "No existing $POD_PREFIX pod found. Creating $POD_NAME..."
  "$SCRIPT_DIR/runpod_pool.sh" create "$POD_NAME"
  sleep 10
  POD_ID="$(
    runpodctl get pod \
      | awk -v name="$POD_NAME" 'NR > 1 && $2 == name { print $1; exit }'
  )"
fi

if [ -z "$POD_ID" ]; then
  echo "Error: unable to resolve a RunPod pod ID for this job." >&2
  exit 1
fi

echo "Using pod $POD_ID for $JOB_ID"
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
  echo "Error: unable to resolve an SSH command for pod $POD_ID: $SSH_CONNECT" >&2
  exit 1
fi

SSH_HOST="$(printf '%s\n' "$SSH_CONNECT" | awk '{print $2}')"
SSH_PORT="$(printf '%s\n' "$SSH_CONNECT" | awk '{print $4}')"

if [ -z "$SSH_HOST" ] || [ -z "$SSH_PORT" ]; then
  echo "Error: unable to parse SSH details from: $SSH_CONNECT" >&2
  exit 1
fi

ssh_remote() {
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_HOST" "$@"
}

scp_to_remote() {
  scp -o StrictHostKeyChecking=no -P "$SSH_PORT" "$1" "$SSH_HOST:$2"
}

echo "Waiting for SSH on $SSH_HOST:$SSH_PORT..."
for _ in {1..18}; do
  if ssh_remote "echo SSH_READY" >/dev/null 2>&1; then
    break
  fi
  sleep 10
done

if ! ssh_remote "echo SSH_READY" >/dev/null 2>&1; then
  echo "Error: SSH did not become ready for pod $POD_ID" >&2
  exit 1
fi

ssh_remote "mkdir -p /workspace/scripts"
scp_to_remote "$SCRIPT_DIR/runpod_bootstrap_remote.sh" "/workspace/scripts/runpod_bootstrap_remote.sh"
ssh_remote "chmod +x /workspace/scripts/runpod_bootstrap_remote.sh"

echo "Bootstrapping exact commit $COMMIT_SHA..."
ssh_remote "/workspace/scripts/runpod_bootstrap_remote.sh $JOB_ID $BRANCH $COMMIT_SHA"

REMOTE_RUN_SCRIPT="/workspace/jobs/$JOB_ID/scripts/runpod_run_remote.sh"
REMOTE_RUN_CMD="$REMOTE_RUN_SCRIPT $JOB_ID $REQ_GPU_COUNT $(printf '%q' "$REQ_GPU_SUBSTRING") $RUN_ARGV_SH"

echo "Launching remote job..."
ssh_remote "$REMOTE_RUN_CMD"

mkdir -p "$REPO_ROOT/registry/spool"
printf '%s\n' "$SSH_HOST" > "$REPO_ROOT/registry/spool/${JOB_ID}_ssh_target.txt"
printf '%s\n' "$SSH_PORT" > "$REPO_ROOT/registry/spool/${JOB_ID}_ssh_port.txt"
printf '%s\n' "$POD_ID" > "$REPO_ROOT/registry/spool/${JOB_ID}_pod_id.txt"

echo "Job dispatched successfully."
