#!/usr/bin/env bash
set -euo pipefail

echo "=== RunPod Status ==="
echo "Pods:"
python3 scripts/runpod_pool.py list

echo ""
echo "Queue:"
ls -la registry/queue 2>/dev/null || echo "Queue directory not found"
