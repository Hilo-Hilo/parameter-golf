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
    shadeform) echo "$MAIN_CHECKOUT/scripts/shadeform_cleanup.sh" ;;
    skypilot)  echo "$MAIN_CHECKOUT/scripts/skypilot_cleanup.sh" ;;
    *)         echo "$MAIN_CHECKOUT/scripts/runpod_cleanup.sh" ;;
  esac
}

SSH_KEY_FILE="${SHADEFORM_SSH_KEY_FILE:-$HOME/.shadeform/ssh_key}"
SSH_ID_OPT=()
[ "$DISPATCH_BACKEND" = "shadeform" ] && [ -f "$SSH_KEY_FILE" ] && SSH_ID_OPT=(-i "$SSH_KEY_FILE")
BASE_SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR)

# For Shadeform: SSH connects to the host VM; tmux sessions live inside
# the Docker container. Returns running container ID or empty string.
get_shadeform_container_id() {
  local ssh_host="$1" ssh_port="$2"
  ssh "${BASE_SSH_OPTS[@]}" "${SSH_ID_OPT[@]}" -p "$ssh_port" "$ssh_host" \
    "docker ps --format '{{.ID}}' | head -1" 2>/dev/null || echo ''
}

# Copy experiment artifacts directly from the container to the Mac via tar pipe
# over SSH. Bypasses the host VM filesystem (which has no /workspace).
pre_collect_from_container() {
  local job_id="$1" ssh_host="$2" ssh_port="$3" cid="$4"
  [ -z "$cid" ] && return 0
  local local_exp_parent="$MAIN_CHECKOUT/experiments"
  local local_spool_dir="$MAIN_CHECKOUT/registry/spool"
  mkdir -p "$local_exp_parent" "$local_spool_dir"
  for src in "/workspace/parameter-golf/experiments/$job_id" \
             "/workspace/jobs/$job_id/experiments/$job_id"; do
    ssh "${BASE_SSH_OPTS[@]}" "${SSH_ID_OPT[@]}" -p "$ssh_port" "$ssh_host" \
      "docker exec \"$cid\" test -d \"$src\" 2>/dev/null && docker cp \"$cid\":\"$src\" - 2>/dev/null" \
      2>/dev/null | tar xf - -C "$local_exp_parent/" 2>/dev/null || true
  done
  ssh "${BASE_SSH_OPTS[@]}" "${SSH_ID_OPT[@]}" -p "$ssh_port" "$ssh_host" \
    "docker exec \"$cid\" test -f \"/workspace/parameter-golf/registry/spool/${job_id}.json\" 2>/dev/null && \
     docker cp \"$cid\":\"/workspace/parameter-golf/registry/spool/${job_id}.json\" - 2>/dev/null" \
    2>/dev/null | tar xf - -C "$local_spool_dir/" 2>/dev/null || true
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

  # Dispatch to GPU cluster if not yet dispatched (plan-only mode enqueues
  # before dispatch so the watcher serializes cluster creation).
  local LEASE_FILE="$MAIN_CHECKOUT/registry/spool/${CHILD_NODE_ID}_lease.json"
  local JOB_SPEC="$MAIN_CHECKOUT/registry/spool/${CHILD_NODE_ID}_job.json"
  if [ ! -f "$LEASE_FILE" ] || ! jq -e '.ssh.host' "$LEASE_FILE" >/dev/null 2>&1; then
    if [ ! -f "$JOB_SPEC" ]; then
      announce "Error: no job spec for $CHILD_NODE_ID"
      update_gpu_job_status "$JOB_ID" "failed"
      return 1
    fi
    announce "Dispatching $CHILD_NODE_ID to GPU cluster..."
    update_gpu_job_status "$JOB_ID" "dispatching"
    local dispatch_script
    case "$DISPATCH_BACKEND" in
      shadeform) dispatch_script="$MAIN_CHECKOUT/scripts/shadeform_dispatch.sh" ;;
      skypilot)  dispatch_script="$MAIN_CHECKOUT/scripts/skypilot_dispatch.sh" ;;
      *)         dispatch_script="$MAIN_CHECKOUT/scripts/runpod_dispatch.sh" ;;
    esac
    if ! CONTROLLER_LOG_LABEL="$BRANCH_NAME" "$dispatch_script" "$JOB_SPEC"; then
      announce "Dispatch failed for $CHILD_NODE_ID"
      update_gpu_job_status "$JOB_ID" "failed"
      return 1
    fi
    update_gpu_job_status "$JOB_ID" "collecting"
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
  # Grace period: number of consecutive "no session" checks required before
  # declaring the job done. Prevents false-finish when the bootstrap is still
  # launching the tmux session on a warm reused instance (~60s window).
  local GRACE_CHECKS=4   # 4 × 15s = 60s grace
  local no_session_streak=0
  local session_seen=0   # flips to 1 once the session has existed at least once

  # -----------------------------------------------------------------------
  # PHASE: wait_remote (SSH poll for tmux session)
  # -----------------------------------------------------------------------
  announce "Waiting for remote job $CHILD_NODE_ID on $SSH_TARGET:$SSH_PORT..."

  local CONTAINER_ID=""
  while true; do
    if ssh "${BASE_SSH_OPTS[@]}" "${SSH_ID_OPT[@]}" -p "$SSH_PORT" "$SSH_TARGET" "true" >/dev/null 2>&1; then
      # SSH reachable — for Shadeform check tmux inside container, otherwise check host directly.
      if [ "$DISPATCH_BACKEND" = "shadeform" ]; then
        [ -z "$CONTAINER_ID" ] && CONTAINER_ID="$(get_shadeform_container_id "$SSH_TARGET" "$SSH_PORT")"
        if [ -n "$CONTAINER_ID" ]; then
          if ssh "${BASE_SSH_OPTS[@]}" "${SSH_ID_OPT[@]}" -p "$SSH_PORT" "$SSH_TARGET" \
              "docker exec \"$CONTAINER_ID\" tmux has-session -t job_${CHILD_NODE_ID} 2>/dev/null" >/dev/null 2>&1; then
            session_seen=1
            no_session_streak=0
          else
            no_session_streak=$(( no_session_streak + 1 ))
            # Only declare done if session was seen before OR grace period exhausted
            if [ "$session_seen" -eq 1 ] || [ "$no_session_streak" -gt "$GRACE_CHECKS" ]; then
              announce "Tmux session ended for $CHILD_NODE_ID. Job complete."
              log_event --event "remote_job_completed" --job-id "$CHILD_NODE_ID" --node-id "$NODE_ID" --phase "wait_remote" --status "completed" --message "remote tmux session ended"
              break
            fi
            announce "No tmux session yet for $CHILD_NODE_ID (streak=$no_session_streak/${GRACE_CHECKS}, still in grace)..."
          fi
        fi
        # Container not up yet — keep waiting
      else
        if ssh "${BASE_SSH_OPTS[@]}" -p "$SSH_PORT" "$SSH_TARGET" \
            "tmux has-session -t job_${CHILD_NODE_ID} 2>/dev/null" >/dev/null 2>&1; then
          session_seen=1
          no_session_streak=0
        else
          no_session_streak=$(( no_session_streak + 1 ))
          if [ "$session_seen" -eq 1 ] || [ "$no_session_streak" -gt "$GRACE_CHECKS" ]; then
            announce "Tmux session ended for $CHILD_NODE_ID. Job complete."
            log_event --event "remote_job_completed" --job-id "$CHILD_NODE_ID" --node-id "$NODE_ID" --phase "wait_remote" --status "completed" --message "remote tmux session ended"
            break
          fi
          announce "No tmux session yet for $CHILD_NODE_ID (streak=$no_session_streak/${GRACE_CHECKS}, still in grace)..."
        fi
      fi
    else
      announce "SSH check failed for $CHILD_NODE_ID; retrying."
    fi
    # Check TTL
    local NOW_EPOCH
    NOW_EPOCH="$(date -u +%s)"
    if [ "$TTL_EPOCH" -gt 0 ] && [ "$NOW_EPOCH" -gt "$TTL_EPOCH" ]; then
      announce "Lease TTL expired for $CHILD_NODE_ID. Aborting."
      "$(cleanup_cmd)" --job-id "$CHILD_NODE_ID" --reason "controller_ttl_exceeded" >/dev/null 2>&1 || true
      update_gpu_job_status "$JOB_ID" "failed"
      return 1
    fi
    sleep "$POLL_INTERVAL"
  done

  # -----------------------------------------------------------------------
  # PHASE: collect
  # -----------------------------------------------------------------------
  announce "Collecting artifacts for $CHILD_NODE_ID..."
  update_gpu_job_status "$JOB_ID" "collecting"

  cd "$MAIN_CHECKOUT"
  if [ "$DISPATCH_BACKEND" = "shadeform" ] && [ -n "$CONTAINER_ID" ]; then
    pre_collect_from_container "$CHILD_NODE_ID" "$SSH_TARGET" "$SSH_PORT" "$CONTAINER_ID"
  fi
  if SSH_IDENTITY_FILE="${SSH_KEY_FILE:-}" \
     "$MAIN_CHECKOUT/scripts/runpod_collect.sh" "$SSH_TARGET" "$SSH_PORT" "$CHILD_NODE_ID" 2>/dev/null; then
    log_event --event "collect_completed" --job-id "$CHILD_NODE_ID" --status "appended" --message "artifact collection finished"
  else
    announce "Warning: collection failed for $CHILD_NODE_ID (may be partial)"
  fi

  # Cleanup: release lease but keep cluster alive for reuse
  "$(cleanup_cmd)" --job-id "$CHILD_NODE_ID" --reason "job_complete" >/dev/null 2>&1 || true

  # -----------------------------------------------------------------------
  # PHASE: pipeline next job (dispatch while we analyze current)
  # Claim the next queued job and dispatch it NOW so the cluster is busy
  # during diagnose+reflect instead of sitting idle for ~2-3 minutes.
  # -----------------------------------------------------------------------
  local NEXT_JOB_JSON NEXT_JOB_ID NEXT_CHILD_ID NEXT_BRANCH
  NEXT_JOB_JSON="$(claim_gpu_job "dispatched" "dispatching" 2>/dev/null || echo "")"
  if [ -n "$NEXT_JOB_JSON" ]; then
    NEXT_JOB_ID="$(echo "$NEXT_JOB_JSON" | jq -r '.job_id')"
    NEXT_CHILD_ID="$(echo "$NEXT_JOB_JSON" | jq -r '.child_node_id')"
    NEXT_BRANCH="$(echo "$NEXT_JOB_JSON" | jq -r '.branch_name')"
    local next_job_spec="$MAIN_CHECKOUT/registry/spool/${NEXT_CHILD_ID}_job.json"
    announce "Pipelining next job $NEXT_JOB_ID onto warm cluster..."
    local dispatch_script
    case "$DISPATCH_BACKEND" in
      shadeform) dispatch_script="$MAIN_CHECKOUT/scripts/shadeform_dispatch.sh" ;;
      skypilot)  dispatch_script="$MAIN_CHECKOUT/scripts/skypilot_dispatch.sh" ;;
      *)         dispatch_script="$MAIN_CHECKOUT/scripts/runpod_dispatch.sh" ;;
    esac
    if CONTROLLER_LOG_LABEL="$NEXT_BRANCH" "$dispatch_script" "$next_job_spec"; then
      update_gpu_job_status "$NEXT_JOB_ID" "dispatched"
      announce "Next job $NEXT_JOB_ID dispatched. Cluster busy — analyzing current job now."
    else
      announce "Warning: pipeline dispatch failed for $NEXT_JOB_ID; requeueing."
      update_gpu_job_status "$NEXT_JOB_ID" "dispatched"
    fi
  fi

  # -----------------------------------------------------------------------
  # PHASE: diagnose + reflect (Claude analysis — runs while next job trains)
  # -----------------------------------------------------------------------
  update_gpu_job_status "$JOB_ID" "analyzing"

  local DIAGNOSE_OUTPUT="$PHASE_LOG_DIR/diagnose.output.json"
  local DIAGNOSE_STDERR="$PHASE_LOG_DIR/diagnose.stderr.log"
  local REFLECT_OUTPUT="$PHASE_LOG_DIR/reflect.output.json"
  local REFLECT_STDERR="$PHASE_LOG_DIR/reflect.stderr.log"

  # Build the prompt context (simplified version of build_plan_prompt)
  local LOG_FILE
  LOG_FILE="$(find "$MAIN_CHECKOUT/experiments/$CHILD_NODE_ID" -name '*.log' -type f 2>/dev/null | head -1 || echo "")"

  # Detect crash: no summary JSON means training did not complete successfully
  local SUMMARY_JSON JOB_OUTCOME CRASH_CONTEXT
  SUMMARY_JSON="$(find "$MAIN_CHECKOUT/experiments/$CHILD_NODE_ID" -name '*.json' \
    ! -name 'dirty.patch' -type f 2>/dev/null | head -1 || echo "")"
  if [ -z "$SUMMARY_JSON" ] && [ -n "$LOG_FILE" ]; then
    JOB_OUTCOME="CRASHED (no results JSON produced)"
    CRASH_CONTEXT="$(grep -m 10 -E 'Error|Traceback|RuntimeError|CUDA|OOM|assert|Exception|Signal' \
      "$LOG_FILE" 2>/dev/null | head -15 | cut -c1-200 | tr '\n' '|')"
    CRASH_CONTEXT="Crash excerpt: ${CRASH_CONTEXT:-(log exists but no matching error lines found)}"
  elif [ -z "$SUMMARY_JSON" ]; then
    JOB_OUTCOME="FAILED (no log or results found)"
    CRASH_CONTEXT="No log file found — likely dispatch or bootstrap failure."
  else
    JOB_OUTCOME="completed"
    CRASH_CONTEXT=""
  fi

  local DIAGNOSE_PROMPT="You are analyzing experiment $CHILD_NODE_ID.
Job outcome: $JOB_OUTCOME.
${CRASH_CONTEXT:+$CRASH_CONTEXT
}Log file: ${LOG_FILE:-(none)}.
Read the log file and identify the root cause. If this was a crash, give a precise one-line description of the error (e.g. 'GQA heads mismatch in SDPA fallback — num_kv_heads=4 vs num_heads=8').
Output JSON."

  local REFLECT_PROMPT="You are reflecting on experiment $CHILD_NODE_ID.
Job outcome: $JOB_OUTCOME.
${CRASH_CONTEXT:+$CRASH_CONTEXT
}Review the diagnosis and outcome. Set failure_reason to a precise one-line root cause if is_success=false, empty string otherwise.
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

  # Parse action and failure_reason from reflect output
  local ACTION FAILURE_REASON
  ACTION=$(jq -r '.structured_output.recommended_action // "discard"' "$REFLECT_OUTPUT" 2>/dev/null || echo "discard")
  FAILURE_REASON=$(jq -r '.structured_output.failure_reason // ""' "$REFLECT_OUTPUT" 2>/dev/null || echo "")

  # Update node status (include failure_reason for planners to see)
  python3 - "$MAIN_CHECKOUT/registry/nodes.jsonl" "$MAIN_CHECKOUT/registry/.nodes.lock" "$CHILD_NODE_ID" "$ACTION" "$FAILURE_REASON" <<'PY'
import fcntl
import json
import pathlib
import sys

db_path = pathlib.Path(sys.argv[1])
lock_path = pathlib.Path(sys.argv[2])
node_id = sys.argv[3]
action = sys.argv[4]
failure_reason = sys.argv[5] if len(sys.argv) > 5 else ""

lock_path.touch(exist_ok=True)

with lock_path.open("a+", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    with db_path.open("a", encoding="utf-8") as db_file:
        entry = {"node_id": node_id, "status": action}
        if failure_reason:
            entry["failure_reason"] = failure_reason
        db_file.write(json.dumps(entry) + "\n")
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
