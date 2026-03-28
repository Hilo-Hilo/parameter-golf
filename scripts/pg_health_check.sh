#!/usr/bin/env bash
# scripts/pg_health_check.sh
# Automated health check and self-healing for the parameter-golf swarm.
# Detects anomalies, wastes GPU resources, and fixes what it can.
# Exit codes: 0=healthy, 1=anomalies found (some may have been auto-fixed), 2=fatal error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
SPOOL="$REPO_ROOT/registry/spool"
NODES_DB="$REPO_ROOT/registry/nodes.jsonl"
LOG="$REPO_ROOT/logs/health_monitor.log"
SHADEFORM_API_KEY="${SHADEFORM_API_KEY:-$(cat ~/.shadeform/api_key 2>/dev/null | tr -d '[:space:]' || echo '')}"
SHADEFORM_API="https://api.shadeform.ai/v1"
MAX_JOB_AGE_MINUTES=18

mkdir -p "$REPO_ROOT/logs"
ANOMALIES=0
FIXES=0

ts()      { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
hr()      { printf '%0.s-' {1..70}; echo; }
log()     { printf '[%s][health] %s\n' "$(ts)" "$*" | tee -a "$LOG"; }
anomaly() { log "ANOMALY: $*"; ANOMALIES=$((ANOMALIES + 1)); }
fixed()   { log "FIXED:   $*";   FIXES=$((FIXES + 1)); }
info()    { log "INFO:    $*"; }

echo
hr
printf '[%s] PARAMETER GOLF HEALTH CHECK\n' "$(ts)"
hr

# ---------------------------------------------------------------------------
# 1. Tmux session health
# ---------------------------------------------------------------------------
info "Checking tmux sessions..."

if ! tmux has-session -t pg-swarm 2>/dev/null; then
  anomaly "pg-swarm tmux session is missing."
  bash "$SCRIPT_DIR/swarm_guardian.sh" >/dev/null 2>&1 && fixed "Relaunched pg-swarm via guardian."
elif ! pgrep -f "start_swarm" >/dev/null 2>&1; then
  anomaly "pg-swarm session exists but start_swarm.sh is not running."
  bash "$SCRIPT_DIR/swarm_guardian.sh" >/dev/null 2>&1 && fixed "Relaunched swarm process via guardian."
else
  info "pg-swarm: healthy."
fi

if ! tmux has-session -t pg-monitor 2>/dev/null; then
  anomaly "pg-monitor tmux session is missing."
  bash "$SCRIPT_DIR/swarm_guardian.sh" >/dev/null 2>&1 && fixed "Relaunched pg-monitor via guardian."
else
  info "pg-monitor: session present."
fi

# ---------------------------------------------------------------------------
# 2. Shadeform instances vs active leases
# ---------------------------------------------------------------------------
info "Checking Shadeform instances..."

if [ -z "$SHADEFORM_API_KEY" ]; then
  info "No Shadeform API key — skipping instance check."
else
  INSTANCES_JSON="$(curl -s -H "X-API-KEY: $SHADEFORM_API_KEY" "$SHADEFORM_API/instances" 2>/dev/null || echo '{}')"
  N_INSTANCES="$(printf '%s' "$INSTANCES_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('instances',[])))" 2>/dev/null || echo 0)"
  info "Active Shadeform instances: $N_INSTANCES"

  # Write to temp file so Python can read it without heredoc stdin conflict
  _INST_TMP="$(mktemp)"
  printf '%s\n' "$INSTANCES_JSON" > "$_INST_TMP"
  NOW_EPOCH="$(date -u +%s)"

  while IFS= read -r _line; do
    anomaly "$_line"
  done < <(python3 - "$SPOOL" "$MAX_JOB_AGE_MINUTES" "$NOW_EPOCH" "$_INST_TMP" <<'PY'
import json, pathlib, sys
from datetime import datetime, timezone

spool = pathlib.Path(sys.argv[1])
max_age_min = int(sys.argv[2])
now_epoch = int(sys.argv[3])
inst_file = sys.argv[4]

try:
    instances = json.loads(open(inst_file).read()).get("instances", [])
except Exception as e:
    print(f"WARNING: could not parse instances JSON: {e}", file=sys.stderr)
    sys.exit(0)

active_instances = [i for i in instances if i.get("status") in ("active", "pending")]

leased_instance_ids = set()
for lf in spool.glob("*_lease.json"):
    try:
        d = json.loads(lf.read_text())
    except Exception:
        continue
    if d.get("cleanup", {}).get("released_at"):
        continue
    inst_id = d.get("instance_id") or d.get("pod_id")
    if inst_id:
        leased_instance_ids.add(inst_id)

for inst in active_instances:
    iid = inst["id"]
    name = inst.get("name", "?")
    if iid not in leased_instance_ids:
        print(f"Shadeform instance {iid} ({name}) is active but has no unreleased lease — potential GPU waste.")
    # Only flag age if also has no active lease (leased instances are in use)
    if iid not in leased_instance_ids:
        created = inst.get("created_at") or inst.get("createdAt") or ""
        if created:
            try:
                if created.endswith("Z"):
                    created = created[:-1] + "+00:00"
                dt = datetime.fromisoformat(created)
                age_min = (now_epoch - int(dt.timestamp())) // 60
                if age_min > max_age_min:
                    print(f"Instance {iid} ({name}) has been running for {age_min}min — may be stuck or completed without cleanup.")
            except Exception:
                pass
PY
)
  rm -f "$_INST_TMP"
fi

# ---------------------------------------------------------------------------
# 3. Stale running nodes in nodes.jsonl
# ---------------------------------------------------------------------------
info "Checking nodes.jsonl for stale entries..."

STALE_NODES="$(python3 - "$NODES_DB" <<'PY'
import json, pathlib, subprocess, re, sys

db_path = pathlib.Path(sys.argv[1])
if not db_path.exists():
    sys.exit(0)

ps_out = subprocess.check_output(["ps", "-axo", "command"], text=True)

for raw in db_path.read_text().splitlines():
    raw = raw.strip()
    if not raw:
        continue
    try:
        r = json.loads(raw)
    except Exception:
        continue
    if r.get("status") != "running":
        continue
    nid = r.get("node_id", "")
    pattern = re.compile(rf"scripts/branch_cycle\.sh(?:\s+--no-validation)?\s+{re.escape(nid)}(?:\s|$)")
    if not pattern.search(ps_out):
        print(nid)
PY
)"

if [ -n "$STALE_NODES" ]; then
  while IFS= read -r nid; do
    [ -z "$nid" ] && continue
    anomaly "Node $nid is marked 'running' but branch_cycle.sh is not alive — stale entry."
    python3 - "$NODES_DB" "$nid" <<'PY' 2>/dev/null && fixed "Recovered stale node $nid to pending."
import json, pathlib, sys, tempfile, os
db_path = pathlib.Path(sys.argv[1])
nid = sys.argv[2]
rows = []
for raw in db_path.read_text().splitlines():
    raw = raw.strip()
    if not raw:
        continue
    try:
        r = json.loads(raw)
    except Exception:
        continue
    if r.get("node_id") == nid and r.get("status") == "running":
        r["status"] = "pending"
    rows.append(r)
fd, tmp = tempfile.mkstemp(dir=str(db_path.parent), prefix=".nodes.", text=True)
try:
    with os.fdopen(fd, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    os.replace(tmp, db_path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY
  done <<< "$STALE_NODES"
else
  info "No stale running nodes."
fi

# ---------------------------------------------------------------------------
# 4. Recent results: byte cap and regression checks
# ---------------------------------------------------------------------------
info "Checking recent spool results..."

while IFS= read -r _line; do
  anomaly "$_line"
done < <(python3 - "$SPOOL" <<'PY'
import json, pathlib, sys, time

spool = pathlib.Path(sys.argv[1])
rows = []
for f in spool.glob("*.json"):
    if any(x in f.name for x in ("_lease", "_state", "_pod_id", "_ssh_port", "_ssh_target", "_job")):
        continue
    try:
        d = json.loads(f.read_text())
    except Exception:
        continue
    bpb = d.get("exact_final_val_bpb") or d.get("val_bpb")
    if bpb is None:
        continue
    rows.append((f.stat().st_mtime, d.get("job_id", f.stem), bpb, d.get("bytes_total"), d.get("status")))

rows.sort(reverse=True)
for mtime, job_id, bpb, bt, status in rows[:5]:
    age_min = (time.time() - mtime) / 60
    if age_min > 60:
        break
    if isinstance(bt, int) and bt > 16_000_000:
        print(f"BYTE CAP BREACH: job={job_id} bytes={bt:,} (over 16MB) status={status}")
    if bpb is not None and bpb > 1.25:
        print(f"REGRESSION: job={job_id} bpb={bpb:.4f} (>1.25, well above SOTA 1.1194) status={status}")
PY
)

# ---------------------------------------------------------------------------
# 5. Swarm log tail — crash/error scan
# ---------------------------------------------------------------------------
info "Scanning swarm log for errors..."

if [ -f "$REPO_ROOT/logs/swarm.log" ]; then
  ERROR_LINES="$(tail -200 "$REPO_ROOT/logs/swarm.log" | grep -iE "\berror\b|\bfatal\b|Traceback|Exception:|SIGKILL|Out of memory|OOM|pod.*killed|job.*failed" | grep -vE "Governance (Reject|Accept)|dispatch error|governance" | tail -5 || true)"
  if [ -n "$ERROR_LINES" ]; then
    anomaly "Recent errors in swarm.log (see below for details)."
    while IFS= read -r eline; do
      log "  >> $eline"
    done <<< "$ERROR_LINES"
  else
    info "swarm.log: no recent errors."
  fi
fi

# ---------------------------------------------------------------------------
# 6. Orphaned leases (result file exists but lease not released)
# ---------------------------------------------------------------------------
info "Checking for orphaned leases..."

while IFS= read -r _line; do
  anomaly "$_line"
done < <(python3 - "$SPOOL" "$NODES_DB" <<'PY'
import json, pathlib, sys

spool = pathlib.Path(sys.argv[1])
nodes_db = pathlib.Path(sys.argv[2])

done_nodes = set()
if nodes_db.exists():
    for raw in nodes_db.read_text().splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            r = json.loads(raw)
        except Exception:
            continue
        if r.get("status") in ("completed", "discarded", "failed"):
            done_nodes.add(r.get("node_id", ""))

for lf in spool.glob("*_lease.json"):
    try:
        d = json.loads(lf.read_text())
    except Exception:
        continue
    if d.get("cleanup", {}).get("released_at"):
        continue
    job_id = d.get("job_id", lf.stem.replace("_lease", ""))
    result_file = spool / f"{job_id}.json"
    if result_file.exists():
        try:
            res = json.loads(result_file.read_text())
            if res.get("exact_final_val_bpb") or res.get("val_bpb"):
                print(f"Orphaned lease: {job_id} has a result file but lease is not released.")
        except Exception:
            pass
PY
)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
hr
printf '[%s] HEALTH CHECK COMPLETE — anomalies=%d  auto-fixed=%d\n' "$(ts)" "$ANOMALIES" "$FIXES"
hr
echo

if [ "$ANOMALIES" -gt 0 ]; then
  exit 1
else
  exit 0
fi
