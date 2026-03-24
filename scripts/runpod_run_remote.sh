#!/usr/bin/env bash
set -euo pipefail

# scripts/runpod_run_remote.sh
# Runs ON the pod to execute a job via tmux

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 <job_id> <gpu_count> <gpu_name_substring> <command...>" >&2
  exit 1
fi

JOB_ID="$1"
REQ_GPU_COUNT="$2"
REQ_GPU_NAME="$3"
shift 3

WORKSPACE="/workspace"
JOB_DIR="$WORKSPACE/jobs/$JOB_ID"

cd "$JOB_DIR"

export DATA_PATH="$WORKSPACE/data"
export OUTPUT_DIR="$JOB_DIR/experiments/$JOB_ID"
export RUN_ID="$JOB_ID"

mkdir -p "$OUTPUT_DIR"

# Provide arguments for run_experiment.sh
# The outer timeout is strictly enforced by run_experiment.sh via --outer-timeout-seconds
# We just launch it in tmux so SSH can disconnect

echo "Launching job $JOB_ID under tmux..."
# Notice we just pass all arguments to scripts/run_experiment.sh
tmux new-session -d -s "job_${JOB_ID}" "scripts/run_experiment.sh --name \"$JOB_ID\" --track remote --job-id \"$JOB_ID\" --required-gpu-count \"$REQ_GPU_COUNT\" --required-gpu-substring \"$REQ_GPU_NAME\" --outer-timeout-seconds 660 -- \"\$@\" > $OUTPUT_DIR/run.log 2>&1"

echo "Job launched. Use 'tmux attach -t job_${JOB_ID}' to view if connected manually."
