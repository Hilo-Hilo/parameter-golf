#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <job_id> <branch> <commit_sha>" >&2
  exit 1
fi

JOB_ID="$1"
BRANCH="$2"
COMMIT_SHA="$3"

WORKSPACE="/workspace"
PG_REPO="$WORKSPACE/pgrepo"
JOB_DIR="$WORKSPACE/jobs/$JOB_ID"

mkdir -p "$WORKSPACE/jobs"

cd "$PG_REPO"
git fetch origin "$BRANCH"

echo "Creating worktree for $JOB_ID at $JOB_DIR..."
git worktree add -f "$JOB_DIR" "$COMMIT_SHA"

cat <<EOF > "$JOB_DIR/pod_state.json"
{
  "job_id": "$JOB_ID",
  "branch": "$BRANCH",
  "commit_sha": "$COMMIT_SHA",
  "status": "prepared",
  "prepared_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo "Worktree prepared."
