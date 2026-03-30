#!/usr/bin/env bash
# scripts/swarm_guardian.sh
# Guardian: restarts pg-swarm and pg-monitor tmux sessions if they have died.
# Safe to run at any time; no-ops if everything is healthy.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"

SWARM_SESSION="pg-swarm"
MONITOR_SESSION="pg-monitor"
SWARM_CMD="DISPATCH_BACKEND=shadeform scripts/start_swarm.sh --pipeline --workers 3 --watchers 1 2>&1 | tee logs/swarm.log"
MONITOR_CMD="while true; do clear; bash scripts/swarm_monitor.sh; sleep 60; done"
LOG="$REPO_ROOT/logs/guardian.log"

mkdir -p "$REPO_ROOT/logs"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { printf '[%s][guardian] %s\n' "$(ts)" "$*"; }

# Check if a tmux session has a live foreground process (not just a shell prompt).
session_alive() {
  local session="$1" keyword="$2"
  tmux list-panes -t "$session" -F "#{pane_pid}" 2>/dev/null | while read -r ppid; do
    if pgrep -P "$ppid" -f "$keyword" >/dev/null 2>&1; then
      echo "alive"
      return
    fi
  done
}

# --- Guard pg-swarm ---
if ! tmux has-session -t "$SWARM_SESSION" 2>/dev/null; then
  log "Session $SWARM_SESSION missing. Creating and launching swarm..."
  tmux new-session -d -s "$SWARM_SESSION" -x 220 -y 50
  tmux send-keys -t "$SWARM_SESSION" "cd '$REPO_ROOT' && $SWARM_CMD" Enter
  log "Swarm relaunched in $SWARM_SESSION."
else
  alive="$(session_alive "$SWARM_SESSION" "start_swarm")"
  if [ -z "$alive" ]; then
    log "Session $SWARM_SESSION exists but start_swarm is dead. Relaunching..."
    tmux send-keys -t "$SWARM_SESSION" "" ""  # clear any partial input
    tmux send-keys -t "$SWARM_SESSION" "cd '$REPO_ROOT' && $SWARM_CMD" Enter
    log "Swarm relaunched in existing $SWARM_SESSION."
  else
    log "Swarm healthy ($SWARM_SESSION)."
  fi
fi

# --- Guard pg-monitor ---
if ! tmux has-session -t "$MONITOR_SESSION" 2>/dev/null; then
  log "Session $MONITOR_SESSION missing. Creating and launching monitor..."
  tmux new-session -d -s "$MONITOR_SESSION" -x 220 -y 50
  tmux send-keys -t "$MONITOR_SESSION" "cd '$REPO_ROOT' && $MONITOR_CMD" Enter
  log "Monitor relaunched in $MONITOR_SESSION."
else
  alive="$(session_alive "$MONITOR_SESSION" "swarm_monitor")"
  # Also treat the inter-run sleep phase as alive
  [ -z "$alive" ] && alive="$(session_alive "$MONITOR_SESSION" "sleep")"
  if [ -z "$alive" ]; then
    log "Session $MONITOR_SESSION exists but monitor loop is dead. Relaunching..."
    tmux send-keys -t "$MONITOR_SESSION" "" ""
    tmux send-keys -t "$MONITOR_SESSION" "cd '$REPO_ROOT' && $MONITOR_CMD" Enter
    log "Monitor relaunched in existing $MONITOR_SESSION."
  else
    log "Monitor healthy ($MONITOR_SESSION)."
  fi
fi
