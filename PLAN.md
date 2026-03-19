# Parameter Golf Plan

## Objective

Place highly on the leaderboard by minimizing the exact `final_int8_zlib_roundtrip` `val_bpb` under the `16,000,000` byte cap, while preserving a clean path to a reproducible 10-minute `8xH100` submission.

## Working Rules

- Do not modify the core trainers until baseline behavior, metrics, and artifact accounting are pinned down.
- Treat exact post-quant `val_bpb` as the canonical score. Pre-quant metrics are diagnostic only.
- Every experiment must have one hypothesis, one command, one log, one TSV row, and one short note.
- Prefer cheap, comparable runs over large ambiguous sweeps.

## Phase 0: Baseline Discipline

1. Reproduce the root baseline paths with the current trainers and published dataset/tokenizer.
2. Verify the harness captures:
   - exact final roundtrip `val_bpb`
   - pre-quant `val_bpb` when available
   - `bytes_total`, `bytes_code`, `bytes_model`
   - wallclock and stop step
3. Keep the repo clean enough that any promising run can be promoted into `records/` without reconstruction work.

## Phase 1: Cheapest Search Axes First

1. Sweep code-cheap trainer settings already exposed by env vars:
   - width, depth, KV heads, MLP multiplier
   - tied-embedding settings
   - LR splits and warmdown behavior
   - sequence length, batch tokens, validation cadence
2. Prioritize changes that improve final roundtrip score, not just pre-quant loss.
3. Track byte headroom explicitly so models do not drift into non-submittable territory.

## Phase 2: Higher-Leverage Changes

1. Explore parameter allocation and tokenizer choices only after baseline measurement is stable.
2. Separate ideas that improve:
   - train-time optimization
   - quantization robustness
   - evaluation-time effectiveness
3. Promote only ideas that either beat the current best or open a clear next branch of investigation.

## Submission Discipline

- A result is promotable only if it has a clean log, exact final metric, artifact bytes, and enough notes to reproduce the command.
- Snapshot competitive runs into `records/...` only after they are clearly worth preserving.
- Keep non-record runs when they reveal useful scaling or compression behavior, otherwise discard them.

## Immediate Next Moves

1. Run smoke experiments through the harness on both `train_gpt.py` and `train_gpt_mlx.py`.
2. Populate a first block of comparable discard runs around the published baseline.
3. Use those rows to decide which search axis earns the first real tuning budget.
