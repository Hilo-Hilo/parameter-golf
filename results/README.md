# Results Ledger

`results/results.tsv` is the live experiment ledger for this repo.

The file currently starts from a compressed frontier snapshot rather than the full raw project history. New runs append to that seed state.

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
2. Let the wrapper append one TSV row and store the raw log under `logs/experiments/`.
3. Upgrade a run from `discard` to `keep` only when it is meaningfully informative.

The TSV is intentionally plain text so it stays easy to diff, grep, and review in PRs.
When the file grows large enough to become noisy startup context, compress it again instead of preserving every historical row in the live worker view.
