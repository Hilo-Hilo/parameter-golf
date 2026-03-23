# Scripts

Experiment helpers and worker lifecycle for this repo.

## Files

- `scripts/run_experiment.sh`: launch one run, capture a log, parse metrics, append one TSV row
- `scripts/parse_train_log.py`: stdlib-only parser for `train.log` plus optional `submission.json`
- `scripts/start_worker.sh`: launch the detached Claude Code research worker
- `scripts/stop_worker.sh`: stop the worker
- `scripts/worker_status.sh`: check if the worker is running
- `scripts/smoke_sliding_eval.py`: CUDA smoke test for sliding-window eval path

## Worker

`worker_program.md` is the canonical operating program. The worker is a `claude -p` process running that program as its prompt.

Start:

```bash
scripts/start_worker.sh
```

Status:

```bash
scripts/worker_status.sh
```

Stop:

```bash
scripts/stop_worker.sh
```

State: `automation/worker.pid` (PID file), `automation/worker.log` (output log). Both are gitignored.

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
