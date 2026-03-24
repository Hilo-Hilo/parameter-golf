#!/usr/bin/env bash
set -euo pipefail

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
MAIN_CHECKOUT="$(cd "$(git -C "$REPO_ROOT" rev-parse --git-common-dir)/.." && pwd)"
LOCAL_RESULTS_DIR="$MAIN_CHECKOUT/registry/remote_results/$JOB_ID"

mkdir -p "$LOCAL_RESULTS_DIR"

echo "Collecting results from $SSH_TARGET for $JOB_ID..."
rsync -avz "$SSH_TARGET:$REMOTE_OUTPUT_DIR/" "$LOCAL_RESULTS_DIR/"

SUMMARY_FILE="$LOCAL_RESULTS_DIR/${JOB_ID}.json"
RUNS_LEDGER="$MAIN_CHECKOUT/registry/runs.jsonl"

if [ -f "$SUMMARY_FILE" ]; then
  (
    flock -x 200
    cat "$SUMMARY_FILE" >> "$RUNS_LEDGER"
    echo "" >> "$RUNS_LEDGER"
  ) 200>"$MAIN_CHECKOUT/registry/.runs.lock"
  echo "Appended summary to runs.jsonl."
else
  echo "Warning: No summary JSON found at $SUMMARY_FILE"
fi
