#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <node_id>" >&2
  exit 1
fi

NODE_ID="$1"
REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
MAIN_CHECKOUT="$(cd "$(git -C "$REPO_ROOT" rev-parse --git-common-dir)/.." && pwd)"
SAFE_NODE_ID="$(printf '%s' "$NODE_ID" | tr -cs 'A-Za-z0-9._-' '_')"

export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
export CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1
export CLAUDE_CODE_DISABLE_CRON=1

mkdir -p "$MAIN_CHECKOUT/registry/spool"
STATE_FILE="$MAIN_CHECKOUT/registry/spool/${NODE_ID}_state.json"
NODES_DB="$MAIN_CHECKOUT/registry/nodes.jsonl"
NODES_LOCK_FILE="$MAIN_CHECKOUT/registry/.nodes.lock"
NODE_LOCK_ROOT="$MAIN_CHECKOUT/registry/node_locks"
NODE_LOCK_DIR="$NODE_LOCK_ROOT/$SAFE_NODE_ID"
touch "$NODES_DB"

SCRATCH_DIR=$(mktemp -d)
SCRATCH_REF="scratch_${SAFE_NODE_ID}_$$"
PLAN_WORKTREE="$MAIN_CHECKOUT/worktrees/$SCRATCH_REF"
JOB_DISPATCHED=0
POD_CLEANED=0
CHILD_NODE_ID=""

acquire_node_lock() {
  mkdir -p "$NODE_LOCK_ROOT"

  while true; do
    if mkdir "$NODE_LOCK_DIR" 2>/dev/null; then
      printf '%s\n' "$$" > "$NODE_LOCK_DIR/pid"
      return
    fi

    if [ -f "$NODE_LOCK_DIR/pid" ]; then
      owner_pid="$(cat "$NODE_LOCK_DIR/pid" 2>/dev/null || echo "")"
      if [ -n "$owner_pid" ] && ! kill -0 "$owner_pid" 2>/dev/null; then
        rm -rf "$NODE_LOCK_DIR"
        continue
      fi
    fi

    echo "Error: node $NODE_ID is already being processed." >&2
    exit 1
  done
}

release_node_lock() {
  rm -rf "$NODE_LOCK_DIR" 2>/dev/null || true
}

cleanup() {
  local rc=$?
  trap - EXIT INT TERM

  if [ "$JOB_DISPATCHED" -eq 1 ] && [ "$POD_CLEANED" -eq 0 ] && [ -n "$CHILD_NODE_ID" ]; then
    cd "$MAIN_CHECKOUT"
    scripts/runpod_cleanup.sh --job-id "$CHILD_NODE_ID" --reason "controller_exit" >/dev/null 2>&1 || true
  fi

  release_node_lock
  rm -rf "$SCRATCH_DIR"
  if [ -d "$PLAN_WORKTREE" ]; then
    git worktree remove -f "$PLAN_WORKTREE" 2>/dev/null || true
    git branch -D "$SCRATCH_REF" 2>/dev/null || true
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

controller_ttl_epoch() {
  local lease_file="$1"

  python3 - "$lease_file" <<'PY'
from datetime import datetime, timezone
import json
import pathlib
import sys

lease_path = pathlib.Path(sys.argv[1])
if not lease_path.exists():
    print("0")
    raise SystemExit(0)

try:
    payload = json.loads(lease_path.read_text(encoding="utf-8"))
except json.JSONDecodeError:
    print("0")
    raise SystemExit(0)

lease_expires_at = payload.get("lease_expires_at")
if not lease_expires_at:
    print("0")
    raise SystemExit(0)

deadline = datetime.strptime(lease_expires_at, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
print(int(deadline.timestamp()))
PY
}

fingerprint_exists() {
  local fingerprint="$1"

  python3 - "$NODES_DB" "$fingerprint" <<'PY'
import json
import pathlib
import sys

db_path = pathlib.Path(sys.argv[1])
fingerprint = sys.argv[2]
exists = False

if db_path.exists():
    for raw_line in db_path.read_text(encoding="utf-8").splitlines():
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        try:
            row = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        if row.get("fingerprint") == fingerprint:
            exists = True
            break

print("true" if exists else "false")
PY
}

append_node_record() {
  local status="$1"
  local enforce_unique="${2:-0}"

  python3 - "$NODES_DB" "$NODES_LOCK_FILE" "$NODE_ID" "$CHILD_NODE_ID" "$PROPOSED_SLUG" "$FINGERPRINT" "$status" "$enforce_unique" <<'PY'
import fcntl
import json
import pathlib
import sys

db_path = pathlib.Path(sys.argv[1])
lock_path = pathlib.Path(sys.argv[2])
parent_node = sys.argv[3]
node_id = sys.argv[4]
slug = sys.argv[5]
fingerprint = sys.argv[6]
status = sys.argv[7]
enforce_unique = sys.argv[8] == "1"

lock_path.parent.mkdir(parents=True, exist_ok=True)
db_path.parent.mkdir(parents=True, exist_ok=True)

with lock_path.open("a+", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

    if enforce_unique and db_path.exists():
        for raw_line in db_path.read_text(encoding="utf-8").splitlines():
            raw_line = raw_line.strip()
            if not raw_line:
                continue
            try:
                row = json.loads(raw_line)
            except json.JSONDecodeError:
                continue
            if row.get("fingerprint") == fingerprint:
                raise SystemExit(3)

    record = {
        "parent": parent_node,
        "node_id": node_id,
        "slug": slug,
        "fingerprint": fingerprint,
        "status": status,
    }
    with db_path.open("a", encoding="utf-8") as db_file:
        db_file.write(json.dumps(record))
        db_file.write("\n")

    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
PY
}

resolve_diagnose_log() {
  local results_dir="$1"

  python3 - "$results_dir" <<'PY'
import pathlib
import sys

results_dir = pathlib.Path(sys.argv[1])
log_candidates = list(results_dir.glob("*.log"))

if log_candidates:
    newest = max(log_candidates, key=lambda path: path.stat().st_mtime)
    print(str(newest))
else:
    print(str(results_dir / "wrapper" / "run.log"))
PY
}

acquire_node_lock
cd "$MAIN_CHECKOUT"
scripts/runpod_reconcile.sh >/dev/null 2>&1 || true

mkdir -p "$MAIN_CHECKOUT/worktrees"
git worktree add -B "$SCRATCH_REF" "$PLAN_WORKTREE" "tree/$NODE_ID"
cd "$PLAN_WORKTREE"

# ==============================================================================
# PHASE 1: PLAN
# ==============================================================================
echo "=== Phase: plan ==="
PROMPT_FILE="$MAIN_CHECKOUT/worker_program.md"

PROMPT="$(cat "$PROMPT_FILE")
Current Phase: plan
Please analyze history, make local file edits for your new approach, and then output your JSON proposal.
Previous state if any: $(cat "$STATE_FILE" 2>/dev/null || echo "{}")"

claude -p "$PROMPT" \
  --model claude-3-7-sonnet-20250219 \
  --max-turns 15 \
  --max-budget-usd 1.00 \
  --bare \
  --tools "Read,Edit,Glob,Grep" \
  --settings "$MAIN_CHECKOUT/.claude/settings.json" \
  --mcp-config "$MAIN_CHECKOUT/.mcp.json" \
  --strict-mcp-config \
  --no-session-persistence \
  --output-format json \
  --json-schema "$MAIN_CHECKOUT/schemas/plan_schema.json" \
  > "$SCRATCH_DIR/phase_plan_output.json" || true

cp "$SCRATCH_DIR/phase_plan_output.json" "$STATE_FILE"

PROPOSED_SLUG=$(jq -r '.structured_output.proposed_slug // empty' "$SCRATCH_DIR/phase_plan_output.json")
CHANGED_AXES=$(jq -r '.structured_output.changed_axes // empty' "$SCRATCH_DIR/phase_plan_output.json")

if [ -z "$PROPOSED_SLUG" ] || [ "$PROPOSED_SLUG" == "null" ]; then
  echo "Error: Plan did not output valid proposed_slug."
  exit 1
fi

echo "Proposed slug: $PROPOSED_SLUG"

if ! git check-ref-format "refs/heads/$PROPOSED_SLUG"; then
  echo "Governance Reject: Invalid branch name '$PROPOSED_SLUG'"
  exit 1
fi

# ==============================================================================
# GOVERNANCE: HYBRID NOVELTY CHECK
# ==============================================================================
# The run command array is parsed into a single string for fingerprinting
ARGS_JSON=$(jq -c '.structured_output.run_argv // []' "$SCRATCH_DIR/phase_plan_output.json")
NEXT_CMD=$(python3 -c "
import sys, json, shlex
try:
    args = json.loads(sys.argv[1])
    print(' '.join(shlex.quote(a) for a in args))
except:
    print('')
" "$ARGS_JSON" || echo "")

FINGERPRINT=$(echo -n "${PROPOSED_SLUG}${CHANGED_AXES}${NEXT_CMD}" | shasum -a 256 | awk '{print $1}')

if [ "$(fingerprint_exists "$FINGERPRINT")" = "true" ]; then
  echo "Governance Reject: Fingerprint '$FINGERPRINT' already exists in registry."
  exit 1
fi

echo "Running Governance LLM Check..."
GOV_PROMPT="You are the Governance Agent. A worker has proposed a new approach:
Slug: $PROPOSED_SLUG
Axes changed: $CHANGED_AXES
Command: $NEXT_CMD

Here is the registry of past runs:
$(tail -n 50 "$NODES_DB" 2>/dev/null || true)

Is this proposed approach a semantic duplicate of a past run? Return JSON."

claude -p "$GOV_PROMPT" \
  --model claude-3-7-sonnet-20250219 \
  --max-turns 3 \
  --max-budget-usd 0.20 \
  --bare \
  --tools "Read,Edit,Glob,Grep" \
  --settings "$MAIN_CHECKOUT/.claude/settings.json" \
  --mcp-config "$MAIN_CHECKOUT/.mcp.json" \
  --strict-mcp-config \
  --no-session-persistence \
  --output-format json \
  --json-schema "$MAIN_CHECKOUT/schemas/governance_schema.json" \
  > "$SCRATCH_DIR/gov_output.json" || true

IS_DUPLICATE=$(jq -r '.structured_output.is_duplicate // "false"' "$SCRATCH_DIR/gov_output.json")
if [ "$IS_DUPLICATE" == "true" ]; then
  REASON=$(jq -r '.structured_output.reason // "No reason provided"' "$SCRATCH_DIR/gov_output.json")
  echo "Governance Reject: Semantic duplicate detected. Reason: $REASON"
  exit 1
fi

echo "Governance Check Passed. Creating child node..."

# ==============================================================================
# INFRA & EXECUTION: BRANCH, PUSH, JOB DISPATCH
# ==============================================================================
CHILD_NODE_ID="${NODE_ID}_${PROPOSED_SLUG}"
BRANCH_NAME="approach/$CHILD_NODE_ID"

git checkout -b "$BRANCH_NAME"
git add .
if ! git diff --staged --quiet; then
  git commit -m "chore: auto-commit for $CHILD_NODE_ID (plan phase)"
fi

# Push the branch to origin
echo "Pushing branch $BRANCH_NAME to origin..."
git push origin "$BRANCH_NAME"

COMMIT_SHA=$(git rev-parse HEAD)

# Write to NODES_DB
if ! append_node_record "running" "1"; then
  rc=$?
  if [ "$rc" -eq 3 ]; then
    echo "Governance Reject: Fingerprint '$FINGERPRINT' already exists in registry."
    exit 1
  fi
  exit "$rc"
fi

# Create Job Spec JSON
JOB_SPEC="$MAIN_CHECKOUT/registry/spool/${CHILD_NODE_ID}_job.json"
jq --arg branch "$BRANCH_NAME" \
   --arg commit "$COMMIT_SHA" \
   --arg job_id "$CHILD_NODE_ID" \
   '.structured_output + {branch: $branch, commit_sha: $commit, job_id: $job_id}' \
   "$SCRATCH_DIR/phase_plan_output.json" > "$JOB_SPEC"

echo "Dispatching job to RunPod..."
cd "$MAIN_CHECKOUT"
scripts/runpod_dispatch.sh "$JOB_SPEC"
JOB_DISPATCHED=1

SSH_TARGET=$(cat "registry/spool/${CHILD_NODE_ID}_ssh_target.txt" || echo "")
SSH_PORT=$(cat "registry/spool/${CHILD_NODE_ID}_ssh_port.txt" || echo "22")
if [ -z "$SSH_TARGET" ]; then
  echo "Error: SSH target not saved by dispatch."
  exit 1
fi

LEASE_FILE="$MAIN_CHECKOUT/registry/spool/${CHILD_NODE_ID}_lease.json"
CONTROLLER_TTL_EPOCH="$(controller_ttl_epoch "$LEASE_FILE")"

echo "Waiting for remote job to complete on $SSH_TARGET:$SSH_PORT..."
while true; do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_TARGET" "tmux has-session -t job_${CHILD_NODE_ID} 2>/dev/null" >/dev/null 2>&1; then
    :
  elif ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_TARGET" "true" >/dev/null 2>&1; then
    echo "Tmux session ended. Job complete."
    break
  else
    echo "Remote SSH check failed for $CHILD_NODE_ID; retrying."
  fi

  if [ "$CONTROLLER_TTL_EPOCH" -gt 0 ] && [ "$(date -u +%s)" -ge "$CONTROLLER_TTL_EPOCH" ]; then
    echo "Controller TTL exceeded for $CHILD_NODE_ID. Triggering failure cleanup."
    if scripts/runpod_cleanup.sh --job-id "$CHILD_NODE_ID" --reason "controller_ttl_exceeded" >/dev/null 2>&1; then
      POD_CLEANED=1
    fi
    exit 1
  fi

  sleep 60
done

echo "Collecting artifacts from remote..."
if ! scripts/runpod_collect.sh "$SSH_TARGET" "$SSH_PORT" "$CHILD_NODE_ID"; then
  if scripts/runpod_cleanup.sh --job-id "$CHILD_NODE_ID" --reason "collect_failed" >/dev/null 2>&1; then
    POD_CLEANED=1
  fi
  exit 1
fi

scripts/runpod_cleanup.sh --job-id "$CHILD_NODE_ID" --reason "job_complete"
POD_CLEANED=1

# Clean up final child worktree if we created one, but we don't need local worktree for execution anymore
# The plan worktree is cleaned up by the trap.

# ==============================================================================
# PHASE 2: DIAGNOSE
# ==============================================================================
echo "=== Phase: diagnose ==="
LOG_FILE="$(resolve_diagnose_log "$MAIN_CHECKOUT/experiments/$CHILD_NODE_ID")"

PROMPT="$(cat "$PROMPT_FILE")
Current Phase: diagnose
The remote experiment has finished. Logs are at $LOG_FILE.
Please analyze the logs and summarize any issues.
Output JSON."

cd "$PLAN_WORKTREE"
claude -p "$PROMPT" \
  --model claude-3-7-sonnet-20250219 \
  --max-turns 10 \
  --max-budget-usd 1.00 \
  --bare \
  --tools "Read,Edit,Glob,Grep" \
  --settings "$MAIN_CHECKOUT/.claude/settings.json" \
  --mcp-config "$MAIN_CHECKOUT/.mcp.json" \
  --strict-mcp-config \
  --no-session-persistence \
  --output-format json \
  --json-schema "$MAIN_CHECKOUT/schemas/diagnose_schema.json" \
  > "$SCRATCH_DIR/phase_diagnose_output.json" || true

# ==============================================================================
# PHASE 3: REFLECT
# ==============================================================================
echo "=== Phase: reflect ==="
PROMPT="$(cat "$PROMPT_FILE")
Current Phase: reflect
Review the diagnosis and outcome. Determine if this was a success and what to do next.
Output JSON."

claude -p "$PROMPT" \
  --model claude-3-7-sonnet-20250219 \
  --max-turns 5 \
  --max-budget-usd 0.50 \
  --bare \
  --tools "Read,Edit,Glob,Grep" \
  --settings "$MAIN_CHECKOUT/.claude/settings.json" \
  --mcp-config "$MAIN_CHECKOUT/.mcp.json" \
  --strict-mcp-config \
  --no-session-persistence \
  --output-format json \
  --json-schema "$MAIN_CHECKOUT/schemas/reflect_schema.json" \
  > "$SCRATCH_DIR/phase_reflect_output.json" || true

# Update node status based on reflection
ACTION=$(jq -r '.structured_output.recommended_action // "discard"' "$SCRATCH_DIR/phase_reflect_output.json")
append_node_record "$ACTION" "0"

echo "Branch cycle complete for $CHILD_NODE_ID. Action determined: $ACTION."
cd "$MAIN_CHECKOUT"
