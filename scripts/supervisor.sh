#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--no-validation] [--worker-id ID]" >&2
}

NO_VALIDATION=0
WORKER_ID="0"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-validation)
      NO_VALIDATION=1
      shift
      ;;
    --worker-id)
      WORKER_ID="${2:-0}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option $1" >&2
      usage
      exit 2
      ;;
  esac
done

REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
NODES_DB="$REPO_ROOT/registry/nodes.jsonl"
NODES_LOCK="$REPO_ROOT/registry/.nodes.lock"

announce() {
  printf '[%s][supervisor/w%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$WORKER_ID" "$*"
}

log_event() {
  "$REPO_ROOT/scripts/log_controller_event.sh" "$@" >/dev/null 2>&1 || true
}

mkdir -p "$REPO_ROOT/registry"
touch "$NODES_DB"

announce "Reconciling stale leases..."
"$REPO_ROOT/scripts/runpod_reconcile.sh" || true
if [ "${DISPATCH_BACKEND:-runpod}" = "skypilot" ] && command -v sky >/dev/null 2>&1; then
  "$REPO_ROOT/scripts/skypilot_reconcile.sh" || true
fi

announce "Checking for pending nodes..."

# Claim one pending node atomically under .nodes.lock (blocking).
# Multiple concurrent supervisors safely serialize here and each claim
# a different pending node.
PENDING_NODE="$(
  python3 - "$NODES_DB" "$NODES_LOCK" <<'PY'
import fcntl
import json
import os
import pathlib
import sys
import tempfile

db_path = pathlib.Path(sys.argv[1])
lock_path = pathlib.Path(sys.argv[2])

lock_path.parent.mkdir(parents=True, exist_ok=True)
db_path.parent.mkdir(parents=True, exist_ok=True)
db_path.touch(exist_ok=True)

rows = []
pending_node = ""

with lock_path.open("a+", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

    for raw_line in db_path.read_text(encoding="utf-8").splitlines():
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        try:
            row = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        rows.append(row)

    for row in rows:
        if row.get("status") == "pending":
            pending_node = row.get("node_id", "")
            row["status"] = "running"
            break

    fd, tmp_path = tempfile.mkstemp(dir=str(db_path.parent), prefix=".nodes.", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp_file:
            for row in rows:
                tmp_file.write(json.dumps(row))
                tmp_file.write("\n")
        os.replace(tmp_path, db_path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

print(pending_node)
PY
)"

if [ -n "$PENDING_NODE" ]; then
  announce "Found pending node: $PENDING_NODE. Starting branch cycle..."
  log_event \
    --event "node_claimed" \
    --node-id "$PENDING_NODE" \
    --status "running" \
    --message "supervisor/w${WORKER_ID} claimed a pending node and is launching branch_cycle"
  cycle_rc=0
  if [ "$NO_VALIDATION" -eq 1 ]; then
    "$REPO_ROOT/scripts/branch_cycle.sh" --no-validation "$PENDING_NODE" || cycle_rc=$?
  else
    "$REPO_ROOT/scripts/branch_cycle.sh" "$PENDING_NODE" || cycle_rc=$?
  fi
  if [ "$cycle_rc" -ne 0 ]; then
    announce "Warning: branch_cycle for $PENDING_NODE exited with code $cycle_rc"
    log_event \
      --event "branch_cycle_failed" \
      --node-id "$PENDING_NODE" \
      --status "failed" \
      --message "branch_cycle exited with code $cycle_rc"
  fi
else
  announce "No pending nodes found."
  log_event \
    --event "supervisor_idle" \
    --status "idle" \
    --message "supervisor/w${WORKER_ID} found no pending nodes"
fi
