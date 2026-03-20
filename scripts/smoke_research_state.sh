#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
RESEARCH_STATE_FILE="$TMP_DIR/automation/state/research_state.json"
WORKER_STATE_FILE="$TMP_DIR/automation/state/continuous_worker.json"
JOURNAL_FILE="$TMP_DIR/journal.md"
RESULTS_FILE="$TMP_DIR/results/results.tsv"
LOG_FILE="$TMP_DIR/automation/logs/continuous_worker.log"

mkdir -p "$TMP_DIR/automation/state" "$TMP_DIR/automation/logs" "$TMP_DIR/results"

cat > "$JOURNAL_FILE" <<'EOF'
# Smoke journal

## 2026-03-20 — smoke
- Hypothesis: one-axis smoke run to validate reconciliation and dedupe state.
EOF

cat > "$RESULTS_FILE" <<'EOF'
ts_utc	experiment_id	run_id	track	trainer	branch	commit	status	exit_code	exact_final_val_bpb	pre_quant_val_bpb	final_val_loss	pre_quant_val_loss	bytes_total	bytes_code	bytes_model	wallclock_seconds	step_stop	log_path	submission_path	notes
2026-03-20T00:00:00Z	20260320T000000Z_smoke_run	20260320T000000Z_smoke_run	mac-smoke	train_gpt_mlx.py	research/continuous-mar18	deadbeef	keep	0	2.5000	2.4000	0	0	1234	0	1234	10		foo.log		Hypothesis: smoke-run
EOF

cat > "$WORKER_STATE_FILE" <<'EOF'
{
  "branch": "research/continuous-mar18",
  "logFile": "/tmp/research_state_smoke.log",
  "owner": {
    "channel": "telegram",
    "accountId": "clawd4",
    "to": "8173956648"
  },
  "pid": 999999999,
  "repoRoot": "/tmp/does-not-matter",
  "status": "running"
}
EOF

printf '[smoke] bootstrapping state\n'
python3 "$REPO_ROOT/scripts/research_state.py" bootstrap \
  --repo-root "$TMP_DIR" \
  --research-state-file "$RESEARCH_STATE_FILE" \
  --worker-state-file "$WORKER_STATE_FILE" \
  --journal-file "$JOURNAL_FILE" \
  --results-file "$RESULTS_FILE" \
  --branch "research/continuous-mar18" \
  --log-file "$LOG_FILE" \
  --worker-pid 999999999 \
  --now "$NOW" >/dev/null

printf '[smoke] reconcile\n'
python3 "$REPO_ROOT/scripts/research_state.py" reconcile \
  --repo-root "$TMP_DIR" \
  --research-state-file "$RESEARCH_STATE_FILE" \
  --worker-state-file "$WORKER_STATE_FILE" \
  --journal-file "$JOURNAL_FILE" \
  --results-file "$RESULTS_FILE"

printf '[smoke] mark stop\n'
python3 "$REPO_ROOT/scripts/research_state.py" mark-stop \
  --repo-root "$TMP_DIR" \
  --research-state-file "$RESEARCH_STATE_FILE" \
  --reason "smoke-stop"

printf '[smoke] inspect state file\n'
cat "$RESEARCH_STATE_FILE"
