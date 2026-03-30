#!/usr/bin/env bash
# scripts/swarm_monitor.sh
# Prints a compact swarm status snapshot. Safe to run at any time.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)"
SHADEFORM_API_KEY="${SHADEFORM_API_KEY:-$(cat ~/.shadeform/api_key 2>/dev/null | tr -d '[:space:]' || echo '')}"
SHADEFORM_API="https://api.shadeform.ai/v1"

hr() { printf '%0.s-' {1..70}; echo; }
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

echo
hr
printf '[%s] PARAMETER GOLF SWARM STATUS\n' "$(ts)"
hr

# --- Nodes queue ---
echo
echo "NODES QUEUE (registry/nodes.jsonl):"
if [ -f "$REPO_ROOT/registry/nodes.jsonl" ]; then
  python3 - "$REPO_ROOT/registry/nodes.jsonl" <<'PY'
import json, sys, collections
path = sys.argv[1]
counts = collections.Counter()
rows = []
for line in open(path):
    line = line.strip()
    if not line: continue
    try: r = json.loads(line)
    except: continue
    counts[r.get("status","?")] += 1
    rows.append(r)
print(f"  total={len(rows)}  " + "  ".join(f"{s}={c}" for s, c in sorted(counts.items())))
# Show last 5 running/pending
active = [r for r in rows if r.get("status") in ("running","pending")][-5:]
for r in active:
    print(f"  [{r.get('status','?'):8s}] {r.get('node_id','?')}")
PY
else
  echo "  (not found)"
fi

# --- Active Shadeform instances ---
echo
echo "SHADEFORM INSTANCES:"
if [ -n "$SHADEFORM_API_KEY" ]; then
  curl -s -H "X-API-KEY: $SHADEFORM_API_KEY" "$SHADEFORM_API/instances" 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
insts = d.get('instances', [])
if not insts:
    print('  (none)')
else:
    for i in insts:
        print(f\"  [{i.get('status','?'):10s}] {i.get('shade_instance_type','?'):8s}  {i.get('name','?')}\")
" 2>/dev/null || echo "  (API error)"
else
  echo "  (no API key)"
fi

# --- Unreleased leases ---
echo
echo "ACTIVE LEASES:"
python3 - "$REPO_ROOT/registry/spool" <<'PY'
import json, pathlib, sys
spool = pathlib.Path(sys.argv[1])
found = 0
for lf in sorted(spool.glob("*_lease.json")):
    try: d = json.loads(lf.read_text())
    except: continue
    if d.get("cleanup", {}).get("released_at"): continue
    job_id = d.get("job_id", lf.stem.replace("_lease",""))
    backend = d.get("backend","?")
    status = d.get("status","?")
    print(f"  {backend:10s}  {job_id}")
    found += 1
if not found:
    print("  (none)")
PY

# --- Recent results from spool ---
echo
echo "RECENT RESULTS (spool *.json, last 8 with bpb):"
python3 - "$REPO_ROOT/registry/spool" <<'PY'
import json, pathlib, sys
spool = pathlib.Path(sys.argv[1])
rows = []
for f in spool.glob("*.json"):
    if "_lease" in f.name or "_state" in f.name or "_pod_id" in f.name \
       or "_ssh_port" in f.name or "_ssh_target" in f.name or "_job" in f.name:
        continue
    try: d = json.loads(f.read_text())
    except: continue
    bpb = d.get("exact_final_val_bpb") or d.get("val_bpb")
    if bpb is None: continue
    rows.append((f.stat().st_mtime, d.get("job_id", f.stem), bpb,
                 d.get("bytes_total","?"), d.get("status","?")))
rows.sort(reverse=True)
if not rows:
    print("  (none)")
for _, job_id, bpb, bt, status in rows[:8]:
    cap = " OVER" if isinstance(bt, int) and bt > 16_000_000 else ""
    print(f"  {bpb:.4f} bpb  {str(bt):>10s} bytes{cap:5s}  [{status:12s}]  {job_id}")
PY

# --- Phase log recent activity ---
echo
echo "RECENT PHASE ACTIVITY (last 5 phase log dirs):"
if [ -d "$REPO_ROOT/registry/phase_logs" ]; then
  ls -td "$REPO_ROOT/registry/phase_logs"/*/* 2>/dev/null | head -5 | while read -r d; do
    node=$(basename "$(dirname "$d")")
    scratch=$(basename "$d")
    latest_phase=""
    latest_time=0
    for f in "$d"/*.output.json; do
      [ -f "$f" ] || continue
      mt=$(python3 -c "import os; print(int(os.path.getmtime('$f')))" 2>/dev/null || echo 0)
      if [ "$mt" -gt "$latest_time" ]; then
        latest_time=$mt
        latest_phase=$(basename "$f" .output.json)
      fi
    done
    age_min=$(( ( $(date -u +%s) - latest_time ) / 60 ))
    printf "  %-30s  phase=%-10s  %dmin ago\n" "$node/$scratch" "$latest_phase" "$age_min"
  done
else
  echo "  (no phase logs yet)"
fi

# --- Reconcile log tail ---
echo
echo "RECONCILE LOG (last 5 lines):"
if [ -f "$REPO_ROOT/logs/shadeform-reconcile.log" ]; then
  tail -5 "$REPO_ROOT/logs/shadeform-reconcile.log" | sed 's/^/  /'
else
  echo "  (no log yet)"
fi

echo
hr
