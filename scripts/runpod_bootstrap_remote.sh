#!/usr/bin/env bash
set -euo pipefail

# scripts/runpod_bootstrap_remote.sh
# Runs ON the pod to bootstrap the worktree at an exact commit SHA.

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <job_id> <branch> <commit_sha>" >&2
  exit 1
fi

JOB_ID="$1"
BRANCH="$2"
COMMIT_SHA="$3"

WORKSPACE="/workspace"
PG_REPO="$WORKSPACE/parameter-golf"
JOB_DIR="$WORKSPACE/jobs/$JOB_ID"
REPO_URL="${RUNPOD_REPO_URL:-https://github.com/Hilo-Hilo/parameter-golf.git}"

# Ensure essential tools
if ! command -v jq >/dev/null || ! command -v tmux >/dev/null || ! command -v rsync >/dev/null; then
  apt-get update && apt-get install -y jq tmux rsync
fi

mkdir -p "$WORKSPACE/jobs"
cd "$WORKSPACE"

if [ ! -d "$PG_REPO" ]; then
  echo "Cloning repository..."
  git clone "$REPO_URL" "$PG_REPO"
fi

cd "$PG_REPO"
git remote set-url origin "$REPO_URL"
echo "Fetching origin..."
git fetch origin --prune

echo "Creating detached worktree for $JOB_ID..."
if [ -d "$JOB_DIR" ]; then
  git worktree remove -f "$JOB_DIR" 2>/dev/null || rm -rf "$JOB_DIR"
fi
git worktree add --detach -f "$JOB_DIR" "$COMMIT_SHA"

cd "$JOB_DIR"
ACTUAL_SHA=$(git rev-parse HEAD)
if [ "$ACTUAL_SHA" != "$COMMIT_SHA" ]; then
  echo "Error: Worktree SHA ($ACTUAL_SHA) does not match requested ($COMMIT_SHA)" >&2
  exit 1
fi

# Ensure data path exists for potential datasets
mkdir -p "$WORKSPACE/data"

echo "Bootstrap complete for $JOB_ID at $COMMIT_SHA."
