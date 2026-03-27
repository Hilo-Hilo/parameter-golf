#!/usr/bin/env bash
set -euo pipefail

# scripts/watcher.sh
# Monitors dispatched GPU jobs, collects artifacts, and runs diagnose/reflect.
# Works with the gpu_queue.jsonl written by branch_cycle.sh --plan-only.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
MAIN_CHECKOUT="$(cd "$(git -C "$REPO_ROOT" rev-parse --git-common-dir)/.." && pwd)"

WORKER_ID="${WATCHER_WORKER_ID:-watcher_0}"
RUN_ONCE=0
NO_VALIDATION=0
DISPATCH_BACKEND="${DISPATCH_BACKEND:-runpod}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --worker-id) WORKER_ID="$2"; shift 2 ;;
    --once) RUN_ONCE=1; shift ;;
    --no-validation) NO_VALIDATION=1; shift ;;
    *) shift ;;
  esac
done

# Source queue library
source "$MAIN_CHECKOUT/scripts/gpu_queue.sh"

announce() {
  printf '[%s][watcher/%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$WORKER_ID" "$*"
}

log_event() {
  "$SCRIPT_DIR/log_controller_event.sh" "$@" >/dev/null 2>&1 || true
}

cleanup_cmd() {
  case "$DISPATCH_BACKEND" in
    skypilot) echo "$MAIN_CHECKOUT/scripts/skypilot_cleanup.sh" ;;
    *) echo "$MAIN_CHECKOUT/scripts/runpod_cleanup.sh" ;;
  esac
}

# ---------------------------------------------------------------------------
# Process a single queued job: wait -> collect -> diagnose -> reflect
# ---------------------------------------------------------------------------

process_job() {
  local job_json="$1"
  local JOB_ID CHILD_NODE_ID NODE_ID BRANCH_NAME PHASE_LOG_DIR PLAN_WORKTREE

  JOB_ID="$(echo "$job_json" | jq -r '.job_id')"
  CHILD_NODE_ID="$(echo "$job_json" | jq -r '.child_node_id')"
  NODE_ID="$(echo "$job_json" | jq -r '.node_id')"
  BRANCH_NAME="$(echo "$job_json" | jq -r '.branch_name')"
  PHASE_LOG_DIR="$(echo "$job_json" | jq -r '.phase_log_dir')"
  PLAN_WORKTREE="$(echo "$job_json" | jq -r '.plan_worktree')"
  local TTL_EPOCH
  TTL_EPOCH="$(echo "$job_json" | jq -r '.controller_ttl_epoch')"

  announce "Processing job $JOB_ID (node=$NODE_ID)"

  # Load SSH details from lease
  local LEASE_FILE="$MAIN_CHECKOUT/registry/spool/${CHILD_NODE_ID}_lease.json"
  if [ ! -f "$LEASE_FILE" ]; then
    announce "Error: lease file not found for $CHILD_NODE_ID"
    update_gpu_job_status "$JOB_ID" "failed"
    return 1
  fi

  local SSH_TARGET SSH_PORT
  SSH_TARGET="$(jq -r '.ssh.host // empty' "$LEASE_FILE")"
  SSH_PORT="$(jq -r '.ssh.port // "22"' "$LEASE_FILE")"

  if [ -z "$SSH_TARGET" ]; then
    SSH_TARGET=$(cat "$MAIN_CHECKOUT/registry/spool/${CHILD_NODE_ID}_ssh_target.txt" 2>/dev/null || echo "")
    SSH_PORT=$(cat "$MAIN_CHECKOUT/registry/spool/${CHILD_NODE_ID}_ssh_port.txt" 2>/dev/null || echo "22")
  fi

  if [ -z "$SSH_TARGET" ]; then
    announce "Error: no SSH target for $CHILD_NODE_ID"
    update_gpu_job_status "$JOB_ID" "failed"
    return 1
  fi

  local POLL_INTERVAL=15

  # -----------------------------------------------------------------------
  # PHASE: wait_remote (SSH poll for tmux session)
  # -----------------------------------------------------------------------
  announce "Waiting for remote job $CHILD_NODE_ID on $SSH_TARGET:$SSH_PORT..."

  while true; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_TARGET" "tmux has-session -t job_${CHILD_NODE_ID} 2>/dev/null" >/dev/null 2>&1; then
      # Still running
      true
    elif ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_TARGET" "true" >/dev/null 2>&1; then
      # SSH works but tmux gone = job finished
      announce "Tmux session ended for $CHILD_NODE_ID. Job complete."
      log_event --event "remote_job_completed" --job-id "$CHILD_NODE_ID" --node-id "$NODE_ID" --phase "wait_remote" --status "completed" --message "remote tmux session ended"
      break
    else
      # SSH failed
      announce "SSH check failed for $CHILD_NODE_ID; retrying."
      # Check TTL
      local NOW_EPOCH
      NOW_EPOCH="$(date -u +%s)"
      if [ "$TTL_EPOCH" -gt 0 ] && [ "$NOW_EPOCH" -gt "$TTL_EPOCH" ]; then
        announce "Lease TTL expired for $CHILD_NODE_ID. Aborting."
        "$(cleanup_cmd)" --job-id "$CHILD_NODE_ID" --reason "controller_ttl_exceeded" >/dev/null 2>&1 || true
        update_gpu_job_status "$JOB_ID" "failed"
        return 1
      fi
    fi
    sleep "$POLL_INTERVAL"
  done

  # -----------------------------------------------------------------------
  # PHASE: collect
  # -----------------------------------------------------------------------
  announce "Collecting artifacts for $CHILD_NODE_ID..."
  update_gpu_job_status "$JOB_ID" "collecting"

  cd "$MAIN_CHECKOUT"
  if "$MAIN_CHECKOUT/scripts/runpod_collect.sh" "$SSH_TARGET" "$SSH_PORT" "$CHILD_NODE_ID" 2>/dev/null; then
    log_event --event "collect_completed" --job-id "$CHILD_NODE_ID" --status "appended" --message "artifact collection finished"
  else
    announce "Warning: collection failed for $CHILD_NODE_ID (may be partial)"
  fi

  # Cleanup: release lease but keep cluster alive for reuse
  "$(cleanup_cmd)" --job-id "$CHILD_NODE_ID" --reason "job_complete" >/dev/null 2>&1 || true

  # -----------------------------------------------------------------------
  # PHASE: diagnose + reflect (Claude analysis)
  # -----------------------------------------------------------------------
  update_gpu_job_status "$JOB_ID" "analyzing"

  local DIAGNOSE_OUTPUT="$PHASE_LOG_DIR/diagnose.output.json"
  local DIAGNOSE_STDERR="$PHASE_LOG_DIR/diagnose.stderr.log"
  local REFLECT_OUTPUT="$PHASE_LOG_DIR/reflect.output.json"
  local REFLECT_STDERR="$PHASE_LOG_DIR/reflect.stderr.log"

  # Build the prompt context (simplified version of build_plan_prompt)
  local LOG_FILE
  LOG_FILE="$(find "$MAIN_CHECKOUT/experiments/$CHILD_NODE_ID" -name '*.log' -type f 2>/dev/null | head -1 || echo "")"

  local DIAGNOSE_PROMPT="You are analyzing experiment $CHILD_NODE_ID.
The remote experiment has finished. Logs are at $LOG_FILE.
Please analyze the logs and summarize any issues.
Output JSON."

  local REFLECT_PROMPT="You are reflecting on experiment $CHILD_NODE_ID.
Review the diagnosis and outcome. Determine if this was a success and what to do next.
Output JSON."

  # Diagnose
  announce "Running diagnose phase for $CHILD_NODE_ID..."
  cd "$MAIN_CHECKOUT/$PLAN_WORKTREE" 2>/dev/null || cd "$MAIN_CHECKOUT"

  if ! claude -p "$DIAGNOSE_PROMPT" \
    --max-turns 100 \
    --max-budget-usd 10.00 \
    --tools "Read,Edit,Glob,Grep" \
    --settings "$MAIN_CHECKOUT/.claude/settings.json" \
    --mcp-config "$MAIN_CHECKOUT/.mcp.json" \
    --strict-mcp-config \
    --no-session-persistence \
    --output-format json \
    --json-schema "$(python3 -c 'import json; print(json.dumps(json.load(open("'"$MAIN_CHECKOUT/schemas/diagnose_schema.json"'"))))' 2>/dev/null || echo '{}')" \
    > "$DIAGNOSE_OUTPUT" 2> "$DIAGNOSE_STDERR" < /dev/null; then
    announce "Warning: diagnose phase exited non-zero for $CHILD_NODE_ID"
  fi

  # Reflect
  announce "Running reflect phase for $CHILD_NODE_ID..."
  if ! claude -p "$REFLECT_PROMPT" \
    --max-turns 50 \
    --max-budget-usd 5.00 \
    --tools "Read,Edit,Glob,Grep" \
    --settings "$MAIN_CHECKOUT/.claude/settings.json" \
    --mcp-config "$MAIN_CHECKOUT/.mcp.json" \
    --strict-mcp-config \
    --no-session-persistence \
    --output-format json \
    --json-schema "$(python3 -c 'import json; print(json.dumps(json.load(open("'"$MAIN_CHECKOUT/schemas/reflect_schema.json"'"))))' 2>/dev/null || echo '{}')" \
    > "$REFLECT_OUTPUT" 2> "$REFLECT_STDERR" < /dev/null; then
    announce "Warning: reflect phase exited non-zero for $CHILD_NODE_ID"
  fi

  # Parse action from reflect output
  local ACTION
  ACTION=$(jq -r '.structured_output.recommended_action // "discard"' "$REFLECT_OUTPUT" 2>/dev/null || echo "discard")

  # Update node status
  python3 - "$MAIN_CHECKOUT/registry/nodes.jsonl" "$MAIN_CHECKOUT/registry/.nodes.lock" "$CHILD_NODE_ID" "$ACTION" <<'PY'
import fcntl
import json
import pathlib
import sys

db_path = pathlib.Path(sys.argv[1])
lock_path = pathlib.Path(sys.argv[2])
node_id = sys.argv[3]
action = sys.argv[4]

lock_path.touch(exist_ok=True)

with lock_path.open("a+", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    with db_path.open("a", encoding="utf-8") as db_file:
        db_file.write(json.dumps({"node_id": node_id, "status": action}) + "\n")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
PY

  # Create tree ref for branched nodes
  if [ "$ACTION" = "branch" ] || [ "$ACTION" = "keep" ]; then
    local CHILD_TREE_REF="tree/$CHILD_NODE_ID"
    if ! git -C "$MAIN_CHECKOUT" show-ref --verify --quiet "refs/heads/$CHILD_TREE_REF" 2>/dev/null; then
      git -C "$MAIN_CHECKOUT" branch "$CHILD_TREE_REF" HEAD 2>/dev/null || true
      announce "Created $CHILD_TREE_REF for child iteration."
    fi
  fi

  log_event --event "reflection_recorded" --job-id "$CHILD_NODE_ID" --node-id "$NODE_ID" --phase "reflect" --status "$ACTION" --message "watcher completed full cycle"

  announce "Job $CHILD_NODE_ID complete. Action: $ACTION."
  update_gpu_job_status "$JOB_ID" "done"

  # Clean up scratch worktree
  local SCRATCH_REF
  SCRATCH_REF="$(basename "$PLAN_WORKTREE")"
  git -C "$MAIN_CHECKOUT" worktree remove -f "$MAIN_CHECKOUT/$PLAN_WORKTREE" 2>/dev/null || true
  git -C "$MAIN_CHECKOUT" branch -D "$SCRATCH_REF" 2>/dev/null || true

  return 0
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

announce "Watcher started."

while true; do
  JOB_JSON="$(claim_gpu_job "dispatched" "collecting" 2>/dev/null || echo "")"

  if [ -n "$JOB_JSON" ]; then
    process_job "$JOB_JSON" || true
  else
    if [ "$RUN_ONCE" -eq 1 ]; then
      announce "No jobs in queue. Exiting (--once mode)."
      exit 0
    fi
    sleep 15
  fi

  if [ "$RUN_ONCE" -eq 1 ]; then
    exit 0
  fi
done
