#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--no-validation] <node_id>" >&2
}

NO_VALIDATION=0
NODE_ID=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-validation)
      NO_VALIDATION=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      if [ "$#" -ne 1 ]; then
        usage
        exit 1
      fi
      NODE_ID="$1"
      break
      ;;
    -*)
      echo "Error: unknown flag: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [ -n "$NODE_ID" ]; then
        echo "Error: expected a single node_id." >&2
        usage
        exit 1
      fi
      NODE_ID="$1"
      ;;
  esac
  shift
done

if [ -z "$NODE_ID" ]; then
  usage
  exit 1
fi

REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
MAIN_CHECKOUT="$(cd "$(git -C "$REPO_ROOT" rev-parse --git-common-dir)/.." && pwd)"
SAFE_NODE_ID="$(printf '%s' "$NODE_ID" | tr -cs 'A-Za-z0-9._-' '_')"
OBS_NODE_DIR="$MAIN_CHECKOUT/registry/observability/nodes"
OBS_JOB_DIR_ROOT="$MAIN_CHECKOUT/registry/observability/jobs"
OBS_NODE_STATUS_FILE="$OBS_NODE_DIR/${SAFE_NODE_ID}.json"
POLL_INTERVAL_SECONDS="${CONTROLLER_POLL_SECONDS:-15}"

export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
export CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1
export CLAUDE_CODE_DISABLE_CRON=1

REQUIRED_UPSTREAM_CONTEXT_FILES=(
  "$MAIN_CHECKOUT/context/upstream/issue_140.md"
  "$MAIN_CHECKOUT/context/upstream/pr_digest.md"
  "$MAIN_CHECKOUT/context/upstream/frontier_digest.md"
)

mkdir -p "$MAIN_CHECKOUT/registry/spool"
STATE_FILE="$MAIN_CHECKOUT/registry/spool/${NODE_ID}_state.json"
NODES_DB="$MAIN_CHECKOUT/registry/nodes.jsonl"
NODES_LOCK_FILE="$MAIN_CHECKOUT/registry/.nodes.lock"
NODE_LOCK_ROOT="$MAIN_CHECKOUT/registry/node_locks"
NODE_LOCK_DIR="$NODE_LOCK_ROOT/$SAFE_NODE_ID"
touch "$NODES_DB"

SCRATCH_DIR=$(mktemp -d)
SCRATCH_REF="scratch_${SAFE_NODE_ID}_$$"
PLAN_WORKTREE="$MAIN_CHECKOUT/worktrees/$SCRATCH_REF"
PHASE_LOG_DIR="$MAIN_CHECKOUT/registry/phase_logs/$SAFE_NODE_ID/$SCRATCH_REF"
PLAN_OUTPUT_FILE="$PHASE_LOG_DIR/plan.output.json"
GOV_OUTPUT_FILE="$PHASE_LOG_DIR/governance.output.json"
DIAGNOSE_OUTPUT_FILE="$PHASE_LOG_DIR/diagnose.output.json"
REFLECT_OUTPUT_FILE="$PHASE_LOG_DIR/reflect.output.json"
JOB_DISPATCHED=0
POD_CLEANED=0
CHILD_NODE_ID=""
BRANCH_NAME=""
COMMIT_SHA=""
SSH_TARGET=""
SSH_PORT="22"
LEASE_FILE=""
CURRENT_POD_ID=""
CURRENT_POD_NAME=""
JOB_OBS_DIR=""
JOB_LOG_MIRROR=""
JOB_HEARTBEAT_MIRROR=""
JOB_FINAL_STATE_MIRROR=""
LOG_CURSOR_FILE=""
CURRENT_PHASE="setup"

mkdir -p "$PHASE_LOG_DIR"
mkdir -p "$OBS_NODE_DIR" "$OBS_JOB_DIR_ROOT"

log_event() {
  "$MAIN_CHECKOUT/scripts/log_controller_event.sh" "$@" >/dev/null 2>&1 || true
}

announce() {
  local label
  if [ -n "$BRANCH_NAME" ]; then
    label="$BRANCH_NAME"
  elif [ -n "$CHILD_NODE_ID" ]; then
    label="$CHILD_NODE_ID"
  else
    label="tree/$NODE_ID"
  fi

  printf '[%s][%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$label" "$*"
}

prepare_job_observability() {
  if [ -z "$CHILD_NODE_ID" ]; then
    return 0
  fi

  JOB_OBS_DIR="$OBS_JOB_DIR_ROOT/$CHILD_NODE_ID"
  JOB_LOG_MIRROR="$JOB_OBS_DIR/run.log"
  JOB_HEARTBEAT_MIRROR="$JOB_OBS_DIR/heartbeat.json"
  JOB_FINAL_STATE_MIRROR="$JOB_OBS_DIR/final_state.json"
  LOG_CURSOR_FILE="$JOB_OBS_DIR/.terminal_log_cursor"
  mkdir -p "$JOB_OBS_DIR"
}

write_observability_state() {
  local phase="$1"
  local status="$2"
  local message="${3:-}"

  python3 - \
    "$OBS_NODE_STATUS_FILE" \
    "$JOB_OBS_DIR" \
    "$NODE_ID" \
    "$SAFE_NODE_ID" \
    "$CHILD_NODE_ID" \
    "$BRANCH_NAME" \
    "$COMMIT_SHA" \
    "$SCRATCH_REF" \
    "$phase" \
    "$status" \
    "$message" \
    "$PHASE_LOG_DIR" \
    "$PLAN_OUTPUT_FILE" \
    "$GOV_OUTPUT_FILE" \
    "$DIAGNOSE_OUTPUT_FILE" \
    "$REFLECT_OUTPUT_FILE" \
    "$CURRENT_POD_ID" \
    "$CURRENT_POD_NAME" \
    "$SSH_TARGET" \
    "$SSH_PORT" \
    "$LEASE_FILE" \
    "$JOB_LOG_MIRROR" \
    "$JOB_HEARTBEAT_MIRROR" \
    "$JOB_FINAL_STATE_MIRROR" \
    "$$" <<'PY'
from datetime import datetime, timezone
import json
import pathlib
import sys

(
    node_status_path,
    job_dir,
    parent_node_id,
    safe_node_id,
    child_node_id,
    branch_name,
    commit_sha,
    scratch_ref,
    phase,
    status,
    message,
    phase_log_dir,
    plan_output_file,
    governance_output_file,
    diagnose_output_file,
    reflect_output_file,
    pod_id,
    pod_name,
    ssh_host,
    ssh_port,
    lease_file,
    run_log_path,
    heartbeat_path,
    final_state_path,
    controller_pid,
) = sys.argv[1:]

now = datetime.now(timezone.utc)

def last_nonempty_line(path_str: str) -> str:
    if not path_str:
        return ""
    path = pathlib.Path(path_str)
    if not path.exists() or not path.is_file():
        return ""
    size = path.stat().st_size
    with path.open("rb") as fh:
        fh.seek(max(size - 65536, 0))
        data = fh.read().decode("utf-8", errors="replace")
    for raw_line in reversed(data.splitlines()):
        line = raw_line.strip()
        if line:
            return line[-500:]
    return ""

def parse_json_file(path_str: str):
    if not path_str:
        return {}
    path = pathlib.Path(path_str)
    if not path.exists() or not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}

heartbeat_payload = parse_json_file(heartbeat_path)
final_state_payload = parse_json_file(final_state_path)
lease_payload = parse_json_file(lease_file)

payload = {
    "updated_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "controller_pid": int(controller_pid),
    "node_id": parent_node_id,
    "safe_node_id": safe_node_id,
    "scratch_ref": scratch_ref,
    "phase": phase,
    "status": status,
    "phase_log_dir": phase_log_dir,
    "phase_outputs": {
        "plan": plan_output_file,
        "governance": governance_output_file,
        "diagnose": diagnose_output_file,
        "reflect": reflect_output_file,
    },
}

if message:
    payload["message"] = message
if child_node_id:
    payload["child_node_id"] = child_node_id
if branch_name:
    payload["branch"] = branch_name
if commit_sha:
    payload["commit"] = commit_sha
if pod_id:
    payload["pod_id"] = pod_id
if pod_name:
    payload["pod_name"] = pod_name
if ssh_host:
    payload["ssh_host"] = ssh_host
if ssh_port:
    payload["ssh_port"] = ssh_port
if run_log_path:
    payload["live_run_log_path"] = run_log_path
    last_log_line = last_nonempty_line(run_log_path)
    if last_log_line:
        payload["last_log_line"] = last_log_line
if heartbeat_path:
    payload["heartbeat_path"] = heartbeat_path
if heartbeat_payload:
    heartbeat_ts = heartbeat_payload.get("timestamp")
    if heartbeat_ts:
        payload["last_heartbeat"] = heartbeat_ts
        try:
            heartbeat_dt = datetime.strptime(heartbeat_ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            payload["heartbeat_age_seconds"] = max(int((now - heartbeat_dt).total_seconds()), 0)
        except ValueError:
            pass
if final_state_path:
    payload["final_state_path"] = final_state_path
if final_state_payload:
    payload["final_state"] = final_state_payload
if lease_file:
    payload["lease_file"] = lease_file
if lease_payload:
    for key in ("profile_key", "dispatched_at", "lease_expires_at"):
        value = lease_payload.get(key)
        if value:
            payload[key] = value
    cleanup = lease_payload.get("cleanup")
    if isinstance(cleanup, dict) and cleanup:
        payload["cleanup"] = cleanup
    lease_expires_at = lease_payload.get("lease_expires_at")
    if lease_expires_at:
        try:
            deadline = datetime.strptime(lease_expires_at, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            payload["controller_ttl_remaining_seconds"] = int((deadline - now).total_seconds())
        except ValueError:
            pass

node_status = pathlib.Path(node_status_path)
node_status.parent.mkdir(parents=True, exist_ok=True)
node_status.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

if job_dir:
    job_status = pathlib.Path(job_dir) / "status.json"
    job_status.parent.mkdir(parents=True, exist_ok=True)
    job_status.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

load_lease_metadata() {
  if [ -z "$LEASE_FILE" ] || [ ! -f "$LEASE_FILE" ]; then
    return 0
  fi

  CURRENT_POD_ID="$(jq -r '.pod_id // empty' "$LEASE_FILE")"
  CURRENT_POD_NAME="$(jq -r '.pod_name // empty' "$LEASE_FILE")"
  SSH_TARGET="$(jq -r '.ssh.host // empty' "$LEASE_FILE")"
  SSH_PORT="$(jq -r '.ssh.port // "22"' "$LEASE_FILE")"
}

mirror_remote_observability() {
  if [ -z "$JOB_OBS_DIR" ] || [ -z "$SSH_TARGET" ]; then
    return 0
  fi

  local ssh_opts=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$SSH_PORT")
  local ssh_transport="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p $SSH_PORT"
  local remote_wrapper_log="/workspace/jobs/$CHILD_NODE_ID/experiments/$CHILD_NODE_ID/run.log"
  local remote_heartbeat="/workspace/parameter-golf/registry/heartbeats/${CHILD_NODE_ID}.json"
  local remote_final_state="/workspace/parameter-golf/registry/spool/${CHILD_NODE_ID}_final_state.json"

  mkdir -p "$JOB_OBS_DIR"

  if ssh "${ssh_opts[@]}" "$SSH_TARGET" "[ -f \"$remote_wrapper_log\" ]" >/dev/null 2>&1; then
    rsync -az --append-verify -e "$ssh_transport" "$SSH_TARGET:$remote_wrapper_log" "$JOB_LOG_MIRROR" >/dev/null 2>&1 || true
  fi

  if ssh "${ssh_opts[@]}" "$SSH_TARGET" "[ -f \"$remote_heartbeat\" ]" >/dev/null 2>&1; then
    rsync -az -e "$ssh_transport" "$SSH_TARGET:$remote_heartbeat" "$JOB_HEARTBEAT_MIRROR" >/dev/null 2>&1 || true
  fi

  if ssh "${ssh_opts[@]}" "$SSH_TARGET" "[ -f \"$remote_final_state\" ]" >/dev/null 2>&1; then
    rsync -az -e "$ssh_transport" "$SSH_TARGET:$remote_final_state" "$JOB_FINAL_STATE_MIRROR" >/dev/null 2>&1 || true
  fi
}

print_new_remote_log_lines() {
  if [ -z "$JOB_LOG_MIRROR" ] || [ ! -f "$JOB_LOG_MIRROR" ]; then
    return 0
  fi

  local seen_lines="0"
  local total_lines

  if [ -n "$LOG_CURSOR_FILE" ] && [ -f "$LOG_CURSOR_FILE" ]; then
    seen_lines="$(tr -dc '0-9' < "$LOG_CURSOR_FILE" 2>/dev/null || true)"
  fi
  if [ -z "$seen_lines" ]; then
    seen_lines="0"
  fi

  total_lines="$(wc -l < "$JOB_LOG_MIRROR" | tr -d ' ')"
  if [ -z "$total_lines" ]; then
    total_lines="0"
  fi

  if [ "$total_lines" -lt "$seen_lines" ]; then
    seen_lines="0"
  fi

  if [ "$total_lines" -gt "$seen_lines" ]; then
    local start_line=$((seen_lines + 1))
    while IFS= read -r line; do
      if [ -n "$line" ]; then
        announce "remote | $line"
      fi
    done < <(sed -n "${start_line},${total_lines}p" "$JOB_LOG_MIRROR")
  fi

  if [ -n "$LOG_CURSOR_FILE" ]; then
    printf '%s\n' "$total_lines" > "$LOG_CURSOR_FILE"
  fi
}

acquire_node_lock() {
  mkdir -p "$NODE_LOCK_ROOT"

  while true; do
    if mkdir "$NODE_LOCK_DIR" 2>/dev/null; then
      printf '%s\n' "$$" > "$NODE_LOCK_DIR/pid"
      return
    fi

    if [ -f "$NODE_LOCK_DIR/pid" ]; then
      owner_pid="$(cat "$NODE_LOCK_DIR/pid" 2>/dev/null || echo "")"
      if [ -n "$owner_pid" ] && ! kill -0 "$owner_pid" 2>/dev/null; then
        rm -rf "$NODE_LOCK_DIR"
        continue
      fi
    fi

    announce "Error: node $NODE_ID is already being processed." >&2
    exit 1
  done
}

release_node_lock() {
  rm -rf "$NODE_LOCK_DIR" 2>/dev/null || true
}

cleanup() {
  local rc=$?
  trap - EXIT INT TERM

  if [ "$rc" -eq 0 ]; then
    write_observability_state "$CURRENT_PHASE" "completed" "branch cycle exited successfully"
    log_event \
      --event "node_finished" \
      --node-id "$NODE_ID" \
      --job-id "$CHILD_NODE_ID" \
      --phase "$CURRENT_PHASE" \
      --branch "$BRANCH_NAME" \
      --status "completed" \
      --message "branch cycle exited successfully"
  else
    write_observability_state "$CURRENT_PHASE" "failed" "branch cycle exited with rc=$rc"
    log_event \
      --event "node_failed" \
      --node-id "$NODE_ID" \
      --job-id "$CHILD_NODE_ID" \
      --phase "$CURRENT_PHASE" \
      --branch "$BRANCH_NAME" \
      --status "$rc" \
      --message "branch cycle exited non-zero"
  fi

  if [ "$JOB_DISPATCHED" -eq 1 ] && [ "$POD_CLEANED" -eq 0 ] && [ -n "$CHILD_NODE_ID" ]; then
    cd "$MAIN_CHECKOUT"
    scripts/runpod_cleanup.sh --job-id "$CHILD_NODE_ID" --reason "controller_exit" >/dev/null 2>&1 || true
  fi

  if [ "$JOB_DISPATCHED" -eq 0 ]; then
    retract_child_node "pre_dispatch_exit"
    requeue_parent_node "pre_dispatch_exit"
  fi

  release_node_lock
  rm -rf "$SCRATCH_DIR"
  if [ -d "$PLAN_WORKTREE" ]; then
    git worktree remove -f "$PLAN_WORKTREE" 2>/dev/null || true
    git branch -D "$SCRATCH_REF" 2>/dev/null || true
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

controller_ttl_epoch() {
  local lease_file="$1"

  python3 - "$lease_file" <<'PY'
from datetime import datetime, timezone
import json
import pathlib
import sys

lease_path = pathlib.Path(sys.argv[1])
if not lease_path.exists():
    print("0")
    raise SystemExit(0)

try:
    payload = json.loads(lease_path.read_text(encoding="utf-8"))
except json.JSONDecodeError:
    print("0")
    raise SystemExit(0)

lease_expires_at = payload.get("lease_expires_at")
if not lease_expires_at:
    print("0")
    raise SystemExit(0)

deadline = datetime.strptime(lease_expires_at, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
print(int(deadline.timestamp()))
PY
}

stage_plan_changes() {
  git add -A -- . \
    ':(exclude)worktrees/**' \
    ':(exclude)experiments/**' \
    ':(exclude)registry/**' \
    ':(exclude).cursor/hooks/state/**' \
    ':(exclude)tmp/**'
}

compact_json_file() {
  local json_path="$1"

  python3 - "$json_path" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
print(json.dumps(json.loads(path.read_text(encoding="utf-8")), separators=(",", ":")))
PY
}

ensure_required_upstream_context() {
  local missing=()
  local path

  for path in "${REQUIRED_UPSTREAM_CONTEXT_FILES[@]}"; do
    if [ ! -f "$path" ]; then
      missing+=("$path")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    return 0
  fi

  announce "Error: missing required upstream context files for the plan phase."
  for path in "${missing[@]}"; do
    announce "  missing: $path"
  done
  announce "Run scripts/sync_upstream_context.sh before starting the swarm."
  write_observability_state "plan" "failed" "missing required upstream context files"
  log_event \
    --event "phase_failed" \
    --node-id "$NODE_ID" \
    --job-id "$CHILD_NODE_ID" \
    --phase "plan" \
    --branch "$BRANCH_NAME" \
    --status "missing_context" \
    --message "required upstream context files are missing"
  return 1
}

ensure_dispatch_feasible() {
  if [ -n "${RUNPOD_POD_ID:-}" ]; then
    return 0
  fi
  if [ -n "${RUNPOD_TEMPLATE_ID:-}" ]; then
    return 0
  fi

  local existing_pod
  existing_pod="$(runpodctl get pod 2>/dev/null \
    | awk 'NR > 1 && $2 ~ /^pg-(exp|rec)/ { print $1; exit }' || true)"
  if [ -n "$existing_pod" ]; then
    return 0
  fi

  announce "Error: dispatch will fail -- no RUNPOD_TEMPLATE_ID, no RUNPOD_POD_ID override, and no existing pg-* pod."
  announce "Set RUNPOD_TEMPLATE_ID before starting the swarm, or ensure a reusable pod exists."
  write_observability_state "plan" "failed" "dispatch not feasible: no pods and no template ID"
  log_event \
    --event "phase_failed" \
    --node-id "$NODE_ID" \
    --phase "plan" \
    --status "no_dispatch_target" \
    --message "pre-flight: RUNPOD_TEMPLATE_ID unset and no reusable pods found"
  return 1
}

build_plan_prompt() {
  python3 - "$MAIN_CHECKOUT" "$STATE_FILE" <<'PY'
import pathlib
import sys

repo = pathlib.Path(sys.argv[1])
state_path = pathlib.Path(sys.argv[2])


def read_lines(path, start=1, limit=None):
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return f"<missing: {path}>"

    if not lines:
        return "<empty>"

    start_index = max(start - 1, 0)
    if start_index >= len(lines):
        return f"<offset {start} beyond EOF for {path}>"

    if limit is None:
        excerpt = lines[start_index:]
        truncated = False
    else:
        excerpt = lines[start_index:start_index + limit]
        truncated = start_index + limit < len(lines)

    body = "\n".join(excerpt)
    if truncated:
        body += "\n... [truncated; use targeted Read with offset/limit if more detail is required]"
    return body


def tail_lines(path, limit):
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return f"<missing: {path}>"

    if not lines:
        return "<empty>"

    excerpt = lines[-limit:]
    prefix = ""
    if len(lines) > limit:
        prefix = f"... [showing last {limit} of {len(lines)} lines]\n"
    return prefix + "\n".join(excerpt)


def list_spool_json(path):
    directory = pathlib.Path(path)
    if not directory.exists():
        return f"<missing directory: {directory}>"

    names = sorted(entry.name for entry in directory.glob("*.json"))
    if not names:
        return "<no spool json files>"
    return "\n".join(f"- {name}" for name in names)


def section(title, body):
    return f"## {title}\n{body.rstrip()}".rstrip()


state_payload = "{}"
if state_path.exists():
    payload = state_path.read_text(encoding="utf-8").strip()
    if payload:
        state_payload = payload

prompt_sections = [
    repo.joinpath("worker_program.md").read_text(encoding="utf-8").rstrip(),
    section(
        "Controller Tooling Guardrails",
        "\n".join(
            [
                "- The Read tool hard-fails above roughly 10k tokens. Do not read `context/upstream/issue_140.md`, `README.md`, or `registry/runs.jsonl` in full.",
                "- Use the bundled excerpts below first. If you need more detail, use targeted Read calls with offset/limit or Grep/Glob.",
                "- Keep exploration bounded. Prefer one novel, well-motivated hypothesis over exhaustive repo scanning.",
                "- If the bundled context below is sufficient, do not reread those same files.",
            ]
        ),
    ),
    section("Bundled CLAUDE.md", read_lines(repo / "CLAUDE.md")),
    section("Bundled PLAN.md", read_lines(repo / "PLAN.md")),
    section("Bundled Journal", read_lines(repo / "journal.md")),
    section("Bundled README Leaderboard Excerpt", read_lines(repo / "README.md", start=29, limit=28)),
    section("Bundled issue_140.md Excerpt", read_lines(repo / "context/upstream/issue_140.md", start=1, limit=160)),
    section("Bundled pr_digest.md", read_lines(repo / "context/upstream/pr_digest.md")),
    section("Bundled frontier_digest.md", read_lines(repo / "context/upstream/frontier_digest.md")),
    section("Bundled registry/runs.jsonl Tail", tail_lines(repo / "registry/runs.jsonl", 12)),
    section("Bundled registry/jobs.jsonl Tail", tail_lines(repo / "registry/jobs.jsonl", 12)),
    section("Bundled registry/spool JSON Files", list_spool_json(repo / "registry/spool")),
    section(
        "Current Phase",
        "plan\nPlease analyze history, make local file edits for your new approach, and then output your JSON proposal.\nPrevious state if any:\n"
        + state_payload,
    ),
]

print("\n\n".join(prompt_sections))
PY
}

run_claude_phase() {
  local phase="$1"
  local prompt="$2"
  local max_turns="$3"
  local max_budget="$4"
  local schema_path="$5"
  local output_file="$6"
  local stderr_log="$PHASE_LOG_DIR/${phase}.stderr.log"
  local schema_json=""
  local cli_subtype=""

  rm -f "$output_file" "$stderr_log"

  CURRENT_PHASE="$phase"
  announce "Running Claude ${phase} phase non-interactively..."
  announce "  JSON output: $output_file"
  announce "  STDERR log:  $stderr_log"
  write_observability_state "$phase" "running" "Claude ${phase} phase started"
  log_event \
    --event "phase_started" \
    --node-id "$NODE_ID" \
    --job-id "$CHILD_NODE_ID" \
    --phase "$phase" \
    --branch "$BRANCH_NAME" \
    --status "running" \
    --message "Claude ${phase} phase started"

  if ! schema_json="$(compact_json_file "$schema_path" 2>>"$stderr_log")"; then
    write_observability_state "$phase" "failed" "Invalid JSON schema at $schema_path"
    log_event \
      --event "phase_failed" \
      --node-id "$NODE_ID" \
      --job-id "$CHILD_NODE_ID" \
      --phase "$phase" \
      --branch "$BRANCH_NAME" \
      --status "invalid_schema" \
      --message "failed to load JSON schema from $schema_path"
    announce "Error: Failed to load JSON schema from $schema_path. See $stderr_log"
    return 1
  fi

  if ! claude -p "$prompt" \
    --max-turns "$max_turns" \
    --max-budget-usd "$max_budget" \
    --tools "Read,Edit,Glob,Grep" \
    --settings "$MAIN_CHECKOUT/.claude/settings.json" \
    --mcp-config "$MAIN_CHECKOUT/.mcp.json" \
    --strict-mcp-config \
    --no-session-persistence \
    --output-format json \
    --json-schema "$schema_json" \
    > "$output_file" 2> "$stderr_log" < /dev/null; then
    announce "Warning: Claude ${phase} phase exited non-zero. See $stderr_log"
  fi

  if [ ! -s "$output_file" ]; then
    write_observability_state "$phase" "failed" "Claude ${phase} phase produced no JSON output"
    log_event \
      --event "phase_failed" \
      --node-id "$NODE_ID" \
      --job-id "$CHILD_NODE_ID" \
      --phase "$phase" \
      --branch "$BRANCH_NAME" \
      --status "no_output" \
      --message "Claude phase produced no JSON output"
    announce "Error: Claude ${phase} phase produced no JSON output. See $stderr_log"
    return 1
  fi

  if jq -e '.is_error == true' "$output_file" >/dev/null 2>&1; then
    local cli_error
    cli_error="$(jq -r '.result // "Claude CLI returned an unspecified error."' "$output_file")"
    write_observability_state "$phase" "failed" "Claude ${phase} phase failed: $cli_error"
    log_event \
      --event "phase_failed" \
      --node-id "$NODE_ID" \
      --job-id "$CHILD_NODE_ID" \
      --phase "$phase" \
      --branch "$BRANCH_NAME" \
      --status "cli_error" \
      --message "$cli_error"
    announce "Error: Claude ${phase} phase failed: $cli_error"
    announce "See $stderr_log and $output_file for details."
    return 1
  fi

  cli_subtype="$(jq -r '.subtype // "unknown"' "$output_file" 2>/dev/null || echo "unknown")"
  if [ "$cli_subtype" != "success" ]; then
    local cli_error
    cli_error="$(jq -r '.result // ((.errors // []) | if length > 0 then join("; ") else empty end)' "$output_file" 2>/dev/null || true)"
    if [ -z "$cli_error" ] || [ "$cli_error" = "null" ]; then
      cli_error="Claude CLI returned subtype=$cli_subtype"
    fi
    write_observability_state "$phase" "failed" "Claude ${phase} phase failed: $cli_error"
    log_event \
      --event "phase_failed" \
      --node-id "$NODE_ID" \
      --job-id "$CHILD_NODE_ID" \
      --phase "$phase" \
      --branch "$BRANCH_NAME" \
      --status "cli_${cli_subtype}" \
      --message "$cli_error"
    announce "Error: Claude ${phase} phase failed: $cli_error"
    announce "See $stderr_log and $output_file for details."
    return 1
  fi

  if ! jq -e '.structured_output != null' "$output_file" >/dev/null 2>&1; then
    write_observability_state "$phase" "failed" "Claude ${phase} phase returned no structured_output"
    log_event \
      --event "phase_failed" \
      --node-id "$NODE_ID" \
      --job-id "$CHILD_NODE_ID" \
      --phase "$phase" \
      --branch "$BRANCH_NAME" \
      --status "missing_structured_output" \
      --message "Claude phase returned no structured_output"
    announce "Error: Claude ${phase} phase returned no structured_output. See $stderr_log and $output_file"
    return 1
  fi

  write_observability_state "$phase" "completed" "Claude ${phase} phase completed"
  log_event \
    --event "phase_completed" \
    --node-id "$NODE_ID" \
    --job-id "$CHILD_NODE_ID" \
    --phase "$phase" \
    --branch "$BRANCH_NAME" \
    --status "completed" \
    --message "Claude ${phase} phase completed"
}

write_job_spec() {
  local output_path="$1"

  if [ "$NO_VALIDATION" -eq 1 ]; then
    # 1-GPU proxy: inject MAX_WALLCLOCK_SECONDS into env_overrides if not
    # already set by the plan.  The remote run script also auto-detects the
    # SKU, but setting it here ensures older pod checkouts get the budget too.
    # Default 5100s = 8.5x official 600s (H100 NVL, the most common RunPod SKU).
    # Rewrite gpu_count to 1, inject proxy wallclock, and fix run_argv
    # so torchrun uses nproc_per_node=1 instead of 8.
    jq --arg branch "$BRANCH_NAME" \
       --arg commit "$COMMIT_SHA" \
       --arg job_id "$CHILD_NODE_ID" \
       --arg gpu_type "H100" \
       '.structured_output
        + {branch: $branch, commit_sha: $commit, job_id: $job_id}
        | .resource_profile = {gpu_count: 1, gpu_type: $gpu_type}
        | .expected_track = "non_record_h100x1"
        | .env_overrides = ((.env_overrides // {}) + (if (.env_overrides // {}).MAX_WALLCLOCK_SECONDS then {} else {MAX_WALLCLOCK_SECONDS: "5100"} end) + {RUNPOD_OUTER_TIMEOUT_SECONDS: "7200"})
        | .run_argv = [.run_argv[]? | if startswith("--nproc_per_node=") then "--nproc_per_node=1" else . end]' \
       "$PLAN_OUTPUT_FILE" > "$output_path"
  else
    jq --arg branch "$BRANCH_NAME" \
       --arg commit "$COMMIT_SHA" \
       --arg job_id "$CHILD_NODE_ID" \
       '.structured_output + {branch: $branch, commit_sha: $commit, job_id: $job_id}' \
       "$PLAN_OUTPUT_FILE" > "$output_path"
  fi
}

requeue_parent_node() {
  local reason="${1:-pre_dispatch_exit}"
  local result

  result="$(python3 - "$NODES_DB" "$NODES_LOCK_FILE" "$NODE_ID" <<'PY'
import fcntl
import json
import os
import pathlib
import sys
import tempfile

db_path = pathlib.Path(sys.argv[1])
lock_path = pathlib.Path(sys.argv[2])
node_id = sys.argv[3]

lock_path.parent.mkdir(parents=True, exist_ok=True)
db_path.parent.mkdir(parents=True, exist_ok=True)
db_path.touch(exist_ok=True)

rows = []
updated = False

with lock_path.open("a+", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

    for raw_line in db_path.read_text(encoding="utf-8").splitlines():
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        try:
            row = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        if row.get("node_id") == node_id and row.get("status") == "running":
            row["status"] = "pending"
            updated = True
        rows.append(row)

    fd, tmp_path = tempfile.mkstemp(dir=str(db_path.parent), prefix=".nodes.", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp_file:
            for row in rows:
                tmp_file.write(json.dumps(row))
                tmp_file.write("\n")
        os.replace(tmp_path, db_path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

print("updated" if updated else "unchanged")
PY
)"

  if [ "$result" = "updated" ]; then
    announce "Requeued parent node $NODE_ID after controller exit before dispatch."
    log_event \
      --event "node_requeued" \
      --job-id "$NODE_ID" \
      --reason "$reason" \
      --status "pending" \
      --message "restored parent node to pending after pre-dispatch controller exit"
  fi
}

retract_child_node() {
  local reason="${1:-pre_dispatch_exit}"
  local result

  if [ -z "$CHILD_NODE_ID" ]; then
    return 0
  fi

  result="$(python3 - "$NODES_DB" "$NODES_LOCK_FILE" "$CHILD_NODE_ID" <<'PY'
import fcntl
import json
import os
import pathlib
import sys
import tempfile

db_path = pathlib.Path(sys.argv[1])
lock_path = pathlib.Path(sys.argv[2])
child_node_id = sys.argv[3]

lock_path.parent.mkdir(parents=True, exist_ok=True)
db_path.parent.mkdir(parents=True, exist_ok=True)
db_path.touch(exist_ok=True)

rows = []
removed = False

with lock_path.open("a+", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

    for raw_line in db_path.read_text(encoding="utf-8").splitlines():
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        try:
            row = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        if row.get("node_id") == child_node_id and row.get("status") == "running":
            removed = True
            continue
        rows.append(row)

    fd, tmp_path = tempfile.mkstemp(dir=str(db_path.parent), prefix=".nodes.", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp_file:
            for row in rows:
                tmp_file.write(json.dumps(row))
                tmp_file.write("\n")
        os.replace(tmp_path, db_path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

print("removed" if removed else "unchanged")
PY
)"

  if [ "$result" = "removed" ]; then
    announce "Retracted child node $CHILD_NODE_ID after controller exit before dispatch."
    log_event \
      --event "child_retracted" \
      --job-id "$CHILD_NODE_ID" \
      --reason "$reason" \
      --status "removed" \
      --message "removed stale child node after pre-dispatch controller exit"

    # Clean up the git branch so retries don't fail with "branch already exists".
    if [ -n "$BRANCH_NAME" ]; then
      git -C "$MAIN_CHECKOUT" branch -D "$BRANCH_NAME" 2>/dev/null || true
      git -C "$MAIN_CHECKOUT" push origin --delete "$BRANCH_NAME" 2>/dev/null || true
    fi
  fi
}

fingerprint_exists() {
  local fingerprint="$1"

  python3 - "$NODES_DB" "$fingerprint" <<'PY'
import json
import pathlib
import sys

db_path = pathlib.Path(sys.argv[1])
fingerprint = sys.argv[2]
exists = False

if db_path.exists():
    for raw_line in db_path.read_text(encoding="utf-8").splitlines():
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        try:
            row = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        if row.get("fingerprint") == fingerprint:
            exists = True
            break

print("true" if exists else "false")
PY
}

append_node_record() {
  local status="$1"
  local enforce_unique="${2:-0}"

  python3 - "$NODES_DB" "$NODES_LOCK_FILE" "$NODE_ID" "$CHILD_NODE_ID" "$PROPOSED_SLUG" "$FINGERPRINT" "$status" "$enforce_unique" <<'PY'
import fcntl
import json
import pathlib
import sys

db_path = pathlib.Path(sys.argv[1])
lock_path = pathlib.Path(sys.argv[2])
parent_node = sys.argv[3]
node_id = sys.argv[4]
slug = sys.argv[5]
fingerprint = sys.argv[6]
status = sys.argv[7]
enforce_unique = sys.argv[8] == "1"

lock_path.parent.mkdir(parents=True, exist_ok=True)
db_path.parent.mkdir(parents=True, exist_ok=True)

with lock_path.open("a+", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

    if enforce_unique and db_path.exists():
        for raw_line in db_path.read_text(encoding="utf-8").splitlines():
            raw_line = raw_line.strip()
            if not raw_line:
                continue
            try:
                row = json.loads(raw_line)
            except json.JSONDecodeError:
                continue
            if row.get("fingerprint") == fingerprint:
                raise SystemExit(3)

    record = {
        "parent": parent_node,
        "node_id": node_id,
        "slug": slug,
        "fingerprint": fingerprint,
        "status": status,
    }
    with db_path.open("a", encoding="utf-8") as db_file:
        db_file.write(json.dumps(record))
        db_file.write("\n")

    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
PY
}

resolve_diagnose_log() {
  local results_dir="$1"

  python3 - "$results_dir" <<'PY'
import pathlib
import sys

results_dir = pathlib.Path(sys.argv[1])
log_candidates = list(results_dir.glob("*.log"))

if log_candidates:
    newest = max(log_candidates, key=lambda path: path.stat().st_mtime)
    print(str(newest))
else:
    print(str(results_dir / "wrapper" / "run.log"))
PY
}

acquire_node_lock
cd "$MAIN_CHECKOUT"
scripts/runpod_reconcile.sh >/dev/null 2>&1 || true
write_observability_state "setup" "running" "branch cycle acquired node lock"
log_event \
  --event "node_started" \
  --node-id "$NODE_ID" \
  --status "running" \
  --message "branch cycle acquired node lock and began processing"

mkdir -p "$MAIN_CHECKOUT/worktrees"
git worktree add -B "$SCRATCH_REF" "$PLAN_WORKTREE" "tree/$NODE_ID"
cd "$PLAN_WORKTREE"

# ==============================================================================
# PHASE 1: PLAN
# ==============================================================================
announce "=== Phase: plan ==="
CURRENT_PHASE="plan"
ensure_required_upstream_context
ensure_dispatch_feasible
PROMPT="$(build_plan_prompt)"

run_claude_phase "plan" "$PROMPT" "100" "10.00" "$MAIN_CHECKOUT/schemas/plan_schema.json" "$PLAN_OUTPUT_FILE"

cp "$PLAN_OUTPUT_FILE" "$STATE_FILE"

PROPOSED_SLUG=$(jq -r '.structured_output.proposed_slug // empty' "$PLAN_OUTPUT_FILE")
CHANGED_AXES=$(jq -r '.structured_output.changed_axes // empty' "$PLAN_OUTPUT_FILE")

if [ -z "$PROPOSED_SLUG" ] || [ "$PROPOSED_SLUG" == "null" ]; then
  announce "Error: Plan did not output valid proposed_slug."
  exit 1
fi

announce "Proposed slug: $PROPOSED_SLUG"

if ! git check-ref-format "refs/heads/$PROPOSED_SLUG"; then
  announce "Governance Reject: Invalid branch name '$PROPOSED_SLUG'"
  exit 1
fi

# ==============================================================================
# GOVERNANCE: HYBRID NOVELTY CHECK
# ==============================================================================
# The run command array is parsed into a single string for fingerprinting
ARGS_JSON=$(jq -c '.structured_output.run_argv // []' "$PLAN_OUTPUT_FILE")
NEXT_CMD=$(python3 -c "
import sys, json, shlex
try:
    args = json.loads(sys.argv[1])
    print(' '.join(shlex.quote(a) for a in args))
except:
    print('')
" "$ARGS_JSON" || echo "")

FINGERPRINT=$(echo -n "${PROPOSED_SLUG}${CHANGED_AXES}${NEXT_CMD}" | shasum -a 256 | awk '{print $1}')

if [ "$(fingerprint_exists "$FINGERPRINT")" = "true" ]; then
  announce "Governance Reject: Fingerprint '$FINGERPRINT' already exists in registry."
  exit 1
fi

announce "Running Governance LLM Check..."
GOV_PROMPT="You are the Governance Agent. A worker has proposed a new approach:
Slug: $PROPOSED_SLUG
Axes changed: $CHANGED_AXES
Command: $NEXT_CMD

Here is the registry of past runs:
$(tail -n 50 "$NODES_DB" 2>/dev/null || true)

Is this proposed approach a semantic duplicate of a past run? Return JSON."

run_claude_phase "governance" "$GOV_PROMPT" "20" "5.00" "$MAIN_CHECKOUT/schemas/governance_schema.json" "$GOV_OUTPUT_FILE"

IS_DUPLICATE=$(jq -r '.structured_output.is_duplicate // "false"' "$GOV_OUTPUT_FILE")
if [ "$IS_DUPLICATE" == "true" ]; then
  REASON=$(jq -r '.structured_output.reason // "No reason provided"' "$GOV_OUTPUT_FILE")
  announce "Governance Reject: Semantic duplicate detected. Reason: $REASON"
  exit 1
fi

announce "Governance Check Passed. Creating child node..."

# ==============================================================================
# INFRA & EXECUTION: BRANCH, PUSH, JOB DISPATCH
# ==============================================================================
CHILD_NODE_ID="${NODE_ID}_${PROPOSED_SLUG}"
BRANCH_NAME="approach/$CHILD_NODE_ID"
prepare_job_observability
CURRENT_PHASE="prepare_branch"
write_observability_state "prepare_branch" "running" "preparing branch and job artifacts"
log_event \
  --event "branch_preparing" \
  --node-id "$NODE_ID" \
  --job-id "$CHILD_NODE_ID" \
  --branch "$BRANCH_NAME" \
  --status "running" \
  --message "preparing child branch and job artifacts"

git checkout -b "$BRANCH_NAME"
stage_plan_changes
if ! git diff --staged --quiet; then
  git commit -m "chore: auto-commit for $CHILD_NODE_ID (plan phase)"
fi

# Push the branch to origin
announce "Pushing branch $BRANCH_NAME to origin..."
git push origin "$BRANCH_NAME"

COMMIT_SHA=$(git rev-parse HEAD)
CURRENT_PHASE="branch_pushed"
write_observability_state "branch_pushed" "running" "branch pushed to origin"
log_event \
  --event "branch_pushed" \
  --node-id "$NODE_ID" \
  --job-id "$CHILD_NODE_ID" \
  --branch "$BRANCH_NAME" \
  --status "pushed" \
  --message "child branch pushed to origin"

# Write to NODES_DB
if ! append_node_record "running" "1"; then
  rc=$?
  if [ "$rc" -eq 3 ]; then
    announce "Governance Reject: Fingerprint '$FINGERPRINT' already exists in registry."
    exit 1
  fi
  exit "$rc"
fi

# Create Job Spec JSON
JOB_SPEC="$MAIN_CHECKOUT/registry/spool/${CHILD_NODE_ID}_job.json"
if [ "$NO_VALIDATION" -eq 1 ]; then
  announce "No-validation enabled; forcing dispatch onto the 1xH100 non-record lane."
fi
write_job_spec "$JOB_SPEC"
CURRENT_PHASE="job_spec_written"
write_observability_state "job_spec_written" "running" "job spec written for dispatch"

announce "Dispatching job to RunPod..."
cd "$MAIN_CHECKOUT"
CONTROLLER_LOG_LABEL="$BRANCH_NAME" scripts/runpod_dispatch.sh "$JOB_SPEC"
JOB_DISPATCHED=1

SSH_TARGET=$(cat "registry/spool/${CHILD_NODE_ID}_ssh_target.txt" || echo "")
SSH_PORT=$(cat "registry/spool/${CHILD_NODE_ID}_ssh_port.txt" || echo "22")
if [ -z "$SSH_TARGET" ]; then
  announce "Error: SSH target not saved by dispatch."
  exit 1
fi

LEASE_FILE="$MAIN_CHECKOUT/registry/spool/${CHILD_NODE_ID}_lease.json"
CONTROLLER_TTL_EPOCH="$(controller_ttl_epoch "$LEASE_FILE")"
load_lease_metadata
mirror_remote_observability
CURRENT_PHASE="wait_remote"
write_observability_state "wait_remote" "running" "waiting for remote tmux session to complete"

announce "Waiting for remote job to complete on $SSH_TARGET:$SSH_PORT..."
while true; do
  CURRENT_PHASE="wait_remote"
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_TARGET" "tmux has-session -t job_${CHILD_NODE_ID} 2>/dev/null" >/dev/null 2>&1; then
    mirror_remote_observability
    print_new_remote_log_lines
    write_observability_state "wait_remote" "running" "remote tmux session is still active"
  elif ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_TARGET" "true" >/dev/null 2>&1; then
    mirror_remote_observability
    print_new_remote_log_lines
    write_observability_state "wait_remote" "completed" "remote tmux session ended"
    log_event \
      --event "remote_job_completed" \
      --node-id "$NODE_ID" \
      --job-id "$CHILD_NODE_ID" \
      --phase "wait_remote" \
      --branch "$BRANCH_NAME" \
      --status "completed" \
      --message "remote tmux session ended"
    announce "Tmux session ended. Job complete."
    break
  else
    mirror_remote_observability
    print_new_remote_log_lines
    write_observability_state "wait_remote" "degraded" "remote SSH check failed; retrying"
    announce "Remote SSH check failed for $CHILD_NODE_ID; retrying."
  fi

  if [ "$CONTROLLER_TTL_EPOCH" -gt 0 ] && [ "$(date -u +%s)" -ge "$CONTROLLER_TTL_EPOCH" ]; then
    announce "Controller TTL exceeded for $CHILD_NODE_ID. Triggering failure cleanup."
    write_observability_state "wait_remote" "failed" "controller TTL exceeded before remote completion"
    log_event \
      --event "lease_ttl_exceeded" \
      --node-id "$NODE_ID" \
      --job-id "$CHILD_NODE_ID" \
      --phase "wait_remote" \
      --reason "controller_ttl_exceeded" \
      --status "cleanup_pending" \
      --message "branch_cycle controller TTL reached before remote completion"
    if CONTROLLER_LOG_LABEL="$BRANCH_NAME" scripts/runpod_cleanup.sh --job-id "$CHILD_NODE_ID" --reason "controller_ttl_exceeded" >/dev/null 2>&1; then
      POD_CLEANED=1
    fi
    exit 1
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done

CURRENT_PHASE="collect"
write_observability_state "collect" "running" "collecting remote artifacts"
announce "Collecting artifacts from remote..."
if ! CONTROLLER_LOG_LABEL="$BRANCH_NAME" scripts/runpod_collect.sh "$SSH_TARGET" "$SSH_PORT" "$CHILD_NODE_ID"; then
  write_observability_state "collect" "failed" "artifact collection failed"
  if CONTROLLER_LOG_LABEL="$BRANCH_NAME" scripts/runpod_cleanup.sh --job-id "$CHILD_NODE_ID" --reason "collect_failed" >/dev/null 2>&1; then
    POD_CLEANED=1
  fi
  exit 1
fi

write_observability_state "collect" "completed" "artifact collection completed"
CONTROLLER_LOG_LABEL="$BRANCH_NAME" scripts/runpod_cleanup.sh --job-id "$CHILD_NODE_ID" --reason "job_complete"
POD_CLEANED=1
write_observability_state "cleanup" "completed" "pod cleanup completed"

# Clean up final child worktree if we created one, but we don't need local worktree for execution anymore
# The plan worktree is cleaned up by the trap.

# ==============================================================================
# PHASE 2: DIAGNOSE
# ==============================================================================
announce "=== Phase: diagnose ==="
LOG_FILE="$(resolve_diagnose_log "$MAIN_CHECKOUT/experiments/$CHILD_NODE_ID")"

PROMPT="$(build_plan_prompt)
Current Phase: diagnose
The remote experiment has finished. Logs are at $LOG_FILE.
Please analyze the logs and summarize any issues.
Output JSON."

cd "$PLAN_WORKTREE"
run_claude_phase "diagnose" "$PROMPT" "100" "10.00" "$MAIN_CHECKOUT/schemas/diagnose_schema.json" "$DIAGNOSE_OUTPUT_FILE"

# ==============================================================================
# PHASE 3: REFLECT
# ==============================================================================
announce "=== Phase: reflect ==="
PROMPT="$(build_plan_prompt)
Current Phase: reflect
Review the diagnosis and outcome. Determine if this was a success and what to do next.
Output JSON."

run_claude_phase "reflect" "$PROMPT" "50" "5.00" "$MAIN_CHECKOUT/schemas/reflect_schema.json" "$REFLECT_OUTPUT_FILE"

# Update node status based on reflection
ACTION=$(jq -r '.structured_output.recommended_action // "discard"' "$REFLECT_OUTPUT_FILE")
append_node_record "$ACTION" "0"
CURRENT_PHASE="reflect"
write_observability_state "reflect" "completed" "branch cycle finished with action=$ACTION"
log_event \
  --event "reflection_recorded" \
  --node-id "$NODE_ID" \
  --job-id "$CHILD_NODE_ID" \
  --phase "reflect" \
  --branch "$BRANCH_NAME" \
  --status "$ACTION" \
  --message "reflection recorded final recommended action"

announce "Branch cycle complete for $CHILD_NODE_ID. Action determined: $ACTION."
cd "$MAIN_CHECKOUT"
