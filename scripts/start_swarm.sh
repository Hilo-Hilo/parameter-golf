#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/start_swarm.sh [options]

Options:
  --node-id NODE_ID       Seed node to enqueue. Default: root
  --base-ref REF          Base ref for tree/<node_id>. Default: main
  --loop-seconds N        Sleep interval between supervisor passes. Default: 30
  --no-validation         Route launched work to the 1xH100 non-record lane
  --once                  Run a single supervisor pass instead of looping
  --reset-tree-ref        Reset tree/<node_id> to --base-ref before starting
  -h, --help              Show this help
EOF
}

NODE_ID="root"
BASE_REF="main"
LOOP_SECONDS=30
NO_VALIDATION=0
RUN_ONCE=0
RESET_TREE_REF=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --node-id)
      NODE_ID="${2:-}"
      shift 2
      ;;
    --base-ref)
      BASE_REF="${2:-}"
      shift 2
      ;;
    --loop-seconds)
      LOOP_SECONDS="${2:-}"
      shift 2
      ;;
    --no-validation)
      NO_VALIDATION=1
      shift
      ;;
    --once)
      RUN_ONCE=1
      shift
      ;;
    --reset-tree-ref)
      RESET_TREE_REF=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$NODE_ID" ] || [ -z "$BASE_REF" ]; then
  echo "Error: --node-id and --base-ref must not be empty." >&2
  exit 2
fi

if ! [[ "$LOOP_SECONDS" =~ ^[0-9]+$ ]] || [ "$LOOP_SECONDS" -lt 1 ]; then
  echo "Error: --loop-seconds must be a positive integer." >&2
  exit 2
fi

REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
NODES_DB="$REPO_ROOT/registry/nodes.jsonl"
TREE_REF="tree/$NODE_ID"

ensure_claude_auth() {
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    return 0
  fi

  if ! command -v claude >/dev/null 2>&1; then
    echo "Error: claude CLI is not installed or not on PATH." >&2
    exit 2
  fi

  local auth_status
  auth_status="$(claude auth status 2>/dev/null || true)"
  if [ -n "$auth_status" ] && printf '%s' "$auth_status" | jq -e '.loggedIn == true' >/dev/null 2>&1; then
    return 0
  fi

  echo "Error: Claude CLI is not authenticated for controller use." >&2
  echo "Run 'claude auth login' for subscription auth, or export ANTHROPIC_API_KEY before starting the swarm." >&2
  exit 2
}

if ! git -C "$REPO_ROOT" rev-parse --verify "${BASE_REF}^{commit}" >/dev/null 2>&1; then
  echo "Error: base ref $BASE_REF does not resolve to a commit." >&2
  exit 2
fi

ensure_claude_auth

mkdir -p "$REPO_ROOT/registry"
touch "$NODES_DB"

if [ -z "${RUNPOD_TEMPLATE_ID:-}" ]; then
  echo "Warning: RUNPOD_TEMPLATE_ID is not set. The controller can reuse an existing pg-* pod but cannot provision a new one." >&2
fi

if [ "$RESET_TREE_REF" -eq 1 ]; then
  git -C "$REPO_ROOT" branch -f "$TREE_REF" "$BASE_REF" >/dev/null
  echo "Reset $TREE_REF to $BASE_REF."
elif git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$TREE_REF"; then
  echo "Using existing $TREE_REF."
else
  git -C "$REPO_ROOT" branch "$TREE_REF" "$BASE_REF" >/dev/null
  echo "Created $TREE_REF from $BASE_REF."
fi

QUEUE_RESULT="$(
  python3 - "$NODES_DB" "$NODE_ID" <<'PY'
import fcntl
import json
import pathlib
import re
import subprocess
import sys

db_path = pathlib.Path(sys.argv[1])
node_id = sys.argv[2]
lock_path = db_path.parent / ".nodes.lock"

process_output = subprocess.check_output(["ps", "-axo", "command"], text=True)
live_branch_cycle = re.compile(rf"scripts/branch_cycle\.sh(?:\s+--no-validation)?\s+{re.escape(node_id)}(?:\s|$)")

db_path.parent.mkdir(parents=True, exist_ok=True)
db_path.touch(exist_ok=True)
lock_path.touch(exist_ok=True)

with lock_path.open("a+", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

    rows = []
    active = False
    recovered = False
    for raw_line in db_path.read_text(encoding="utf-8").splitlines():
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        try:
            row = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        if row.get("node_id") == node_id:
            if row.get("status") == "pending":
                active = True
            elif row.get("status") == "running":
                if live_branch_cycle.search(process_output):
                    active = True
                else:
                    row["status"] = "pending"
                    active = True
                    recovered = True
        rows.append(row)

    if recovered:
        with db_path.open("w", encoding="utf-8") as db_file:
            for row in rows:
                db_file.write(json.dumps(row))
                db_file.write("\n")
        print("recovered")
    elif active:
        print("existing")
    else:
        with db_path.open("a", encoding="utf-8") as db_file:
            db_file.write(json.dumps({"node_id": node_id, "status": "pending"}))
            db_file.write("\n")
        print("queued")

    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
PY
)"

case "$QUEUE_RESULT" in
  queued)
    echo "Queued node $NODE_ID in registry/nodes.jsonl."
    ;;
  recovered)
    echo "Recovered stale running node $NODE_ID and re-queued it as pending."
    ;;
  existing)
    echo "Node $NODE_ID already has an active pending/running entry."
    ;;
esac

cd "$REPO_ROOT"

run_supervisor() {
  if [ "$NO_VALIDATION" -eq 1 ]; then
    "$REPO_ROOT/scripts/supervisor.sh" --no-validation
  else
    "$REPO_ROOT/scripts/supervisor.sh"
  fi
}

if [ "$RUN_ONCE" -eq 1 ]; then
  run_supervisor
  exit 0
fi

echo "Starting supervisor loop for node $NODE_ID (interval ${LOOP_SECONDS}s)..."
trap 'echo "Stopping swarm loop."; exit 0' INT TERM
while true; do
  run_supervisor
  sleep "$LOOP_SECONDS"
done
