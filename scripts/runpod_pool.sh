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
  - RUNPOD_TEMPLATE_ID must be set for create
  - RUNPOD_TEMPLATE_IMAGE_NAME can override template image lookup if needed
  - RUNPOD_CONTAINER_ARGS is optional; leave it unset to preserve template startup
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: missing required command: $1" >&2
    exit 1
  fi
}

resolve_template_image_name() {
  local template_id="$1"

  python3 - "$template_id" <<'PY'
import json
import os
import pathlib
import sys
import urllib.parse
import urllib.request

template_id = sys.argv[1]
api_key = os.environ.get("RUNPOD_API_KEY", "").strip()

if not api_key:
    config_path = pathlib.Path.home() / ".runpod" / "config.toml"
    if config_path.exists():
        for raw_line in config_path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if line.startswith("apikey =") or line.startswith("api_key ="):
                api_key = line.split("=", 1)[1].strip().strip('"')
                if api_key:
                    break

if not api_key:
    print("")
    raise SystemExit(0)

url = (
    "https://rest.runpod.io/v1/templates/"
    + urllib.parse.quote(template_id)
    + "?includePublicTemplates=true&includeRunpodTemplates=true&includeEndpointBoundTemplates=false"
)
request = urllib.request.Request(url, headers={"Authorization": f"Bearer {api_key}"})

try:
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.load(response)
except Exception:
    print("")
    raise SystemExit(0)

print(payload.get("imageName", ""))
PY
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

    if [ -z "${RUNPOD_TEMPLATE_ID:-}" ]; then
      echo "Error: RUNPOD_TEMPLATE_ID must be set before creating RunPod pods." >&2
      echo "Refusing to fall back to a generic image for controller-managed launches." >&2
      exit 1
    fi

    TEMPLATE_IMAGE_NAME="${RUNPOD_TEMPLATE_IMAGE_NAME:-}"
    if [ -z "$TEMPLATE_IMAGE_NAME" ]; then
      TEMPLATE_IMAGE_NAME="$(resolve_template_image_name "$RUNPOD_TEMPLATE_ID")"
    fi
    if [ -z "$TEMPLATE_IMAGE_NAME" ]; then
      echo "Error: unable to resolve imageName for template $RUNPOD_TEMPLATE_ID." >&2
      echo "Set RUNPOD_TEMPLATE_IMAGE_NAME explicitly if template lookup is unavailable." >&2
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
      --templateId "$RUNPOD_TEMPLATE_ID"
      --imageName "$TEMPLATE_IMAGE_NAME"
    )

    if [ -n "${RUNPOD_CONTAINER_ARGS:-}" ]; then
      create_args+=(--args "$RUNPOD_CONTAINER_ARGS")
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
