# Scripts

Experiment helpers and worker lifecycle for this repo.

## Files

- `scripts/run_experiment.sh`: launch one run, capture a log, parse metrics, isolate output under `experiments/<run_id>`, and append a JSON summary to `registry/runs.jsonl`
- `scripts/parse_train_log.py`: stdlib-only parser for `train.log` plus optional `submission.json`
- `scripts/branch_cycle.sh`: deterministic, phase-bounded 3-step Claude session (`plan`, `diagnose`, `reflect`) in an isolated Git worktree
- `scripts/smoke_sliding_eval.py`: CUDA smoke test for sliding-window eval path

## Worker Lifecycle

Start an autonomous worker cycle for a specific branch node:

```bash
scripts/branch_cycle.sh <node_id>
```

This runs a deterministic, phase-bounded 3-step Claude session (`plan`, `diagnose`, `reflect`) in an isolated Git worktree (`worktrees/<node_id>`). It enforces `--no-session-persistence` and strict `.claude/settings.json` permissions to keep runs concurrency-safe and side-effect free.

## Typical Usage

PyTorch run:

```bash
scripts/run_experiment.sh \
  --name baseline_1gpu_smoke \
  --track local-smoke \
  --trainer train_gpt.py \
  --notes "1 GPU smoke with short wallclock" \
  -- \
  env RUN_ID=baseline_sp1024 \
      MAX_WALLCLOCK_SECONDS=30 \
      torchrun --standalone --nproc_per_node=1 train_gpt.py
```

MLX local run:

```bash
scripts/run_experiment.sh \
  --name mlx_smoke \
  --track mac-smoke \
  --trainer train_gpt_mlx.py \
  --notes "short local sanity run" \
  -- \
  env ITERATIONS=200 TRAIN_BATCH_TOKENS=8192 VAL_LOSS_EVERY=0 VAL_BATCH_SIZE=8192 python3 train_gpt_mlx.py
```

## Notes

- The experiment wrapper defaults successful runs to `discard`. Pass `--status keep` only when you already know the run should be retained.
- If the command exits non-zero, the row is recorded as `crash`.
- If the exact final roundtrip metric is missing, or the artifact exceeds `16,000,000` bytes, the row is recorded as `invalid`.
- `submission.json` is optional. When provided, parser fields from the JSON take precedence over log-derived values.