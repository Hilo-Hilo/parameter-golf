#!/usr/bin/env bash
set -euo pipefail

# scripts/runpod_collect.sh
# Runs ON the Mac to collect job artifacts and append to registry.

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <ssh_target> <job_id>" >&2
  exit 1
fi
SSH_TARGET="$1"
JOB_ID="$2"

WORKSPACE="/workspace"
JOB_DIR="$WORKSPACE/jobs/$JOB_ID"
REMOTE_OUTPUT_DIR="$JOB_DIR/experiments/$JOB_ID"

REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCAL_RESULTS_DIR="$REPO_ROOT/experiments/$JOB_ID"

mkdir -p "$LOCAL_RESULTS_DIR"

echo "Collecting results from $SSH_TARGET for $JOB_ID..."
rsync -avz -e "ssh -o StrictHostKeyChecking=no" "$SSH_TARGET:$REMOTE_OUTPUT_DIR/" "$LOCAL_RESULTS_DIR/"

# After collecting, append summary to locked runs.jsonl
# The pod's run_experiment.sh generated a $JOB_ID.json in the output directory
# BUT wait! run_experiment.sh creates the summary path as `$experiment_id.json`, and run_id might be `$JOB_ID`.
# Let's find the json file in the pulled directory.

SUMMARY_FILES=("$LOCAL_RESULTS_DIR"/*.json)
if [ ${#SUMMARY_FILES[@]} -gt 0 ] && [ -f "${SUMMARY_FILES[0]}" ]; then
  SUMMARY_FILE="${SUMMARY_FILES[0]}"
  RUNS_LEDGER="$REPO_ROOT/registry/runs.jsonl"
  mkdir -p "$REPO_ROOT/registry"
  
  (
    flock -x 200
    cat "$SUMMARY_FILE" >> "$RUNS_LEDGER"
    echo "" >> "$RUNS_LEDGER"
  ) 200>"$REPO_ROOT/registry/.runs.lock"
  echo "Appended summary to runs.jsonl."
else
  echo "Warning: No summary JSON found in $LOCAL_RESULTS_DIR"
fi
