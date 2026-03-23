#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
PID_FILE="$REPO_ROOT/automation/worker.pid"
LOG_FILE="$REPO_ROOT/automation/worker.log"
PROMPT_FILE="$REPO_ROOT/worker_program.md"

if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE")"
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "already running (pid $OLD_PID)"
    exit 0
  fi
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "missing $PROMPT_FILE" >&2
  exit 1
fi

mkdir -p "$(dirname "$PID_FILE")"

PROMPT="$(cat "$PROMPT_FILE")"

nohup claude --dangerously-skip-permissions -p "$PROMPT" >> "$LOG_FILE" 2>&1 &
PID=$!
echo "$PID" > "$PID_FILE"
echo "started (pid $PID), log: $LOG_FILE"
