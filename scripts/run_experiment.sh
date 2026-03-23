#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/run_experiment.sh --name NAME [options] -- command ...

Options:
  --name NAME           Human-readable experiment label. Required.
  --track LABEL         Track label recorded. Default: local
  --trainer PATH        Trainer path or label. Default: train_gpt.py
  --status STATUS       Requested status for successful valid runs: keep|discard|invalid|crash
  --notes TEXT          Short free-form note.
  --eval-stride N       Override EVAL_STRIDE env var for train_gpt.py.
  --eval-batch-seqs N   Override EVAL_BATCH_SEQS env var for train_gpt.py.
  --eval-seq-len N      Override EVAL_SEQ_LEN env var for train_gpt.py.
  --muon-weight-decay N Override MUON_WEIGHT_DECAY env var for train_gpt.py.
  --submission PATH     Optional submission.json to merge into parsed metrics.
  --code-path PATH      Path used to compute code bytes. Default: same as --trainer
EOF
}

name=""
track="local"
trainer="train_gpt.py"
status="discard"
notes=""
eval_stride=""
eval_batch_seqs=""
eval_seq_len=""
muon_weight_decay=""
submission=""
code_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      name="${2:-}"
      shift 2
      ;;
    --track)
      track="${2:-}"
      shift 2
      ;;
    --trainer)
      trainer="${2:-}"
      shift 2
      ;;
    --status)
      status="${2:-}"
      shift 2
      ;;
    --notes)
      notes="${2:-}"
      shift 2
      ;;
    --eval-stride)
      eval_stride="${2:-}"
      shift 2
      ;;
    --eval-batch-seqs)
      eval_batch_seqs="${2:-}"
      shift 2
      ;;
    --eval-seq-len)
      eval_seq_len="${2:-}"
      shift 2
      ;;
    --muon-weight-decay)
      muon_weight_decay="${2:-}"
      shift 2
      ;;
    --submission)
      submission="${2:-}"
      shift 2
      ;;
    --code-path)
      code_path="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      printf 'unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$name" ]]; then
  printf 'missing required --name\n' >&2
  usage >&2
  exit 2
fi

if [[ $# -eq 0 ]]; then
  printf 'missing command after --\n' >&2
  usage >&2
  exit 2
fi

case "$status" in
  keep|discard|invalid|crash) ;;
  *)
    printf 'invalid --status: %s\n' "$status" >&2
    exit 2
    ;;
esac

repo_root=$(git rev-parse --show-toplevel)
branch=$(git -C "$repo_root" branch --show-current)
commit=$(git -C "$repo_root" rev-parse HEAD)
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
stamp_compact=$(date -u +"%Y%m%dT%H%M%SZ")
safe_name=$(printf '%s' "$name" | tr -cs 'A-Za-z0-9._-' '_')
experiment_id="${stamp_compact}_${safe_name}"
run_id="${RUN_ID:-$experiment_id}"
venv_bin="$repo_root/.venv/bin"

resolve_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$repo_root" "$1" ;;
  esac
}

code_path="${code_path:-$trainer}"
resolved_code_path=$(resolve_path "$code_path")
resolved_submission=""
if [[ -n "$submission" ]]; then
  resolved_submission=$(resolve_path "$submission")
fi

experiment_dir="$repo_root/experiments/$run_id"
mkdir -p "$experiment_dir"
mkdir -p "$repo_root/registry/spool"

log_path="$experiment_dir/$experiment_id.log"
meta_path="$experiment_dir/$experiment_id.meta"
summary_path="$experiment_dir/$experiment_id.json"
spool_path="$repo_root/registry/spool/${run_id}.json"

git -C "$repo_root" diff > "$experiment_dir/dirty.patch"
env > "$experiment_dir/env.txt"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi -L > "$experiment_dir/nvidia_smi.txt" || true
fi

wallclock_now() {
  python3 - <<'PY'
import time
print(f"{time.time():.6f}")
PY
}

printf -v command_str '%q ' "$@"
command_str="${command_str% }"

{
  printf 'ts_utc=%s\n' "$timestamp"
  printf 'experiment_id=%s\n' "$experiment_id"
  printf 'run_id=%s\n' "$run_id"
  printf 'track=%s\n' "$track"
  printf 'trainer=%s\n' "$trainer"
  printf 'branch=%s\n' "$branch"
  printf 'commit=%s\n' "$commit"
  printf 'status_requested=%s\n' "$status"
  printf 'submission=%s\n' "$resolved_submission"
  printf 'code_path=%s\n' "$resolved_code_path"
  printf 'log_path=%s\n' "$log_path"
  printf 'command=%s\n' "$command_str"
  printf 'notes=%s\n' "$notes"
} >"$meta_path"

wallclock_start=$(wallclock_now)
set +e
(
  cd "$repo_root"
  if [[ -d "$venv_bin" ]]; then
    export PATH="$venv_bin:$PATH"
  fi
  if [[ -n "$eval_stride" ]]; then
    export EVAL_STRIDE="$eval_stride"
  fi
  if [[ -n "$eval_batch_seqs" ]]; then
    export EVAL_BATCH_SEQS="$eval_batch_seqs"
  fi
  if [[ -n "$eval_seq_len" ]]; then
    export EVAL_SEQ_LEN="$eval_seq_len"
  fi
  if [[ -n "$muon_weight_decay" ]]; then
    export MUON_WEIGHT_DECAY="$muon_weight_decay"
  fi
  export OUTPUT_DIR="$experiment_dir"
  RUN_ID="$run_id" PYTHONUNBUFFERED=1 "$@"
) >"$log_path" 2>&1
exit_code=$?
set -e
wallclock_end=$(wallclock_now)
process_wallclock_seconds=$(python3 - "$wallclock_start" "$wallclock_end" <<'PY'
import sys
start = float(sys.argv[1])
end = float(sys.argv[2])
print(f"{max(end - start, 0.0):.6f}")
PY
)

printf 'exit_code=%s\n' "$exit_code" >>"$meta_path"
printf 'process_wallclock_seconds=%s\n' "$process_wallclock_seconds" >>"$meta_path"

python3 "$repo_root/scripts/parse_train_log.py" \
  "$log_path" \
  --submission "$resolved_submission" \
  --code-path "$resolved_code_path" \
  --ts-utc "$timestamp" \
  --experiment-id "$experiment_id" \
  --run-id "$run_id" \
  --track "$track" \
  --trainer "$trainer" \
  --branch "$branch" \
  --commit "$commit" \
  --status "$status" \
  --exit-code "$exit_code" \
  --process-wallclock-seconds "$process_wallclock_seconds" \
  --notes "$notes" \
  --format json >"$summary_path"

cp "$summary_path" "$spool_path"

printf 'log=%s\nsummary=%s\nspool=%s\n' "$log_path" "$summary_path" "$spool_path"
exit "$exit_code"
