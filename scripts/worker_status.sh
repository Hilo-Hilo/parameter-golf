#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
PID_FILE="$REPO_ROOT/automation/worker.pid"
LOG_FILE="$REPO_ROOT/automation/worker.log"

if [[ ! -f "$PID_FILE" ]]; then
  echo "stopped"
  exit 0
fi

PID="$(cat "$PID_FILE")"
if kill -0 "$PID" 2>/dev/null; then
  echo "running (pid $PID)"
  [[ -f "$LOG_FILE" ]] && echo "log tail:" && tail -5 "$LOG_FILE"
else
  echo "dead (pid $PID)"
  rm -f "$PID_FILE"
fi
