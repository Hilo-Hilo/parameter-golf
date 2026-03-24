#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
SMOKE_TIMEOUT_SECONDS="${SMOKE_TIMEOUT_SECONDS:-120}"

resolve_timeout_cmd() {
  if command -v timeout >/dev/null 2>&1; then
    printf 'timeout\n'
  elif command -v gtimeout >/dev/null 2>&1; then
    printf 'gtimeout\n'
  else
    printf '\n'
  fi
}

timeout_cmd="$(resolve_timeout_cmd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required" >&2
  exit 2
fi

cd "$REPO_ROOT"
if [[ -n "$timeout_cmd" ]]; then
  exec "$timeout_cmd" -k 15s "$SMOKE_TIMEOUT_SECONDS" python3 scripts/smoke_sliding_eval.py "$@"
fi

exec python3 scripts/timeout_exec.py --kill-after 15 "$SMOKE_TIMEOUT_SECONDS" -- python3 scripts/smoke_sliding_eval.py "$@"
