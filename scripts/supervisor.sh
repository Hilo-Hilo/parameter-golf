#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
NODES_DB="$REPO_ROOT/registry/nodes.jsonl"
LOCK_FILE="$REPO_ROOT/registry/.supervisor.lock"

mkdir -p "$REPO_ROOT/registry"
touch "$NODES_DB"

# Ensure only one supervisor runs at a time
(
  flock -n 200 || { echo "Supervisor already running."; exit 0; }
  
  echo "Checking for pending nodes..."
  
  # Find the first pending node
  # We read line by line since it's JSONL
  PENDING_NODE=""
  if [ -s "$NODES_DB" ]; then
    PENDING_NODE=$(jq -c 'select(.status == "pending")' "$NODES_DB" | head -n 1 | jq -r '.node_id // empty')
  fi
  
  if [ -n "$PENDING_NODE" ]; then
    echo "Found pending node: $PENDING_NODE. Starting branch cycle..."
    
    # Mark it as running
    tmp=$(mktemp)
    jq -c "if .node_id == \"$PENDING_NODE\" then .status = \"running\" else . end" "$NODES_DB" > "$tmp"
    mv "$tmp" "$NODES_DB"
    
    # Run the cycle
    "$REPO_ROOT/scripts/branch_cycle.sh" "$PENDING_NODE"
  else
    echo "No pending nodes found."
  fi

) 200>"$LOCK_FILE"