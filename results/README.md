# Results Ledger

`registry/spool/*.json` acts as the live experiment ledger for this repo via per-run spools.

Runs are output individually by `scripts/run_experiment.sh` into JSON files instead of a single appended TSV. This ensures safer concurrency across parallel branches.

## Canonical Fields

- `exact_final_val_bpb`: score to optimize, taken from `final_int8_zlib_roundtrip_exact`
- `pre_quant_val_bpb`: last pre-quant validation BPB if present
- `bytes_model`: quantized model artifact bytes when available
- `bytes_code`: trainer code bytes when available
- `bytes_total`: `bytes_model + bytes_code` when available
- `wallclock_seconds`: parsed from the logged train time or submission metadata
- `status`: one of `keep`, `discard`, `invalid`, `crash`
- `notes`: short explanation of what changed or why the run matters

## Status Meanings

- `keep`: worth revisiting or promoting
- `discard`: valid but not worth carrying forward
- `invalid`: finished but not leaderboard-comparable
- `crash`: command failed

## Workflow

1. Launch runs through `scripts/run_experiment.sh`.
2. Let the wrapper spool the summary to `registry/spool/<run_id>.json` and save artifacts to `experiments/<run_id>`.
3. Upgrade a run from `discard` to `keep` only when it is meaningfully informative.

When the spooled runs grow large enough to become noisy startup context, compress them into a summarized format instead of preserving every historical file in the live worker view.
