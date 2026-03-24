#!/usr/bin/env bash
set -euo pipefail

# scripts/runpod_dispatch.sh
# Reads a job spec JSON, finds/provisions an appropriate pod, and triggers remote execution.

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <job_spec.json>" >&2
  exit 1
fi

JOB_SPEC="$1"

if [ ! -f "$JOB_SPEC" ]; then
  echo "Error: Job spec $JOB_SPEC not found." >&2
  exit 1
fi

BRANCH=$(jq -r '.branch' "$JOB_SPEC")
COMMIT_SHA=$(jq -r '.commit_sha' "$JOB_SPEC")
RUN_ARGV=$(jq -r '.run_argv | join(" ")' "$JOB_SPEC")
JOB_ID=$(jq -r '.job_id' "$JOB_SPEC")
REQ_GPU_COUNT=$(jq -r '.resource_profile.gpu_count // empty' "$JOB_SPEC")
REQ_GPU_SUBSTRING=$(jq -r '.resource_profile.gpu_type // "H100"' "$JOB_SPEC")

# Determine profile/prefix
if [ "$REQ_GPU_COUNT" = "8" ]; then
  POD_PREFIX="pg-rec"
else
  POD_PREFIX="pg-exp"
fi

echo "Looking for a $POD_PREFIX pod..."
# We try to get an existing pod that is running. (Mock implementation of find/provision)
# We will use jq to parse runpodctl output, assuming runpodctl get pods -a -o json is supported
# For now, we'll try to get the SSH info for a pod starting with POD_PREFIX
# If runpodctl get pods output is text, we might need a workaround, but let's assume it supports outputting JSON or we just use a known SSH target for dry runs.

POD_ID=$(runpodctl get pods -a | grep "$POD_PREFIX" | head -n 1 | awk '{print $1}')
if [ -z "$POD_ID" ]; then
  echo "No pod found starting with $POD_PREFIX. Creating one..."
  scripts/runpod_pool.sh create "${POD_PREFIX}-01"
  sleep 10
  POD_ID=$(runpodctl get pods -a | grep "${POD_PREFIX}-01" | head -n 1 | awk '{print $1}')
fi

echo "Starting pod $POD_ID..."
runpodctl start pod "$POD_ID" || true
echo "Waiting for pod to be running..."
sleep 15

# Extract IP and Port from pod info using runpodctl get pod $POD_ID
# runpodctl doesn't output SSH string nicely, often we need the API or assume it's set in user's SSH config as the POD_ID.
# According to user: "Use full SSH via public IP + TCP 22 ... Since you want the Mac to collect artifacts/logs cleanly, full SSH is the better fit."
# Let's extract the IP and port from `runpodctl get pod $POD_ID`.
# The output format has a row with IP and port. We use awk.
POD_INFO=$(runpodctl get pod "$POD_ID")
# We'll use a hack to just let the user set SSH config if it fails, or if they have a wrapper.
# Actually, the user says runpodctl supports create/get/start/stop.
# Let's assume there is an SSH_TARGET derived from the pod info or environment.
# Since we don't have real runpodctl here, we'll just try to parse the SSH connection string from RunPod dashboard or assume standard format.
SSH_IP=$(echo "$POD_INFO" | grep "IP" | awk '{print $NF}' || echo "")
SSH_PORT=$(echo "$POD_INFO" | grep "Port" | grep 22 | awk '{print $NF}' || echo "22")

# Fallback: if we can't parse it, we ask the user or just assume the SSH config is configured.
if [ -z "$SSH_IP" ]; then
  echo "Warning: Could not parse SSH IP from runpodctl. Assuming SSH target is configured as $POD_ID."
  SSH_TARGET="$POD_ID"
else
  SSH_TARGET="root@$SSH_IP -p $SSH_PORT"
fi

echo "Deploying scripts to RunPod ($SSH_TARGET)..."
SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 $SSH_TARGET"

# Wait for SSH to be up
for i in {1..12}; do
  if $SSH_CMD echo "SSH is up"; then
    break
  fi
  echo "Waiting for SSH..."
  sleep 10
done

$SSH_CMD "mkdir -p /workspace/scripts"
scp -o StrictHostKeyChecking=no scripts/runpod_bootstrap_remote.sh $SSH_TARGET:/workspace/scripts/
scp -o StrictHostKeyChecking=no scripts/runpod_run_remote.sh $SSH_TARGET:/workspace/scripts/
$SSH_CMD "chmod +x /workspace/scripts/*.sh"

echo "Bootstrapping RunPod environment..."
$SSH_CMD "/workspace/scripts/runpod_bootstrap_remote.sh $JOB_ID $BRANCH $COMMIT_SHA"

echo "Launching job $JOB_ID on RunPod..."
# Pass all the env vars from the job spec if needed, or we just rely on run_experiment.sh to handle it.
$SSH_CMD "/workspace/scripts/runpod_run_remote.sh $JOB_ID \"$REQ_GPU_COUNT\" \"$REQ_GPU_SUBSTRING\" $RUN_ARGV"

echo "Job dispatched successfully."
echo "$SSH_TARGET" > "registry/spool/${JOB_ID}_ssh_target.txt"
