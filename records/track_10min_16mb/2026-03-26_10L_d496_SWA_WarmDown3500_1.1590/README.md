# 10L d496 SWA + WarmDown3500

**val_bpb: 1.1590** (1-GPU proxy, 1 seed) | **15.94 MB** | 1xH100 NVL (proxy for 8xH100)

## Results (1xH100 NVL 80GB, PyTorch, proxy run)

| Metric | Value |
|--------|-------|
| exact_final_val_bpb (int8+zlib roundtrip) | **1.1590** |
| pre_quant_val_bpb | 1.1695 |
| steps | 6,721 |
| step_avg | 758.87ms |
| wallclock (training) | 5,100s |
| wallclock (total incl. eval) | 8,729s |
| bytes_model (int6+zlib) | 15,877,533 |
| bytes_code | 62,791 |
| bytes_total | 15,940,324 |

## Approach

Stock `train_gpt.py` with tuned environment variables. No code changes.

Key hyperparameters (via env overrides):
- `MODEL_DIM=496` (reduced from 512 to fit under 16M)
- `NUM_LAYERS=10`
- `TRAIN_BATCH_TOKENS=524288` (smaller batch for more update steps on 1-GPU)
- `WARMDOWN_ITERS=3500`
- `SWA_ENABLED=1`, `SWA_START_FRAC=0.4`, `SWA_EVERY=50`
- `EVAL_STRIDE=64`
- `TTT_ENABLED=0` (no test-time training)

## Reproduction

```bash
# 8xH100 (official track)
MODEL_DIM=496 NUM_LAYERS=10 WARMDOWN_ITERS=3500 \
SWA_ENABLED=1 SWA_START_FRAC=0.4 SWA_EVERY=50 \
EVAL_STRIDE=64 TTT_ENABLED=0 \
torchrun --standalone --nproc_per_node=8 train_gpt.py

# 1xH100 proxy (how this result was obtained)
MODEL_DIM=496 NUM_LAYERS=10 TRAIN_BATCH_TOKENS=524288 \
WARMDOWN_ITERS=3500 SWA_ENABLED=1 SWA_START_FRAC=0.4 \
SWA_EVERY=50 EVAL_STRIDE=64 TTT_ENABLED=0 \
MAX_WALLCLOCK_SECONDS=5100 \
torchrun --standalone --nproc_per_node=1 train_gpt.py
```

## Notes

- This is a 1-GPU proxy result. On 8xH100 with ~13,300 steps (vs 6,721 here), the bpb should improve.
- No code modifications required -- all tuning via environment variables.
- The d496 model dimension is key to fitting under 16M with int6+zlib serialization.
- SWA (Stochastic Weight Averaging) provides ~0.005 bpb improvement.
- WarmDown at 3500 iterations balances training stability with final convergence.
