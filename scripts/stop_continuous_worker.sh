#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
STATE_FILE="$REPO_ROOT/automation/state/continuous_worker.json"

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
  echo "{\"status\":\"stopped\",\"pid\":$PID}"
else
  echo "{\"status\":\"not-running\",\"pid\":${PID:-null}}"
fi
