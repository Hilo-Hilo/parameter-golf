#!/usr/bin/env bash
# scripts/gpu_queue.sh
# Lightweight file-based job queue for pipelined plan/execute/analyze.
# Sourced by other scripts (not executed directly).

GPU_QUEUE_FILE="${GPU_QUEUE_FILE:-$REPO_ROOT/registry/gpu_queue.jsonl}"
GPU_QUEUE_LOCK="${GPU_QUEUE_LOCK:-$REPO_ROOT/registry/.gpu_queue.lock}"

# Enqueue a dispatched job. Called by branch_cycle.sh --plan-only after dispatch.
enqueue_gpu_job() {
  local job_id="$1"
  local node_id="$2"
  local child_node_id="$3"
  local branch_name="$4"
  local commit_sha="$5"
  local phase_log_dir="$6"
  local plan_worktree="$7"
  local no_validation="$8"
  local controller_ttl_epoch="$9"

  python3 - "$GPU_QUEUE_FILE" "$GPU_QUEUE_LOCK" \
    "$job_id" "$node_id" "$child_node_id" "$branch_name" "$commit_sha" \
    "$phase_log_dir" "$plan_worktree" "$no_validation" "$controller_ttl_epoch" <<'PY'
import fcntl
import json
import pathlib
import sys
from datetime import datetime, timezone

queue_path = pathlib.Path(sys.argv[1])
lock_path = pathlib.Path(sys.argv[2])
job_id = sys.argv[3]
node_id = sys.argv[4]
child_node_id = sys.argv[5]
branch_name = sys.argv[6]
commit_sha = sys.argv[7]
phase_log_dir = sys.argv[8]
plan_worktree = sys.argv[9]
no_validation = sys.argv[10]
controller_ttl_epoch = sys.argv[11]

queue_path.parent.mkdir(parents=True, exist_ok=True)
lock_path.touch(exist_ok=True)

now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
record = {
    "job_id": job_id,
    "node_id": node_id,
    "child_node_id": child_node_id,
    "status": "dispatched",
    "branch_name": branch_name,
    "commit_sha": commit_sha,
    "phase_log_dir": phase_log_dir,
    "plan_worktree": plan_worktree,
    "no_validation": int(no_validation),
    "controller_ttl_epoch": int(controller_ttl_epoch),
    "enqueued_at": now,
}

with lock_path.open("a+", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    with queue_path.open("a", encoding="utf-8") as qf:
        qf.write(json.dumps(record) + "\n")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

print(job_id)
PY
}

# Claim the next job with the given status. Atomically transitions to next_status.
# Prints the full JSON record to stdout. Returns 1 if no jobs available.
claim_gpu_job() {
  local target_status="$1"
  local next_status="$2"

  python3 - "$GPU_QUEUE_FILE" "$GPU_QUEUE_LOCK" "$target_status" "$next_status" <<'PY'
import fcntl
import json
import os
import pathlib
import sys
import tempfile

queue_path = pathlib.Path(sys.argv[1])
lock_path = pathlib.Path(sys.argv[2])
target_status = sys.argv[3]
next_status = sys.argv[4]

if not queue_path.exists():
    raise SystemExit(1)

lock_path.touch(exist_ok=True)

with lock_path.open("a+", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

    rows = []
    claimed = None
    for line in queue_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if claimed is None and row.get("status") == target_status:
            row["status"] = next_status
            claimed = row
        rows.append(row)

    if claimed is None:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        raise SystemExit(1)

    fd, tmp = tempfile.mkstemp(dir=str(queue_path.parent), prefix=".gpu_queue.", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp_file:
            for row in rows:
                tmp_file.write(json.dumps(row) + "\n")
        os.replace(tmp, str(queue_path))
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

print(json.dumps(claimed))
PY
}

# Update a specific job's status.
update_gpu_job_status() {
  local job_id="$1"
  local new_status="$2"

  python3 - "$GPU_QUEUE_FILE" "$GPU_QUEUE_LOCK" "$job_id" "$new_status" <<'PY'
import fcntl
import json
import os
import pathlib
import sys
import tempfile

queue_path = pathlib.Path(sys.argv[1])
lock_path = pathlib.Path(sys.argv[2])
job_id = sys.argv[3]
new_status = sys.argv[4]

if not queue_path.exists():
    raise SystemExit(1)

lock_path.touch(exist_ok=True)

with lock_path.open("a+", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

    rows = []
    found = False
    for line in queue_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if row.get("job_id") == job_id:
            row["status"] = new_status
            found = True
        rows.append(row)

    if found:
        fd, tmp = tempfile.mkstemp(dir=str(queue_path.parent), prefix=".gpu_queue.", text=True)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as tmp_file:
                for row in rows:
                    tmp_file.write(json.dumps(row) + "\n")
            os.replace(tmp, str(queue_path))
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)

    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

if not found:
    raise SystemExit(1)
PY
}
