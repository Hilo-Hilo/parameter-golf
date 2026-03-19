#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/run_experiment.sh --name NAME [options] -- command ...

Options:
  --name NAME           Human-readable experiment label. Required.
  --track LABEL         Track label recorded in results.tsv. Default: local
  --trainer PATH        Trainer path or label. Default: train_gpt.py
  --status STATUS       Requested status for successful valid runs: keep|discard|invalid|crash
  --notes TEXT          Short free-form note.
  --submission PATH     Optional submission.json to merge into parsed metrics.
  --results PATH        Results TSV path. Default: results/results.tsv
  --log-dir PATH        Log directory. Default: logs/experiments
  --code-path PATH      Path used to compute code bytes. Default: same as --trainer
EOF
}

name=""
track="local"
trainer="train_gpt.py"
status="discard"
notes=""
submission=""
results_tsv="results/results.tsv"
log_dir="logs/experiments"
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
    --submission)
      submission="${2:-}"
      shift 2
      ;;
    --results)
      results_tsv="${2:-}"
      shift 2
      ;;
    --log-dir)
      log_dir="${2:-}"
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

resolve_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$repo_root" "$1" ;;
  esac
}

code_path="${code_path:-$trainer}"
resolved_log_dir=$(resolve_path "$log_dir")
resolved_results_tsv=$(resolve_path "$results_tsv")
resolved_code_path=$(resolve_path "$code_path")
resolved_submission=""
if [[ -n "$submission" ]]; then
  resolved_submission=$(resolve_path "$submission")
fi

mkdir -p "$resolved_log_dir" "$(dirname "$resolved_results_tsv")"

log_path="$resolved_log_dir/$experiment_id.log"
meta_path="$resolved_log_dir/$experiment_id.meta"
summary_path="$resolved_log_dir/$experiment_id.json"

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

set +e
(
  cd "$repo_root"
  RUN_ID="$run_id" "$@"
) >"$log_path" 2>&1
exit_code=$?
set -e

printf 'exit_code=%s\n' "$exit_code" >>"$meta_path"

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
  --notes "$notes" \
  --format json >"$summary_path"

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
  --notes "$notes" \
  --format tsv >>"$resolved_results_tsv"

printf 'log=%s\nsummary=%s\nresults=%s\n' "$log_path" "$summary_path" "$resolved_results_tsv"
exit "$exit_code"
