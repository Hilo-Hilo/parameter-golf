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
ALLOW_APT_FALLBACK="${RUNPOD_BOOTSTRAP_ALLOW_APT_FALLBACK:-0}"
FINEWEB_VARIANT="${RUNPOD_FINEWEB_VARIANT:-sp1024}"
FINEWEB_TRAIN_SHARDS="${RUNPOD_FINEWEB_TRAIN_SHARDS:-80}"
DATA_ROOT="$PG_REPO/data"

missing_tools=()
for tool in git jq tmux rsync; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing_tools+=("$tool")
  fi
done

if [ "${#missing_tools[@]}" -gt 0 ]; then
  if [ "$ALLOW_APT_FALLBACK" = "1" ]; then
    apt-get update
    apt-get install -y "${missing_tools[@]}"
  else
    echo "Error: pod template is missing required tools: ${missing_tools[*]}" >&2
    echo "Set RUNPOD_BOOTSTRAP_ALLOW_APT_FALLBACK=1 only for explicit recovery." >&2
    exit 1
  fi
fi

mkdir -p "$WORKSPACE/jobs"
cd "$WORKSPACE"

if [ -d "$PG_REPO" ] && ! git -C "$PG_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Existing $PG_REPO is not a git repository; removing it before clone..."
  rm -rf "$PG_REPO"
fi

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

case "$FINEWEB_VARIANT" in
  sp[0-9]*)
    FINEWEB_DATASET_DIR="$DATA_ROOT/datasets/fineweb10B_${FINEWEB_VARIANT}"
    FINEWEB_TOKENIZER_PATH="$DATA_ROOT/tokenizers/fineweb_${FINEWEB_VARIANT#sp}_bpe.model"
    ;;
  *)
    echo "Error: unsupported RUNPOD_FINEWEB_VARIANT=$FINEWEB_VARIANT for controller bootstrap." >&2
    echo "Use an sp<VOCAB_SIZE> variant or override DATA_PATH/TOKENIZER_PATH explicitly for the run." >&2
    exit 1
    ;;
esac

if [ ! -d "$FINEWEB_DATASET_DIR" ] || [ ! -f "$FINEWEB_TOKENIZER_PATH" ]; then
  echo "Preparing FineWeb cache for $FINEWEB_VARIANT (train_shards=$FINEWEB_TRAIN_SHARDS)..."
  (
    cd "$PG_REPO"
    python3 data/cached_challenge_fineweb.py --variant "$FINEWEB_VARIANT" --train-shards "$FINEWEB_TRAIN_SHARDS"
  )
fi

echo "Bootstrap complete for $JOB_ID at $COMMIT_SHA."
