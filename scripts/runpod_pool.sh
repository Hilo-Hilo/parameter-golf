#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

action="${1:-}"
case "$action" in
    list|create|stop|terminate)
        python3 "$SCRIPT_DIR/runpod_pool.py" "$@"
        ;;
    *)
        echo "Usage: $0 {list|create|stop|terminate} [args...]"
        exit 1
        ;;
esac
