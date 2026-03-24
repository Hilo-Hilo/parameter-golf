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

export DATA_PATH="${DATA_PATH:-$WORKSPACE/data/datasets/fineweb10B_sp1024}"
export TOKENIZER_PATH="${TOKENIZER_PATH:-$WORKSPACE/data/tokenizers/fineweb_1024_bpe.model}"
export OUTPUT_DIR="$JOB_DIR/experiments/$JOB_ID"
export RUN_ID="$JOB_ID"

mkdir -p "$OUTPUT_DIR"

echo "Launching job $JOB_ID under tmux..."

printf -v tmux_cmd '%q ' \
  "./scripts/run_experiment.sh" \
  "--name" "$JOB_ID" \
  "--track" "remote" \
  "--job-id" "$JOB_ID" \
  "--heartbeat-seconds" "30" \
  "--required-gpu-count" "$REQ_GPU_COUNT" \
  "--required-gpu-substring" "$REQ_GPU_NAME" \
  "--outer-timeout-seconds" "660" \
  "--" \
  "$@"
tmux_cmd="${tmux_cmd% }"

tmux new-session -d -s "job_${JOB_ID}" "$tmux_cmd > \"$OUTPUT_DIR/run.log\" 2>&1"

echo "Job launched. Use 'tmux attach -t job_${JOB_ID}' to view if connected manually."
