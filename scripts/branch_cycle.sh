#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <node_id>" >&2
  exit 1
fi

NODE_ID="$1"
REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
WORKTREE_DIR="$REPO_ROOT/worktrees/$NODE_ID"

if [ ! -d "$WORKTREE_DIR" ]; then
  echo "Creating worktree for $NODE_ID..."
  mkdir -p "$REPO_ROOT/worktrees"
  git worktree add -B "tree/$NODE_ID" "$WORKTREE_DIR" HEAD 2>/dev/null || git worktree add "$WORKTREE_DIR" "tree/$NODE_ID"
fi

cd "$WORKTREE_DIR"

export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
export CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1
export CLAUDE_CODE_DISABLE_CRON=1

mkdir -p "$REPO_ROOT/registry/spool"
STATE_FILE="$REPO_ROOT/registry/spool/${NODE_ID}_state.json"

# ==============================================================================
# PHASE 1: PLAN (Propose changes, generate run command)
# ==============================================================================
echo "=== Phase: plan ==="
PROMPT_FILE="$REPO_ROOT/worker_program.md"

PROMPT="$(cat "$PROMPT_FILE")
Current Phase: plan
Please analyze history, make local file edits for your new approach, and then output your JSON proposal.
Previous state if any: $(cat "$STATE_FILE" 2>/dev/null || echo "{}")"

claude -p "$PROMPT" \
  --bare \
  --settings "$REPO_ROOT/.claude/settings.json" \
  --mcp-config "$REPO_ROOT/.mcp.json" \
  --strict-mcp-config \
  --no-session-persistence \
  --output-format json \
  --json-schema "$REPO_ROOT/schemas/plan_schema.json" \
  --allowedTools "Read,Edit,Glob,Grep" > phase_plan_output.json || true

cp phase_plan_output.json "$STATE_FILE"

# Parse JSON
PROPOSED_SLUG=$(jq -r '.structured_output.proposed_slug // empty' phase_plan_output.json)
NEXT_CMD=$(jq -r '.structured_output.next_run_command // empty' phase_plan_output.json)
CHANGED_AXES=$(jq -r '.structured_output.changed_axes // empty' phase_plan_output.json)

if [ -z "$PROPOSED_SLUG" ] || [ -z "$NEXT_CMD" ]; then
  echo "Error: Plan did not output valid proposed_slug or next_run_command."
  exit 1
fi

echo "Proposed slug: $PROPOSED_SLUG"
echo "Next command: $NEXT_CMD"

# Ref-format check
if ! git check-ref-format "refs/heads/$PROPOSED_SLUG"; then
  echo "Governance Reject: Invalid branch name '$PROPOSED_SLUG'"
  exit 1
fi

# ==============================================================================
# GOVERNANCE: HYBRID NOVELTY CHECK
# ==============================================================================
NODES_DB="$REPO_ROOT/registry/nodes.jsonl"
touch "$NODES_DB"

# 1. Deterministic Fast Check
FINGERPRINT=$(echo -n "${PROPOSED_SLUG}${CHANGED_AXES}${NEXT_CMD}" | shasum -a 256 | awk '{print $1}')
if grep -q "\"fingerprint\":\"$FINGERPRINT\"" "$NODES_DB" 2>/dev/null; then
  echo "Governance Reject: Fingerprint '$FINGERPRINT' already exists in registry."
  exit 1
fi

# 2. Semantic LLM Judge Check
echo "Running Governance LLM Check..."
GOV_PROMPT="You are the Governance Agent. A worker has proposed a new approach:
Slug: $PROPOSED_SLUG
Axes changed: $CHANGED_AXES
Command: $NEXT_CMD

Here is the registry of past runs:
$(tail -n 50 "$NODES_DB" 2>/dev/null || true)

Is this proposed approach a semantic duplicate of a past run? Return JSON."

claude -p "$GOV_PROMPT" \
  --bare \
  --settings "$REPO_ROOT/.claude/settings.json" \
  --mcp-config "$REPO_ROOT/.mcp.json" \
  --strict-mcp-config \
  --no-session-persistence \
  --output-format json \
  --json-schema "$REPO_ROOT/schemas/governance_schema.json" > gov_output.json || true

IS_DUPLICATE=$(jq -r '.structured_output.is_duplicate // "false"' gov_output.json)
if [ "$IS_DUPLICATE" == "true" ]; then
  REASON=$(jq -r '.structured_output.reason // "No reason provided"' gov_output.json)
  echo "Governance Reject: Semantic duplicate detected. Reason: $REASON"
  exit 1
fi

echo "Governance Check Passed. Creating child node..."

# ==============================================================================
# INFRA & EXECUTION
# ==============================================================================
CHILD_NODE_ID="${NODE_ID}_${PROPOSED_SLUG}"

# The shell controller commits the changes that Claude made and creates the branch
git checkout -b "approach/$CHILD_NODE_ID" || git checkout "approach/$CHILD_NODE_ID"
git add .
if ! git diff --staged --quiet; then
  git commit -m "chore: auto-commit for $CHILD_NODE_ID (plan phase)"
else
  echo "No changes to commit for $CHILD_NODE_ID."
fi

# Restore parent worktree branch
git checkout "tree/$NODE_ID"

echo "{\"parent\": \"$NODE_ID\", \"node_id\": \"$CHILD_NODE_ID\", \"slug\": \"$PROPOSED_SLUG\", \"fingerprint\": \"$FINGERPRINT\", \"status\": \"running\"}" >> "$NODES_DB"

# Create a new isolated worktree for child
CHILD_WORKTREE_DIR="$REPO_ROOT/worktrees/$CHILD_NODE_ID"
if [ ! -d "$CHILD_WORKTREE_DIR" ]; then
  mkdir -p "$REPO_ROOT/worktrees"
  git worktree add "$CHILD_WORKTREE_DIR" "approach/$CHILD_NODE_ID"
fi

cd "$CHILD_WORKTREE_DIR"

echo "Executing run command..."
echo "$NEXT_CMD" > run_child.sh
chmod +x run_child.sh
./run_child.sh

# ==============================================================================
# PHASE 2: DIAGNOSE
# ==============================================================================
echo "=== Phase: diagnose ==="
PROMPT="$(cat "$PROMPT_FILE")
Current Phase: diagnose
The experiment has finished. Please analyze the logs and summarize any issues.
Output JSON."

claude -p "$PROMPT" \
  --bare \
  --settings "$REPO_ROOT/.claude/settings.json" \
  --mcp-config "$REPO_ROOT/.mcp.json" \
  --strict-mcp-config \
  --no-session-persistence \
  --output-format json \
  --json-schema "$REPO_ROOT/schemas/diagnose_schema.json" \
  --allowedTools "Read,Edit,Glob,Grep" > phase_diagnose_output.json || true

# ==============================================================================
# PHASE 3: REFLECT
# ==============================================================================
echo "=== Phase: reflect ==="
PROMPT="$(cat "$PROMPT_FILE")
Current Phase: reflect
Review the diagnosis and outcome. Determine if this was a success and what to do next.
Output JSON."

claude -p "$PROMPT" \
  --bare \
  --settings "$REPO_ROOT/.claude/settings.json" \
  --mcp-config "$REPO_ROOT/.mcp.json" \
  --strict-mcp-config \
  --no-session-persistence \
  --output-format json \
  --json-schema "$REPO_ROOT/schemas/reflect_schema.json" \
  --allowedTools "Read,Edit,Glob,Grep" > phase_reflect_output.json || true

# Update node status based on reflection
ACTION=$(jq -r '.structured_output.recommended_action // "discard"' phase_reflect_output.json)
echo "{\"parent\": \"$NODE_ID\", \"node_id\": \"$CHILD_NODE_ID\", \"slug\": \"$PROPOSED_SLUG\", \"fingerprint\": \"$FINGERPRINT\", \"status\": \"$ACTION\"}" >> "$NODES_DB"

echo "Branch cycle complete for $CHILD_NODE_ID. Action determined: $ACTION."