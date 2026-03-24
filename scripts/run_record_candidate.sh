#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <name> [--3seed] [extra_run_experiment_args...]" >&2
  exit 1
fi

NAME="$1"
shift

SEEDS=(1)
PROFILE="candidate_h100x8"

if [ "${1:-}" == "--3seed" ]; then
  SEEDS=(1 2 3)
  PROFILE="record_h100x8_3seed"
  shift
fi

for SEED in "${SEEDS[@]}"; do
  RUN_NAME="${NAME}_seed${SEED}"
  echo "Queueing record candidate: $RUN_NAME with profile $PROFILE"
  
  # Delegate to the remote dispatcher by generating a job
  scripts/push_branch_for_job.sh "$(git branch --show-current)" "$RUN_NAME" "$PROFILE"

  # The actual run_experiment.sh invocation that the pod will run:
  # This uses the wrapper with strict constraints
  cat <<EOF > registry/queue/${RUN_NAME}_cmd.sh
#!/usr/bin/env bash
scripts/run_experiment.sh \\
  --name "$RUN_NAME" \\
  --track record_h100x8 \\
  --trainer train_gpt.py \\
  --required-gpu-count 8 \\
  --required-gpu-substring H100 \\
  --outer-timeout-seconds 660 \\
  "\$@" -- \\
  env MAX_WALLCLOCK_SECONDS=600 \\
      DATA_PATH=/workspace/data/datasets \\
      TOKENIZER_PATH=/workspace/data/tokenizers \\
      PYTHONHASHSEED=$SEED \\
      torchrun --standalone --nproc_per_node=8 train_gpt.py
EOF
  chmod +x registry/queue/${RUN_NAME}_cmd.sh
done
