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

export DATA_PATH="${DATA_PATH:-$WORKSPACE/parameter-golf/data/datasets/fineweb10B_sp1024}"
export TOKENIZER_PATH="${TOKENIZER_PATH:-$WORKSPACE/parameter-golf/data/tokenizers/fineweb_1024_bpe.model}"
export OUTPUT_DIR="$JOB_DIR/experiments/$JOB_ID"
export RUN_ID="$JOB_ID"

mkdir -p "$OUTPUT_DIR"

# For 1-GPU proxy runs, auto-detect the H100 SKU and compute a faithful
# wallclock training budget.  The official contest is 600s on 8xH100 SXM.
# With grad_accum_steps=8//world_size the global batch is preserved, so the
# proxy just needs to give ~8x more wall time, adjusted for SKU throughput.
#
# Reference multipliers (conservative, from public hardware data):
#   H100 SXM  (80GB HBM3)  -> 8.0x  (4800s)
#   H100 NVL               -> 8.5x  (5100s)
#   H100 PCIe              -> 11.0x (6600s)
#
# The outer timeout is set to proxy_train + 1800s headroom for eval/TTT.
# All values can be overridden via MAX_WALLCLOCK_SECONDS / RUNPOD_OUTER_TIMEOUT_SECONDS.
if [ "$REQ_GPU_COUNT" = "1" ] && [ -z "${MAX_WALLCLOCK_SECONDS:-}" ]; then
  GPU_LINE="$(nvidia-smi -L 2>/dev/null | head -1 || true)"
  echo "Detected GPU: $GPU_LINE"
  PROXY_TRAIN_SECONDS="$(python3 - "$GPU_LINE" <<'PY'
import sys
gpu = sys.argv[1] if len(sys.argv) > 1 else ""
official_budget = 600
if "NVL" in gpu:
    mult = 8.5
elif "PCIe" in gpu or "PCIE" in gpu:
    mult = 11.0
else:
    # Default: assume SXM-class (includes "H100 80GB HBM3" and unknowns)
    mult = 8.0
print(int(official_budget * mult))
PY
)"
  export MAX_WALLCLOCK_SECONDS="$PROXY_TRAIN_SECONDS"
  echo "1-GPU proxy: MAX_WALLCLOCK_SECONDS=$PROXY_TRAIN_SECONDS (from SKU detection)"
fi

DEFAULT_OUTER_TIMEOUT_SECONDS="660"
if [ "$REQ_GPU_COUNT" = "1" ]; then
  # Outer timeout = proxy train budget + 5400s headroom for compile + eval/TTT/serialization.
  # TTT eval with many epochs can take 60+ min on 1 GPU.
  proxy_train="${MAX_WALLCLOCK_SECONDS:-4800}"
  DEFAULT_OUTER_TIMEOUT_SECONDS="$(( proxy_train + 5400 ))"
fi
OUTER_TIMEOUT_SECONDS="${RUNPOD_OUTER_TIMEOUT_SECONDS:-$DEFAULT_OUTER_TIMEOUT_SECONDS}"

echo "Launching job $JOB_ID under tmux..."

printf -v tmux_cmd '%q ' \
  "./scripts/run_experiment.sh" \
  "--name" "$JOB_ID" \
  "--track" "remote" \
  "--job-id" "$JOB_ID" \
  "--heartbeat-seconds" "30" \
  "--required-gpu-count" "$REQ_GPU_COUNT" \
  "--required-gpu-substring" "$REQ_GPU_NAME" \
  "--outer-timeout-seconds" "$OUTER_TIMEOUT_SECONDS" \
  "--" \
  "$@"
tmux_cmd="${tmux_cmd% }"

tmux new-session -d -s "job_${JOB_ID}" "$tmux_cmd > \"$OUTPUT_DIR/run.log\" 2>&1"

echo "Job launched. Use 'tmux attach -t job_${JOB_ID}' to view if connected manually."
