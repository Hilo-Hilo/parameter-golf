#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <branch_name> <job_id> <profile>" >&2
  exit 1
fi

BRANCH_NAME="$1"
JOB_ID="$2"
PROFILE="$3"

REPO_ROOT="$(git rev-parse --show-toplevel)"
MAIN_CHECKOUT="$(cd "$(git -C "$REPO_ROOT" rev-parse --git-common-dir)/.." && pwd)"
QUEUE_DIR="$MAIN_CHECKOUT/registry/queue"
mkdir -p "$QUEUE_DIR"

echo "Committing and pushing branch $BRANCH_NAME..."
git -C "$REPO_ROOT" add .
if ! git -C "$REPO_ROOT" diff --staged --quiet; then
  git -C "$REPO_ROOT" commit -m "chore: auto-commit for job $JOB_ID"
fi

git -C "$REPO_ROOT" push -u origin "$BRANCH_NAME" --force

COMMIT_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD)

JOB_SPEC="$QUEUE_DIR/${JOB_ID}.json"

cat <<EOF > "$JOB_SPEC"
{
  "job_id": "$JOB_ID",
  "branch": "$BRANCH_NAME",
  "commit_sha": "$COMMIT_SHA",
  "resource_profile": "$PROFILE",
  "status": "queued",
  "queued_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo "Job spec written to $JOB_SPEC"
