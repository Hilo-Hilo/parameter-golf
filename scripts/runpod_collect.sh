#!/usr/bin/env bash
set -euo pipefail

# scripts/runpod_collect.sh
# Runs ON the Mac to collect job artifacts and append to registry.

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <ssh_host> [ssh_port] <job_id>" >&2
  exit 1
fi

if [ "$#" -eq 2 ]; then
  SSH_HOST="$1"
  SSH_PORT="${RUNPOD_SSH_PORT:-22}"
  JOB_ID="$2"
else
  SSH_HOST="$1"
  SSH_PORT="$2"
  JOB_ID="$3"
fi

WORKSPACE="/workspace"
JOB_DIR="$WORKSPACE/jobs/$JOB_ID"
PRIMARY_REMOTE_DIR="$WORKSPACE/parameter-golf/experiments/$JOB_ID"
FALLBACK_REMOTE_DIR="$JOB_DIR/experiments/$JOB_ID"
REMOTE_SPOOL_JSON="$WORKSPACE/parameter-golf/registry/spool/${JOB_ID}.json"

REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCAL_RESULTS_DIR="$REPO_ROOT/experiments/$JOB_ID"

mkdir -p "$LOCAL_RESULTS_DIR"

echo "Collecting results from $SSH_HOST:$SSH_PORT for $JOB_ID..."
if ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "$SSH_HOST" "[ -d \"$PRIMARY_REMOTE_DIR\" ]"; then
  rsync -avz -e "ssh -o StrictHostKeyChecking=no -p $SSH_PORT" "$SSH_HOST:$PRIMARY_REMOTE_DIR/" "$LOCAL_RESULTS_DIR/"
fi

if ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "$SSH_HOST" "[ -d \"$FALLBACK_REMOTE_DIR\" ]"; then
  rsync -avz -e "ssh -o StrictHostKeyChecking=no -p $SSH_PORT" "$SSH_HOST:$FALLBACK_REMOTE_DIR/" "$LOCAL_RESULTS_DIR/wrapper/"
fi

if ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "$SSH_HOST" "[ -f \"$REMOTE_SPOOL_JSON\" ]"; then
  rsync -avz -e "ssh -o StrictHostKeyChecking=no -p $SSH_PORT" "$SSH_HOST:$REMOTE_SPOOL_JSON" "$LOCAL_RESULTS_DIR/"
fi

# After collecting, append summary to locked runs.jsonl
# The pod's run_experiment.sh generated a $JOB_ID.json in the output directory
# BUT wait! run_experiment.sh creates the summary path as `$experiment_id.json`, and run_id might be `$JOB_ID`.
# Let's find the json file in the pulled directory.

SUMMARY_FILES=("$LOCAL_RESULTS_DIR"/*.json)
if [ ${#SUMMARY_FILES[@]} -gt 0 ] && [ -f "${SUMMARY_FILES[0]}" ]; then
  SUMMARY_FILE="${SUMMARY_FILES[0]}"
  RUNS_LEDGER="$REPO_ROOT/registry/runs.jsonl"
  mkdir -p "$REPO_ROOT/registry"

  python3 - "$RUNS_LEDGER" "$SUMMARY_FILE" <<'PY'
import fcntl
import pathlib
import sys

ledger_path = pathlib.Path(sys.argv[1])
summary_path = pathlib.Path(sys.argv[2])

ledger_path.parent.mkdir(parents=True, exist_ok=True)

with ledger_path.open("a+", encoding="utf-8") as ledger, summary_path.open(encoding="utf-8") as summary:
    fcntl.flock(ledger.fileno(), fcntl.LOCK_EX)
    ledger.write(summary.read())
    ledger.write("\n")
    ledger.flush()
    fcntl.flock(ledger.fileno(), fcntl.LOCK_UN)
PY
  echo "Appended summary to runs.jsonl."
else
  echo "Warning: No summary JSON found in $LOCAL_RESULTS_DIR"
fi
