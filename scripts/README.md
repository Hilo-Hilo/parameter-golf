# Scripts

Minimal experiment helpers for this repo.

## Files

- `scripts/run_experiment.sh`: launch one run, capture a log, parse metrics, append one TSV row
- `scripts/parse_train_log.py`: stdlib-only parser for `train.log` plus optional `submission.json`
- `scripts/start_continuous_worker.sh`: launch the detached Codex research worker and write watchdog state
- `scripts/check_continuous_worker.py`: machine-readable liveness check for the detached worker
- `scripts/stop_continuous_worker.sh`: stop the detached worker using watchdog state
- `scripts/watchdog_tick.py`: one deterministic watchdog tick (check/cooldown/restart)
- `scripts/research_state.py`: durable planning/dedupe state for worker runs, with reconciliation logic
- `scripts/smoke_research_state.sh`: reproducible smoke path for reconcile/start-stop state lifecycle

## Continuous worker stance

- The continuous worker is expected to run 24/7 until manually stopped.
- Preferred training lane: remote CUDA hardware, with DGX Spark / RunPod first when accessible.
- Local MLX is the secondary sanity-check lane, not the default long-run search lane.
- `journal.md` at repo root is the durable append-only project log; material updates should be appended, never rewritten.
- `automation/state/research_state.json` is the durable planning state for reconciliation and run dedupe.
- The durable state tracks active hypothesis/action signatures, upstream checks, last completed run signature, and reconciliation decisions.

## Typical Usage

PyTorch baseline-style run:

```bash
scripts/run_experiment.sh \
  --name baseline_1gpu_smoke \
  --track local-smoke \
  --trainer train_gpt.py \
  --notes "1 GPU smoke with short wallclock" \
  -- \
  env MAX_WALLCLOCK_SECONDS=30 VAL_LOSS_EVERY=200 torchrun --standalone --nproc_per_node=1 train_gpt.py
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

## Watchdog helpers

Start the detached worker:

```bash
scripts/start_continuous_worker.sh
```

Check worker status:

```bash
python3 scripts/check_continuous_worker.py
```

Inspect reconciliation payload with state file:

```bash
python3 scripts/check_continuous_worker.py --research-state-file automation/state/research_state.json
```

Run one watchdog tick:

```bash
python3 scripts/watchdog_tick.py
```

Smoke-check orchestration-state lifecycle:

```bash
scripts/smoke_research_state.sh
```

Stop worker:

```bash
scripts/stop_continuous_worker.sh
```

The watchdog state lives under `automation/state/` and logs under `automation/logs/`.
These runtime artifacts are intentionally gitignored.

## State-dedupe smoke path

```bash
scripts/smoke_research_state.sh
```

## Notes

- The experiment wrapper defaults successful runs to `discard`. Pass `--status keep` only when you already know the run should be retained.
- If the command exits non-zero, the row is recorded as `crash`.
- If the exact final roundtrip metric is missing, or the artifact exceeds `16,000,000` bytes, the row is recorded as `invalid`.
- `submission.json` is optional. When provided, parser fields from the JSON take precedence over log-derived values.
