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

STATE_FILE="$WORKTREE_DIR/registry/spool/${NODE_ID}_state.json"
mkdir -p "$(dirname "$STATE_FILE")"

for phase in plan diagnose reflect; do
  PROMPT_FILE="$REPO_ROOT/prompts/${phase}.md"
  
  if [ ! -f "$PROMPT_FILE" ]; then
    PROMPT_FILE="$REPO_ROOT/worker_program.md"
  fi

  echo "=== Phase: $phase ==="
  
  PROMPT="$(cat "$PROMPT_FILE")
  
Current Phase: $phase
Please output your response matching the JSON schema for this phase, passing context cleanly.
Previous state if any:
$(cat "$STATE_FILE" 2>/dev/null || echo "{}")"

  # Capture output to pass context to the next phase
  claude -p "$PROMPT" --no-session-persistence > "phase_${phase}_output.json" || true
  
  cp "phase_${phase}_output.json" "$STATE_FILE"
done
