#!/usr/bin/env bash
set -euo pipefail

# scripts/runpod_pool.sh
# Manage RunPod lifecycle using local runpodctl

# Official Parameter Golf RunPod template ID (update this with actual ID from RunPod if known)
# If using a custom template, supply it via env var.
TEMPLATE_ID="${RUNPOD_TEMPLATE_ID:-tjb4f8a8g0}" # A placeholder if needed, though upstream says use official PG template.

usage() {
  echo "Usage: $0 {get|create|start|stop|terminate} <pod_id_or_profile_name> [options]"
  echo ""
  echo "Examples:"
  echo "  $0 get [pod_id]"
  echo "  $0 create pg-exp-01"
  echo "  $0 create pg-rec-01"
  echo "  $0 start <pod_id>"
  echo "  $0 stop <pod_id>"
  echo "  $0 terminate <pod_id>"
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

ACTION="$1"
shift

case "$ACTION" in
  get)
    if [ $# -eq 1 ]; then
      runpodctl get pod "$1"
    else
      runpodctl get pods
    fi
    ;;
  create)
    if [ $# -lt 1 ]; then
      echo "Error: Must provide pod name, e.g., pg-exp-01"
      exit 1
    fi
    NAME="$1"
    
    # Determine profile from prefix
    if [[ "$NAME" == pg-exp-* ]]; then
      GPU_COUNT=1
      GPU_TYPE="NVIDIA H100 80GB HBM3"
    elif [[ "$NAME" == pg-rec-* ]]; then
      GPU_COUNT=8
      GPU_TYPE="NVIDIA H100 80GB HBM3"
    else
      echo "Error: Name must start with pg-exp- or pg-rec-"
      exit 1
    fi
    
    # Create pod using the PG template.
    # Note: Using an idle command so it stays running for SSH.
    echo "Creating pod $NAME ($GPU_COUNT x $GPU_TYPE)..."
    runpodctl create pod \
      --name "$NAME" \
      --image "runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04" \
      --gpuCount "$GPU_COUNT" \
      --gpuType "$GPU_TYPE" \
      --volumeInGb 100 \
      --containerDiskInGb 100 \
      --ports "22/tcp" \
      --dockerArgs "sleep infinity"
    # Note: --templateId <id> could be used instead of image/dockerArgs if we know the PG template ID
    ;;
  start)
    if [ $# -lt 1 ]; then
      echo "Error: Must provide pod ID"
      exit 1
    fi
    runpodctl start pod "$1"
    ;;
  stop)
    if [ $# -lt 1 ]; then
      echo "Error: Must provide pod ID"
      exit 1
    fi
    runpodctl stop pod "$1"
    ;;
  terminate)
    if [ $# -lt 1 ]; then
      echo "Error: Must provide pod ID"
      exit 1
    fi
    runpodctl remove pod "$1"
    ;;
  *)
    usage
    exit 1
    ;;
esac
