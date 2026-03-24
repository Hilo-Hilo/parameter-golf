#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 <job_id> <gpu_count> <gpu_name_substring> <timeout_seconds> [command...]" >&2
  exit 1
fi

JOB_ID="$1"
REQ_GPU_COUNT="$2"
REQ_GPU_NAME="$3"
TIMEOUT_SECS="$4"
shift 4

WORKSPACE="/workspace"
JOB_DIR="$WORKSPACE/jobs/$JOB_ID"

# GPU Check
ACTUAL_GPU_COUNT=$(nvidia-smi -L | wc -l)
if [ "$ACTUAL_GPU_COUNT" -ne "$REQ_GPU_COUNT" ]; then
  echo "Error: Expected $REQ_GPU_COUNT GPUs, found $ACTUAL_GPU_COUNT" >&2
  exit 1
fi

if ! nvidia-smi -L | grep -qi "$REQ_GPU_NAME"; then
  echo "Error: GPU does not match $REQ_GPU_NAME" >&2
  exit 1
fi

cd "$JOB_DIR"

export DATA_PATH="$WORKSPACE/data"
export OUTPUT_DIR="$JOB_DIR/experiments/$JOB_ID"
export RUN_ID="$JOB_ID"

mkdir -p "$OUTPUT_DIR"

echo "Launching job $JOB_ID under tmux..."
tmux new-session -d -s "job_${JOB_ID}" "timeout ${TIMEOUT_SECS}s \"\$@\" > $OUTPUT_DIR/run.log 2>&1"
echo "Job launched. Use 'tmux attach -t job_${JOB_ID}' to view."
