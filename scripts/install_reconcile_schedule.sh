#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"

usage() {
  cat <<'EOF'
Usage:
  scripts/install_reconcile_schedule.sh [options]

Options:
  --mode launchd|cron      Scheduler backend to install. Default: launchd on macOS, cron elsewhere.
  --interval-minutes N     Reconcile interval in minutes. Default: 5.
  --label LABEL            Scheduler label/comment. Default: com.parameter-golf.runpod-reconcile
  --log-file PATH          Log file path. Default: <repo>/logs/reconcile.log
  --dry-run                Print the generated schedule instead of installing it.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: missing required command: $1" >&2
    exit 1
  fi
}

mode=""
interval_minutes=5
label="com.parameter-golf.runpod-reconcile"
log_file="$REPO_ROOT/logs/reconcile.log"
dry_run=0
launchd_path="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      mode="${2:-}"
      shift 2
      ;;
    --interval-minutes)
      interval_minutes="${2:-}"
      shift 2
      ;;
    --label)
      label="${2:-}"
      shift 2
      ;;
    --log-file)
      log_file="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$mode" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    mode="launchd"
  else
    mode="cron"
  fi
fi

if ! [[ "$interval_minutes" =~ ^[0-9]+$ ]] || [[ "$interval_minutes" -lt 1 ]]; then
  echo "Error: --interval-minutes must be a positive integer" >&2
  exit 2
fi

mkdir -p "$(dirname "$log_file")"
reconcile_cmd="$REPO_ROOT/scripts/runpod_reconcile.sh"

install_launchd() {
  local plist_path="$HOME/Library/LaunchAgents/${label}.plist"
  local start_interval=$((interval_minutes * 60))
  local tmp_file
  tmp_file="$(mktemp)"

  cat >"$tmp_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${reconcile_cmd}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${REPO_ROOT}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${launchd_path}</string>
  </dict>
  <key>StartInterval</key>
  <integer>${start_interval}</integer>
  <key>StandardOutPath</key>
  <string>${log_file}</string>
  <key>StandardErrorPath</key>
  <string>${log_file}</string>
</dict>
</plist>
EOF

  if [[ "$dry_run" -eq 1 ]]; then
    echo "Would install launchd agent at $plist_path:"
    sed -n '1,999p' "$tmp_file"
    rm -f "$tmp_file"
    return
  fi

  require_cmd launchctl
  mkdir -p "$HOME/Library/LaunchAgents"
  mv "$tmp_file" "$plist_path"
  launchctl bootout "gui/$(id -u)" "$plist_path" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$plist_path"
  echo "Installed launchd reconcile agent at $plist_path"
}

install_cron() {
  local cron_line="*/${interval_minutes} * * * * cd \"$REPO_ROOT\" && \"$reconcile_cmd\" >> \"$log_file\" 2>&1 # ${label}"
  local existing_crontab
  local rendered_crontab

  existing_crontab="$(crontab -l 2>/dev/null || true)"
  rendered_crontab="$(
    CRON_LINE="$cron_line" CRON_LABEL="$label" python3 - <<'PY' <<<"$existing_crontab"
import os
import sys

cron_line = os.environ["CRON_LINE"]
cron_label = os.environ["CRON_LABEL"]
existing = sys.stdin.read().splitlines()

filtered = [line for line in existing if cron_label not in line]
filtered.append(cron_line)
print("\n".join(line for line in filtered if line.strip()))
PY
  )"

  if [[ "$dry_run" -eq 1 ]]; then
    echo "Would install cron entry:"
    printf '%s\n' "$cron_line"
    return
  fi

  require_cmd crontab
  printf '%s\n' "$rendered_crontab" | crontab -
  echo "Installed cron reconcile entry for $label"
}

case "$mode" in
  launchd)
    install_launchd
    ;;
  cron)
    if [[ "$interval_minutes" -gt 59 ]]; then
      echo "Error: cron mode requires --interval-minutes between 1 and 59" >&2
      exit 2
    fi
    install_cron
    ;;
  *)
    echo "Error: unsupported --mode $mode" >&2
    exit 2
    ;;
esac
