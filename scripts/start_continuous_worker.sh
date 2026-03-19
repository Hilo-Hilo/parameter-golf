#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/start_continuous_worker.sh [--branch <name>] [--channel <id>] [--account-id <id>] [--to <id>] [--force-restart]

Launch the detached continuous Parameter Golf Codex worker and write watchdog state.
EOF
}

BRANCH="research/continuous-mar18"
OWNER_CHANNEL="telegram"
OWNER_ACCOUNT_ID="clawd4"
OWNER_TO="8173956648"
FORCE_RESTART=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --channel) OWNER_CHANNEL="$2"; shift 2 ;;
    --account-id) OWNER_ACCOUNT_ID="$2"; shift 2 ;;
    --to) OWNER_TO="$2"; shift 2 ;;
    --force-restart) FORCE_RESTART=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
STATE_DIR="$REPO_ROOT/automation/state"
LOG_DIR="$REPO_ROOT/automation/logs"
STATE_FILE="$STATE_DIR/continuous_worker.json"
LOCK_FILE="$STATE_DIR/continuous_worker.lock"
LOG_FILE="$LOG_DIR/continuous_worker.log"
PROMPT_FILE="$REPO_ROOT/automation/continuous_worker_prompt.md"
JOURNAL_FILE="$REPO_ROOT/journal.md"

mkdir -p "$STATE_DIR" "$LOG_DIR"
: > "$LOCK_FILE"

PREV_RESTART_COUNT=0
if [[ -f "$STATE_FILE" ]]; then
  PREV_RESTART_COUNT="$(python3 - "$STATE_FILE" <<'PY'
import json, sys
from pathlib import Path
try:
    data = json.loads(Path(sys.argv[1]).read_text())
except Exception:
    print(0)
else:
    print(int(data.get("restartCount", 0)))
PY
)"
fi

if [[ $FORCE_RESTART -eq 0 && -f "$STATE_FILE" ]]; then
  EXISTING_PID="$(python3 - "$STATE_FILE" <<'PY'
import json, sys
from pathlib import Path
try:
    data = json.loads(Path(sys.argv[1]).read_text())
except Exception:
    print("")
else:
    print(data.get("pid", ""))
PY
)"
  if [[ -n "$EXISTING_PID" ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
    STATE_FILE="$STATE_FILE" LOG_FILE="$LOG_FILE" EXISTING_PID="$EXISTING_PID" python3 - <<'PY'
import json, os
print(json.dumps({
  "status": "already-running",
  "pid": int(os.environ["EXISTING_PID"]),
  "stateFile": os.environ["STATE_FILE"],
  "logFile": os.environ["LOG_FILE"],
}, indent=2))
PY
    exit 0
  fi
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git switch "$BRANCH" >/dev/null 2>&1
  else
    git switch -c "$BRANCH" --track "origin/$BRANCH" >/dev/null 2>&1 || git switch -c "$BRANCH" >/dev/null 2>&1
  fi
fi

PROMPT_QUOTED="$(python3 - "$PROMPT_FILE" <<'PY'
import shlex, sys
from pathlib import Path
print(shlex.quote(Path(sys.argv[1]).read_text()))
PY
)"
CMD="cd $(printf '%q' "$REPO_ROOT") && exec codex --yolo exec ${PROMPT_QUOTED}"
nohup script -q /dev/null /bin/zsh -lc "$CMD" >> "$LOG_FILE" 2>&1 &
PID=$!
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
RESTART_COUNT=$((PREV_RESTART_COUNT + 1))
if [[ ! -f "$STATE_FILE" ]]; then
  RESTART_COUNT=0
fi

REPO_ROOT="$REPO_ROOT" BRANCH="$BRANCH" PROMPT_FILE="$PROMPT_FILE" JOURNAL_FILE="$JOURNAL_FILE" LOG_FILE="$LOG_FILE" LOCK_FILE="$LOCK_FILE" STATE_FILE="$STATE_FILE" OWNER_CHANNEL="$OWNER_CHANNEL" OWNER_ACCOUNT_ID="$OWNER_ACCOUNT_ID" OWNER_TO="$OWNER_TO" NOW="$NOW" PID="$PID" RESTART_COUNT="$RESTART_COUNT" python3 - <<'PY'
import json, os
from pathlib import Path
state = {
  "repoRoot": os.environ["REPO_ROOT"],
  "branch": os.environ["BRANCH"],
  "launcher": "scripts/start_continuous_worker.sh",
  "promptFile": os.environ["PROMPT_FILE"],
  "journalFile": os.environ["JOURNAL_FILE"],
  "logFile": os.environ["LOG_FILE"],
  "lockFile": os.environ["LOCK_FILE"],
  "operatingMode": "remote-first-24-7",
  "preferredCompute": ["dgx-spark", "runpod"],
  "secondaryCompute": ["local-mlx"],
  "researchStrategy": "architecture-first",
  "journalPolicy": "append-only",
  "pid": int(os.environ["PID"]),
  "owner": {
    "channel": os.environ["OWNER_CHANNEL"],
    "accountId": os.environ["OWNER_ACCOUNT_ID"],
    "to": os.environ["OWNER_TO"],
  },
  "lastLaunchAt": os.environ["NOW"],
  "lastHealthyAt": os.environ["NOW"],
  "lastMilestoneAt": None,
  "lastRestartAt": os.environ["NOW"],
  "restartCount": int(os.environ["RESTART_COUNT"]),
  "staleAfterSeconds": 5400,
  "deadAfterSeconds": 1200,
  "restartCooldownSeconds": 1200,
}
Path(os.environ["STATE_FILE"]).write_text(json.dumps(state, indent=2) + "\n")
print(json.dumps({
  "status": "started",
  "pid": state["pid"],
  "stateFile": os.environ["STATE_FILE"],
  "logFile": os.environ["LOG_FILE"],
  "branch": state["branch"],
}, indent=2))
PY
