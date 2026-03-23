#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
PID_FILE="$REPO_ROOT/automation/worker.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "not running (no pid file)"
  exit 0
fi

PID="$(cat "$PID_FILE")"
if kill "$PID" 2>/dev/null; then
  echo "stopped (pid $PID)"
else
  echo "already dead (pid $PID)"
fi
rm -f "$PID_FILE"
