#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/Hilo-Hilo/parameter-golf"
WORKSPACE="/workspace"
PG_REPO="$WORKSPACE/pgrepo"

echo "Bootstrapping remote environment in $WORKSPACE..."

# Ensure tools
if ! command -v jq &> /dev/null || ! command -v tmux &> /dev/null || ! command -v rsync &> /dev/null; then
  apt-get update && apt-get install -y jq tmux rsync
fi

mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

if [ ! -d "$PG_REPO" ]; then
  echo "Cloning repository..."
  git clone "$REPO_URL" "$PG_REPO"
else
  echo "Repository exists. Fetching latest..."
  cd "$PG_REPO"
  git fetch --all --prune
fi

# Ensure data path exists
mkdir -p "$WORKSPACE/data"

echo "Bootstrap complete."
