#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <name> [--3seed] [--no-validation] [extra_run_experiment_args...]" >&2
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

NAME="$1"
shift

SEEDS=(1)
PROFILE_LABEL="candidate_h100x8"
TRACK_LABEL="record_h100x8"
GPU_COUNT=8
GPU_TYPE="H100"
OUTER_TIMEOUT_SECONDS=660
NPROC_PER_NODE=8
NO_VALIDATION=0
EXTRA_RUN_EXPERIMENT_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --3seed)
      SEEDS=(1 2 3)
      PROFILE_LABEL="record_h100x8_3seed"
      shift
      ;;
    --no-validation)
      NO_VALIDATION=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      EXTRA_RUN_EXPERIMENT_ARGS+=("$@")
      break
      ;;
    *)
      EXTRA_RUN_EXPERIMENT_ARGS+=("$1")
      shift
      ;;
  esac
done

if [ "$NO_VALIDATION" -eq 1 ]; then
  PROFILE_LABEL="non_record_h100x1"
  TRACK_LABEL="non_record_h100x1"
  GPU_COUNT=1
  OUTER_TIMEOUT_SECONDS=3600
  NPROC_PER_NODE=1
  if [ "${#SEEDS[@]}" -gt 1 ]; then
    PROFILE_LABEL="non_record_h100x1_3seed"
  fi
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
MAIN_CHECKOUT="$(cd "$(git -C "$REPO_ROOT" rev-parse --git-common-dir)/.." && pwd)"
QUEUE_DIR="$MAIN_CHECKOUT/registry/queue"
CURRENT_BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"
DATASET_PATH="/workspace/parameter-golf/data/datasets/fineweb10B_sp1024"
TOKENIZER_PATH="/workspace/parameter-golf/data/tokenizers/fineweb_1024_bpe.model"
mkdir -p "$QUEUE_DIR"

EXTRA_RUN_EXPERIMENT_LINES=""
if [ "${#EXTRA_RUN_EXPERIMENT_ARGS[@]}" -gt 0 ]; then
  for arg in "${EXTRA_RUN_EXPERIMENT_ARGS[@]}"; do
    printf -v EXTRA_RUN_EXPERIMENT_LINES '%s  %q \\\n' "$EXTRA_RUN_EXPERIMENT_LINES" "$arg"
  done
fi

for SEED in "${SEEDS[@]}"; do
  RUN_NAME="${NAME}_seed${SEED}"
  echo "Queueing candidate helper run: $RUN_NAME with profile $PROFILE_LABEL"

  scripts/push_branch_for_job.sh "$CURRENT_BRANCH" "$RUN_NAME" "$PROFILE_LABEL"

  COMMIT_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  JOB_SPEC="$QUEUE_DIR/${RUN_NAME}.json"

  # Overwrite the legacy queue entry with the object-shaped job spec used by runpod_dispatch.sh.
  jq -n \
    --arg job_id "$RUN_NAME" \
    --arg branch "$CURRENT_BRANCH" \
    --arg commit_sha "$COMMIT_SHA" \
    --arg track "$TRACK_LABEL" \
    --arg gpu_type "$GPU_TYPE" \
    --arg seed "$SEED" \
    --arg nproc "--nproc_per_node=${NPROC_PER_NODE}" \
    --argjson gpu_count "$GPU_COUNT" \
    '{
      job_id: $job_id,
      branch: $branch,
      commit_sha: $commit_sha,
      resource_profile: {
        gpu_count: $gpu_count,
        gpu_type: $gpu_type
      },
      run_argv: ["torchrun", "--standalone", $nproc, "train_gpt.py"],
      env_overrides: {
        MAX_WALLCLOCK_SECONDS: "600",
        DATA_PATH: "/workspace/parameter-golf/data/datasets/fineweb10B_sp1024",
        TOKENIZER_PATH: "/workspace/parameter-golf/data/tokenizers/fineweb_1024_bpe.model",
        PYTHONHASHSEED: $seed
      },
      expected_track: $track,
      success_criteria: "complete the helper run on the requested lane without skipping final evaluation"
    }' > "$JOB_SPEC"

  cat <<EOF > "$QUEUE_DIR/${RUN_NAME}_cmd.sh"
#!/usr/bin/env bash
scripts/run_experiment.sh \\
  --name "$RUN_NAME" \\
  --track "$TRACK_LABEL" \\
  --trainer train_gpt.py \\
  --required-gpu-count $GPU_COUNT \\
  --required-gpu-substring $GPU_TYPE \\
  --outer-timeout-seconds $OUTER_TIMEOUT_SECONDS \\
$EXTRA_RUN_EXPERIMENT_LINES  "\$@" -- \\
  env MAX_WALLCLOCK_SECONDS=600 \\
      DATA_PATH=$DATASET_PATH \\
      TOKENIZER_PATH=$TOKENIZER_PATH \\
      PYTHONHASHSEED=$SEED \\
      torchrun --standalone --nproc_per_node=$NPROC_PER_NODE train_gpt.py
EOF
  chmod +x "$QUEUE_DIR/${RUN_NAME}_cmd.sh"
done
