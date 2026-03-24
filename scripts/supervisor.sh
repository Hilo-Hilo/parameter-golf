#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
NODES_DB="$REPO_ROOT/registry/nodes.jsonl"
LOCK_FILE="$REPO_ROOT/registry/.supervisor.lock"

mkdir -p "$REPO_ROOT/registry"
touch "$NODES_DB"

echo "Checking for pending nodes..."

PENDING_NODE="$(
  python3 - "$NODES_DB" "$LOCK_FILE" <<'PY'
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
    try:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("__LOCKED__")
        raise SystemExit(0)

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

if [ "$PENDING_NODE" = "__LOCKED__" ]; then
  echo "Supervisor already running."
  exit 0
fi

if [ -n "$PENDING_NODE" ]; then
  echo "Found pending node: $PENDING_NODE. Starting branch cycle..."
  "$REPO_ROOT/scripts/branch_cycle.sh" "$PENDING_NODE"
else
  echo "No pending nodes found."
fi