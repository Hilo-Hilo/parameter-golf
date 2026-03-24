#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
PROFILE_FILE="$REPO_ROOT/config/runpod_profiles.json"

usage() {
  cat <<'EOF'
Usage:
  scripts/runpod_pool.sh get [pod_id]
  scripts/runpod_pool.sh create <pod_name>
  scripts/runpod_pool.sh start <pod_id>
  scripts/runpod_pool.sh stop <pod_id>
  scripts/runpod_pool.sh terminate <pod_id>

Notes:
  - pod_name must start with pg-exp- or pg-rec-
  - create uses config/runpod_profiles.json for GPU selection
  - set RUNPOD_TEMPLATE_ID to force a specific template
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: missing required command: $1" >&2
    exit 1
  fi
}

profile_key_for_name() {
  case "$1" in
    pg-exp-*) printf 'pg-exp\n' ;;
    pg-rec-*) printf 'pg-rec\n' ;;
    *)
      echo "Error: pod name must start with pg-exp- or pg-rec-" >&2
      exit 1
      ;;
  esac
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

require_cmd runpodctl
require_cmd jq

ACTION="$1"
shift

case "$ACTION" in
  get)
    if [ $# -eq 1 ]; then
      runpodctl get pod "$1" --allfields
    else
      runpodctl get pod
    fi
    ;;
  create)
    if [ $# -lt 1 ]; then
      echo "Error: must provide pod name" >&2
      exit 1
    fi

    NAME="$1"
    PROFILE_KEY="$(profile_key_for_name "$NAME")"
    GPU_COUNT="$(jq -r --arg key "$PROFILE_KEY" '.[$key].gpu_count' "$PROFILE_FILE")"
    GPU_TYPE="$(jq -r --arg key "$PROFILE_KEY" '.[$key].gpu_type' "$PROFILE_FILE")"

    if [ -z "$GPU_COUNT" ] || [ "$GPU_COUNT" = "null" ] || [ -z "$GPU_TYPE" ] || [ "$GPU_TYPE" = "null" ]; then
      echo "Error: invalid profile configuration for $PROFILE_KEY in $PROFILE_FILE" >&2
      exit 1
    fi

    echo "Creating pod $NAME ($GPU_COUNT x $GPU_TYPE)..."

    create_args=(
      create pod
      --name "$NAME"
      --gpuCount "$GPU_COUNT"
      --gpuType "$GPU_TYPE"
      --containerDiskSize 50
      --volumeSize 50
      --volumePath "/workspace"
      --ports "22/tcp"
      --startSSH
      --args "sleep infinity"
    )

    if [ -n "${RUNPOD_TEMPLATE_ID:-}" ]; then
      create_args+=(--templateId "$RUNPOD_TEMPLATE_ID")
    else
      create_args+=(--imageName "runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04")
    fi

    runpodctl "${create_args[@]}"
    ;;
  start)
    if [ $# -lt 1 ]; then
      echo "Error: must provide pod ID" >&2
      exit 1
    fi
    runpodctl start pod "$1"
    ;;
  stop)
    if [ $# -lt 1 ]; then
      echo "Error: must provide pod ID" >&2
      exit 1
    fi
    runpodctl stop pod "$1"
    ;;
  terminate)
    if [ $# -lt 1 ]; then
      echo "Error: must provide pod ID" >&2
      exit 1
    fi
    runpodctl remove pod "$1"
    ;;
  *)
    usage
    exit 1
    ;;
esac
