#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <job_id>" >&2
  exit 1
fi
JOB_ID="$1"

echo "Canceling job $JOB_ID..."
tmux kill-session -t "job_${JOB_ID}" 2>/dev/null || echo "Session not found."
