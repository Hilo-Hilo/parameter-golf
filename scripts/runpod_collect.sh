#!/usr/bin/env bash
set -euo pipefail

# scripts/runpod_collect.sh
# Runs ON the Mac to collect job artifacts and append to registry.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: missing required command: $1" >&2
    exit 1
  fi
}

log_event() {
  "$SCRIPT_DIR/log_controller_event.sh" "$@" >/dev/null 2>&1 || true
}

announce() {
  local label="${CONTROLLER_LOG_LABEL:-$JOB_ID}"
  printf '[%s][%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$label" "$*"
}

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <ssh_host> [ssh_port] <job_id>" >&2
  exit 1
fi

if [ "$#" -eq 2 ]; then
  SSH_HOST="$1"
  SSH_PORT="${RUNPOD_SSH_PORT:-22}"
  JOB_ID="$2"
else
  SSH_HOST="$1"
  SSH_PORT="$2"
  JOB_ID="$3"
fi

require_cmd ssh
require_cmd rsync
require_cmd python3

collect_exit() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    log_event \
      --event "collect_failed" \
      --job-id "$JOB_ID" \
      --ssh-host "$SSH_HOST" \
      --ssh-port "$SSH_PORT" \
      --status "$rc" \
      --message "artifact collection exited non-zero"
  fi
}
trap collect_exit EXIT

WORKSPACE="/workspace"
JOB_DIR="$WORKSPACE/jobs/$JOB_ID"
PRIMARY_REMOTE_DIR="$WORKSPACE/parameter-golf/experiments/$JOB_ID"
FALLBACK_REMOTE_DIR="$JOB_DIR/experiments/$JOB_ID"
REMOTE_SPOOL_JSON="$WORKSPACE/parameter-golf/registry/spool/${JOB_ID}.json"

REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCAL_RESULTS_DIR="$REPO_ROOT/experiments/$JOB_ID"

mkdir -p "$LOCAL_RESULTS_DIR"

# Optional SSH identity file (set by Shadeform reconcile for non-default keys).
SSH_ID_OPTS="${SSH_IDENTITY_FILE:+-i $SSH_IDENTITY_FILE}"
# shellcheck disable=SC2086
SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_ID_OPTS -p $SSH_PORT"

announce "Collecting results from $SSH_HOST:$SSH_PORT for $JOB_ID..."

# Try direct rsync (works for RunPod where /workspace is on the host VM).
_rsync_got_files=0
# shellcheck disable=SC2086
if $SSH_CMD "$SSH_HOST" "[ -d \"$PRIMARY_REMOTE_DIR\" ]" 2>/dev/null; then
  # shellcheck disable=SC2086
  if rsync -avz -e "$SSH_CMD" "$SSH_HOST:$PRIMARY_REMOTE_DIR/" "$LOCAL_RESULTS_DIR/" 2>/tmp/collect_rsync_err; then
    _rsync_got_files=1
  else
    announce "rsync from $PRIMARY_REMOTE_DIR failed: $(cat /tmp/collect_rsync_err | head -3)"
  fi
else
  announce "rsync: $PRIMARY_REMOTE_DIR not found on host VM (may be inside Docker container — checking fallback)"
fi

# shellcheck disable=SC2086
if $SSH_CMD "$SSH_HOST" "[ -d \"$FALLBACK_REMOTE_DIR\" ]" 2>/dev/null; then
  # shellcheck disable=SC2086
  rsync -avz -e "$SSH_CMD" "$SSH_HOST:$FALLBACK_REMOTE_DIR/" "$LOCAL_RESULTS_DIR/wrapper/" 2>/dev/null || true
fi

# shellcheck disable=SC2086
if $SSH_CMD "$SSH_HOST" "[ -f \"$REMOTE_SPOOL_JSON\" ]" 2>/dev/null; then
  # shellcheck disable=SC2086
  rsync -avz -e "$SSH_CMD" "$SSH_HOST:$REMOTE_SPOOL_JSON" "$LOCAL_RESULTS_DIR/" 2>/dev/null || true
fi

# Docker-based fallback: if the experiment dir is still empty, the results are inside
# a Docker container on the host VM (Shadeform/Hyperstack setup).
_local_file_count=$(ls -A "$LOCAL_RESULTS_DIR" 2>/dev/null | wc -l)
if [ "$_local_file_count" -eq 0 ]; then
  announce "Local results dir empty after rsync — attempting Docker container fallback..."
  _CONTAINER_ID=""
  # shellcheck disable=SC2086
  _CONTAINER_ID=$($SSH_CMD "$SSH_HOST" "docker ps --format '{{.ID}}' | head -1" 2>/dev/null || echo "")
  if [ -n "$_CONTAINER_ID" ]; then
    announce "Found container $_CONTAINER_ID — attempting docker cp for $JOB_ID..."
    for _docker_src in "/workspace/parameter-golf/experiments/$JOB_ID" \
                       "/workspace/jobs/$JOB_ID/experiments/$JOB_ID"; do
      # shellcheck disable=SC2086
      if $SSH_CMD "$SSH_HOST" "docker exec \"$_CONTAINER_ID\" test -d \"$_docker_src\" 2>/dev/null" 2>/dev/null; then
        announce "Found experiment dir at $_docker_src in container — streaming via docker cp..."
        # shellcheck disable=SC2086
        if $SSH_CMD "$SSH_HOST" "docker cp \"$_CONTAINER_ID\":\"$_docker_src\" - 2>/dev/null" \
             2>/tmp/collect_docker_err | tar xf - -C "$(dirname "$LOCAL_RESULTS_DIR")/" 2>/tmp/collect_docker_tar_err; then
          _new_count=$(ls -A "$LOCAL_RESULTS_DIR" 2>/dev/null | wc -l)
          announce "docker cp fallback: extracted $_new_count files to $LOCAL_RESULTS_DIR"
          break
        else
          announce "docker cp fallback failed: ssh='$(cat /tmp/collect_docker_err 2>/dev/null | head -2)' tar='$(cat /tmp/collect_docker_tar_err 2>/dev/null | head -2)'"
        fi
      fi
    done
    # Also try to get the spool JSON from container
    _REMOTE_SPOOL_IN_CTR="/workspace/parameter-golf/registry/spool/${JOB_ID}.json"
    # shellcheck disable=SC2086
    if ! [ -f "$LOCAL_RESULTS_DIR/${JOB_ID}.json" ] && \
       $SSH_CMD "$SSH_HOST" "docker exec \"$_CONTAINER_ID\" test -f \"$_REMOTE_SPOOL_IN_CTR\" 2>/dev/null" 2>/dev/null; then
      announce "Fetching spool JSON from container..."
      # shellcheck disable=SC2086
      $SSH_CMD "$SSH_HOST" "docker exec \"$_CONTAINER_ID\" cat \"$_REMOTE_SPOOL_IN_CTR\"" 2>/dev/null \
        > "$LOCAL_RESULTS_DIR/${JOB_ID}.json.tmp" && \
        python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(d))" \
          "$LOCAL_RESULTS_DIR/${JOB_ID}.json.tmp" > "$LOCAL_RESULTS_DIR/${JOB_ID}.json" && \
        rm -f "$LOCAL_RESULTS_DIR/${JOB_ID}.json.tmp" || \
        rm -f "$LOCAL_RESULTS_DIR/${JOB_ID}.json.tmp"
    fi
  else
    announce "Docker fallback: no running container found on $SSH_HOST"
  fi
fi

_final_file_count=$(ls -A "$LOCAL_RESULTS_DIR" 2>/dev/null | wc -l)
announce "Collection complete: $LOCAL_RESULTS_DIR has $_final_file_count files"

# After collecting, append the canonical summary to locked runs.jsonl.
SUMMARY_FILE="$(
  python3 - "$LOCAL_RESULTS_DIR" <<'PY'
import json
import pathlib
import sys

results_dir = pathlib.Path(sys.argv[1])

for candidate in sorted(results_dir.glob("*.json")):
    try:
        payload = json.loads(candidate.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        continue
    if isinstance(payload, dict) and payload.get("run_id"):
        print(str(candidate))
        break
PY
)"

if [ -n "$SUMMARY_FILE" ] && [ -f "$SUMMARY_FILE" ]; then
  RUNS_LEDGER="$REPO_ROOT/registry/runs.jsonl"
  RUNS_LOCK="$REPO_ROOT/registry/.runs.lock"
  mkdir -p "$REPO_ROOT/registry"

  APPEND_RESULT="$(python3 - "$RUNS_LEDGER" "$RUNS_LOCK" "$SUMMARY_FILE" <<'PY'
import fcntl
import json
import pathlib
import sys

ledger_path = pathlib.Path(sys.argv[1])
lock_path = pathlib.Path(sys.argv[2])
summary_path = pathlib.Path(sys.argv[3])

ledger_path.parent.mkdir(parents=True, exist_ok=True)
lock_path.parent.mkdir(parents=True, exist_ok=True)
summary_text = summary_path.read_text(encoding="utf-8").strip()
summary_payload = json.loads(summary_text)
# Ensure single-line JSON for JSONL format (spool files may be pretty-printed)
summary_text = json.dumps(summary_payload)
run_id = summary_payload.get("run_id")

with lock_path.open("a+", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    existing_run_ids = set()
    if ledger_path.exists():
        for raw_line in ledger_path.read_text(encoding="utf-8").splitlines():
            raw_line = raw_line.strip()
            if not raw_line:
                continue
            try:
                payload = json.loads(raw_line)
            except json.JSONDecodeError:
                continue
            existing_run_ids.add(payload.get("run_id"))

    if run_id and run_id in existing_run_ids:
        print("skipped")
    else:
        with ledger_path.open("a+", encoding="utf-8") as ledger:
            ledger.write(summary_text)
            ledger.write("\n")
            ledger.flush()
        print("appended")

    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
PY
)"

  if [ "$APPEND_RESULT" = "skipped" ]; then
    announce "Summary already present in runs.jsonl; skipping duplicate append."
    collect_status="skipped"
  else
    announce "Appended summary to runs.jsonl."
    collect_status="appended"
  fi
else
  _dir_contents=$(ls "$LOCAL_RESULTS_DIR" 2>/dev/null | head -10 || echo "(empty)")
  announce "ERROR: No summary JSON found in $LOCAL_RESULTS_DIR"
  announce "  Dir contents: $_dir_contents"
  announce "  This means result collection FAILED for $JOB_ID — bpb will not be recorded!"
  collect_status="no_summary"
fi

log_event \
  --event "collect_completed" \
  --job-id "$JOB_ID" \
  --ssh-host "$SSH_HOST" \
  --ssh-port "$SSH_PORT" \
  --status "$collect_status" \
  --message "artifact collection finished"

trap - EXIT
