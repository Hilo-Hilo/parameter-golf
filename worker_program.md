# Worker Program

You are an autonomous research worker. Execute this program immediately without asking for permission or confirmation. Do not present options or ask clarifying questions. Make decisions and act. If a step requires infrastructure (creating pods, running commands, fetching upstream), do it.

## Objective

Optimize exact final roundtrip `val_bpb` under challenge constraints:

- Primary metric: `exact_final_val_bpb` from `final_int8_zlib_roundtrip_exact`
- Hard artifact cap: `16,000,000` total bytes (`bytes_total`)
- Canonical track: reproducible 10-minute training on `8xH100`

Pre-quant validation metrics are diagnostic only.

## Required Context

Read before taking action:

- `CLAUDE.md`, `README.md`, `PLAN.md`
- `journal.md`, `registry/spool/`
- `train_gpt.py`, `train_gpt_mlx.py`

`journal.md` and spool records are compressed startup memory, not full archives. Use git history only when a summary line is insufficient.

## Repo Reality

- Trainers: `train_gpt.py` (CUDA/PyTorch), `train_gpt_mlx.py` (Apple Silicon MLX).
- Run wrapper: `scripts/run_experiment.sh`.
- Results ledger: spooled to `registry/spool/<run_id>.json` by wrapper.
- This repo does not use `prepare.py`, `train.py`, or `uv run train.py`.

## Branching

Before making any code changes, create a new branch named after the approach:

```bash
git checkout -b approach/<short-descriptive-name>
```

Examples: `approach/qat-int5-mixed`, `approach/bigram-hash-10k`, `approach/zstd22-byte-shave`.

Never commit experimental changes directly to `main` or `research/*` branches. Each approach gets its own branch. Push the branch to origin regularly.

## Startup Checklist

1. Confirm branch and git state.
2. Sync from `upstream` before committing to an old direction.
3. Create an approach-specific branch (see Branching above).
4. Check RunPod; only use pods with a `pg-` prefix.
5. Reconcile `journal.md` and spool records before choosing work.
6. Pick one bounded hypothesis with one changed axis.

## Status Semantics

- `keep`: valid, comparable run worth carrying forward.
- `discard`: valid run with no carry-forward value.
- `invalid`: completed but not challenge-comparable (missing exact metric, over byte cap, wrong eval regime).
- `crash`: command failed or output too broken to score.

## Run Pattern

```bash
scripts/run_experiment.sh \
  --name frontier_probe \
  --track runpod_h100 \
  --trainer train_gpt.py \
  --notes "one bounded frontier probe" \
  -- \
  env RUN_ID=frontier_probe \
      MAX_WALLCLOCK_SECONDS=600 \
      torchrun --standalone --nproc_per_node=1 train_gpt.py
```

## Experiment Loop

1. Reconcile: branch, best legal score, near misses, recent dead ends, infra state.
2. Choose one small hypothesis.
3. Make the minimum code/config change.
4. Launch one wrapped run with `scripts/run_experiment.sh`.
5. Review log and summary JSON from `experiments/<run_id>`.
6. Decide `keep` / `discard` / `invalid` / `crash`.
7. Update state and pass context to next branch cycle phase.

## Runtime Constraints

- Work on your own `approach/<name>` branch. Never commit to `main` or `research/*`.
- Use `scripts/run_experiment.sh` for comparable runs.
- Work one bounded hypothesis at a time.
- Only use Parameter Golf pods with a `pg-` prefix.
- Update local branch state (do NOT directly edit shared `journal.md` or `results.tsv` inside a branch cycle).
- Commit and push your branch regularly.

## Hygiene

- `journal.md` is append-only from this reset onward.
- Preserve exact metric and byte accounting for important runs.
- Prefer cheap, comparable runs over broad sweeps.
- Compress journal and spool records again when they stop being useful startup memory.
