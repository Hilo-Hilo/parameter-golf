#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <node_id>" >&2
  exit 1
fi

NODE_ID="$1"
REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
MAIN_CHECKOUT="$(cd "$(git -C "$REPO_ROOT" rev-parse --git-common-dir)/.." && pwd)"

export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
export CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1
export CLAUDE_CODE_DISABLE_CRON=1

mkdir -p "$MAIN_CHECKOUT/registry/spool"
STATE_FILE="$MAIN_CHECKOUT/registry/spool/${NODE_ID}_state.json"
NODES_DB="$MAIN_CHECKOUT/registry/nodes.jsonl"
touch "$NODES_DB"

SCRATCH_DIR=$(mktemp -d)
PLAN_WORKTREE="$MAIN_CHECKOUT/worktrees/scratch_$$"

cleanup() {
  rm -rf "$SCRATCH_DIR"
  if [ -d "$PLAN_WORKTREE" ]; then
    git worktree remove -f "$PLAN_WORKTREE" 2>/dev/null || true
    git branch -D "scratch_$$" 2>/dev/null || true
  fi
}
trap cleanup EXIT

mkdir -p "$MAIN_CHECKOUT/worktrees"
git worktree add -B "scratch_$$" "$PLAN_WORKTREE" "tree/$NODE_ID"
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

echo "#!/usr/bin/env bash" > "$SCRATCH_DIR/run_child.sh"
echo "set -euo pipefail" >> "$SCRATCH_DIR/run_child.sh"

jq -r '(.structured_output.experiment_spec.env_keys // {}) | to_entries | .[] | "export \(.key)=\(.value|@sh)"' "$SCRATCH_DIR/phase_plan_output.json" >> "$SCRATCH_DIR/run_child.sh" || true

ARGS_JSON=$(jq -c '.structured_output.experiment_spec.run_command // []' "$SCRATCH_DIR/phase_plan_output.json")
python3 -c "
import sys, json, shlex
try:
    args = json.loads(sys.argv[1])
    print(' '.join(shlex.quote(a) for a in args))
except:
    print('')
" "$ARGS_JSON" > "$SCRATCH_DIR/run_args.txt" || echo "" > "$SCRATCH_DIR/run_args.txt"

RUN_ARGS=$(cat "$SCRATCH_DIR/run_args.txt")
if [ -z "$RUN_ARGS" ]; then
  echo "Error: Plan did not output a valid experiment_spec.run_command array."
  exit 1
fi

NEXT_CMD="$MAIN_CHECKOUT/scripts/run_experiment.sh --name \"$PROPOSED_SLUG\" --track \"autonomous\" -- $RUN_ARGS"
echo "$NEXT_CMD" >> "$SCRATCH_DIR/run_child.sh"
chmod +x "$SCRATCH_DIR/run_child.sh"

# ==============================================================================
# GOVERNANCE: HYBRID NOVELTY CHECK
# ==============================================================================
FINGERPRINT=$(echo -n "${PROPOSED_SLUG}${CHANGED_AXES}${NEXT_CMD}" | shasum -a 256 | awk '{print $1}')

exec 200>"$MAIN_CHECKOUT/registry/.nodes.lock"
flock -x 200

if grep -q "\"fingerprint\":\"$FINGERPRINT\"" "$NODES_DB" 2>/dev/null; then
  echo "Governance Reject: Fingerprint '$FINGERPRINT' already exists in registry."
  flock -u 200
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
  flock -u 200
  exit 1
fi

echo "Governance Check Passed. Creating child node..."

# ==============================================================================
# INFRA & EXECUTION
# ==============================================================================
CHILD_NODE_ID="${NODE_ID}_${PROPOSED_SLUG}"

git checkout -b "approach/$CHILD_NODE_ID"
git add .
if ! git diff --staged --quiet; then
  git commit -m "chore: auto-commit for $CHILD_NODE_ID (plan phase)"
fi

echo "{\"parent\": \"$NODE_ID\", \"node_id\": \"$CHILD_NODE_ID\", \"slug\": \"$PROPOSED_SLUG\", \"fingerprint\": \"$FINGERPRINT\", \"status\": \"running\"}" >> "$NODES_DB"
flock -u 200

# Set up final child worktree
cd "$MAIN_CHECKOUT"
CHILD_WORKTREE_DIR="$MAIN_CHECKOUT/worktrees/$CHILD_NODE_ID"

if [ ! -d "$CHILD_WORKTREE_DIR" ]; then
  git worktree add --lock "$CHILD_WORKTREE_DIR" "approach/$CHILD_NODE_ID"
fi

cd "$CHILD_WORKTREE_DIR"
cp "$SCRATCH_DIR/run_child.sh" .

echo "Executing run command..."
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
exec 200>"$MAIN_CHECKOUT/registry/.nodes.lock"
flock -x 200
ACTION=$(jq -r '.structured_output.recommended_action // "discard"' "$SCRATCH_DIR/phase_reflect_output.json")
echo "{\"parent\": \"$NODE_ID\", \"node_id\": \"$CHILD_NODE_ID\", \"slug\": \"$PROPOSED_SLUG\", \"fingerprint\": \"$FINGERPRINT\", \"status\": \"$ACTION\"}" >> "$NODES_DB"
flock -u 200

echo "Branch cycle complete for $CHILD_NODE_ID. Action determined: $ACTION."

# Cleanup final child worktree as requested
cd "$MAIN_CHECKOUT"
git worktree unlock "$CHILD_WORKTREE_DIR" || true
git worktree remove -f "$CHILD_WORKTREE_DIR" || true
