#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
STATE_FILE="$REPO_ROOT/automation/state/continuous_worker.json"
RESEARCH_STATE_FILE="$REPO_ROOT/automation/state/research_state.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"status":"missing","reason":"state-file-missing"}'
  exit 0
fi

PID="$(python3 - "$STATE_FILE" <<'PY'
import json, sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text()).get("pid", ""))
PY
)"

if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
  kill "$PID" || true
  sleep 1
  if kill -0 "$PID" 2>/dev/null; then
    kill -9 "$PID" || true
  fi
  STOP_REASON="killed-by-script"
else
  STOP_REASON="not-running"
fi

if [[ -f "$RESEARCH_STATE_FILE" ]]; then
  python3 "$REPO_ROOT/scripts/research_state.py" mark-stop \
    --repo-root "$REPO_ROOT" \
    --research-state-file "$RESEARCH_STATE_FILE" \
    --reason "$STOP_REASON" >/dev/null
fi

if [[ "$STOP_REASON" == "killed-by-script" ]]; then
  echo "{\"status\":\"stopped\",\"pid\":$PID}"
else
  echo "{\"status\":\"not-running\",\"pid\":${PID:-null},\"reason\":\"$STOP_REASON\"}"
fi
