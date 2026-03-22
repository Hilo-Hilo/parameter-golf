# Parameter Golf Continuous Program (Repo-Adapted)

Use this as the default operating program for autonomous or semi-autonomous experimentation in this repository.

## Objective

Optimize the best exact final roundtrip score under challenge constraints:

- Primary metric: `exact_final_val_bpb` from `final_int8_zlib_roundtrip_exact`
- Hard artifact cap: `16,000,000` total bytes (`bytes_total`)
- Canonical track target: reproducible 10-minute training path on `8xH100`

Pre-quant validation metrics are diagnostic only and should not be treated as the objective.

## Required Context Before Action

Read these files before making meaningful changes or launching runs:

- `CLAUDE.md`
- `README.md`
- `PLAN.md`
- `program.md`
- `journal.md`
- `results/README.md`
- `scripts/README.md`
- `automation/continuous_worker_prompt.md`
- `automation/cron_watchdog_spec.md`
- `train_gpt.py`
- `train_gpt_mlx.py`

## Repo Reality (Important Differences From Generic Autoresearch)

- This repo does not use `prepare.py`, `train.py`, or `uv run train.py`.
- Main trainers are `train_gpt.py` (PyTorch/CUDA) and `train_gpt_mlx.py` (Apple Silicon MLX).
- Preferred run wrapper is `scripts/run_experiment.sh` (not ad hoc `run.log` loops).
- Results ledger is `results/results.tsv` with wide schema from `scripts/parse_train_log.py`.
- Default wallclock cap is 600 seconds unless overridden (`MAX_WALLCLOCK_SECONDS`).
- Durable project memory is append-only `journal.md`.

## Setup Checklist

1. Confirm branch and git state.
2. Ensure data/tokenizer exists or fetch it:

   ```bash
   python3 data/cached_challenge_fineweb.py --variant sp1024 --train-shards 10
   ```

3. Confirm training lane for this run:
   - preferred: remote CUDA (RunPod/DGX)
   - secondary: local MLX sanity runs
4. Define one short hypothesis and one primary changed axis.
5. Use one command per run via `scripts/run_experiment.sh`.

## Canonical Run Patterns

CUDA/PyTorch smoke:

```bash
scripts/run_experiment.sh \
  --name baseline_1gpu_smoke \
  --track local-smoke \
  --trainer train_gpt.py \
  --notes "1 GPU smoke with short wallclock" \
  -- \
  env RUN_ID=baseline_sp1024 \
      DATA_PATH=./data/datasets/fineweb10B_sp1024/ \
      TOKENIZER_PATH=./data/tokenizers/fineweb_1024_bpe.model \
      VOCAB_SIZE=1024 \
      MAX_WALLCLOCK_SECONDS=30 \
      VAL_LOSS_EVERY=200 \
      torchrun --standalone --nproc_per_node=1 train_gpt.py
```

Local MLX smoke:

```bash
scripts/run_experiment.sh \
  --name mlx_smoke \
  --track mac-smoke \
  --trainer train_gpt_mlx.py \
  --notes "short local sanity run" \
  -- \
  env RUN_ID=mlx_smoke \
      ITERATIONS=200 \
      TRAIN_BATCH_TOKENS=8192 \
      VAL_LOSS_EVERY=0 \
      VAL_BATCH_SIZE=8192 \
      python3 train_gpt_mlx.py
```

## Status and Logging Rules

Use status values exactly as defined by this repo:

- `keep`: new best or clearly useful next-branch signal
- `discard`: valid run without carry-forward value
- `invalid`: run completed but not challenge-comparable (missing exact metric or over byte cap)
- `crash`: command failed

The wrapper and parser automatically record one row in `results/results.tsv`.
Do not maintain a custom 5-column results format.

## Experiment Loop

Repeat continuously until manually stopped:

1. Reconcile current state (`branch`, current best, open hypotheses, recent rows in `results/results.tsv`).
2. Choose one small, testable hypothesis.
3. Implement the minimal code change needed.
4. Run exactly one wrapped experiment command.
5. Review:
   - `logs/experiments/<experiment_id>.log`
   - `logs/experiments/<experiment_id>.json`
   - appended row in `results/results.tsv`
6. Decide:
   - keep and branch forward if it improves score or clearly improves search direction
   - otherwise discard and move to the next bounded hypothesis
7. Append a journal entry in `journal.md` for every material update (attempt, result, infra change, directional decision).

## Promotion Discipline

Promote only high-value runs into `records/track_10min_16mb/<run_name>/` with:

- `README.md` (clear method + reproducibility notes)
- `submission.json`
- trainer script and any local dependencies
- training logs needed for significance claims

Do not treat root trainer tweaks as a final submission by default; use `records/` snapshots for promotable runs.

## Continuous Worker and Infra Notes

- If running the detached worker, use:
  - `scripts/start_continuous_worker.sh`
  - `python3 scripts/check_continuous_worker.py`
  - `python3 scripts/watchdog_tick.py`
  - `scripts/stop_continuous_worker.sh`
- Keep orchestration state in `automation/state/research_state.json`.
- RunPod usage for this project should use pods intended for Parameter Golf and follow repo policy.

## Non-Negotiable Hygiene

- Never rewrite prior entries in `journal.md` (append only).
- Keep exact final metric and byte accounting in every materially important run.
- Prefer cheap, comparable runs over broad ambiguous sweeps.
- Avoid repeating stale experiments; reconcile prior rows and journal before launching.