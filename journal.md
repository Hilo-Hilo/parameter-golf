# Worker Journal

This is the compressed startup journal for the current repo reset.
It intentionally replaces the old full history so the worker can start from low-load memory.
Use git history if a summarized point needs more detail.

## 2026-03-22 — Blank-slate frontier reset

### Reset state
- The live worker context was intentionally compressed on 2026-03-22.
- Assume no active run, no active pod, and no valid worker pid until verified.
- Worker state is tracked via `automation/worker.pid` and `automation/worker.log` (both gitignored).
- Full pre-reset detail is still recoverable from git history, including snapshot commit `030e8ab`.

### Carry-forward signal
- MLX lane became usable only after the validation accumulation fix; first valid canonical row was `20260319T023241Z_mlx_smoke_small_d256_l6_i10_evalfix`.
- Best local MLX keep was `20260319T055436Z_mlx_l7_d256_i600` at `2.07206045` with `4,145,729` total bytes.
- Best DGX keep was `20260319T230654Z_dgx_cuda_nocompile_l9_d544_kv4_seq256_i600` at `1.96640037` with `13,162,082` total bytes.
- RunPod verify/export became stable at `20260320T073704Z_runpod_h100_1gpu_l11_d496_untied_verify3`, which reached `1.31193434` at `15,070,268` total bytes.
- Best legal RunPod frontier keep was `20260321T025500Z_runpod_h100_1gpu_l11_d496_untied_verify_stride256_int4l9s3wc1750_mwd0003` at `1.22501069` with `15,754,075` total bytes.
- Best legal lower-byte alternative was `20260321T115941Z_runpod_h100_1gpu_l11_d496_untied_verify_stride256_bs80_int4l9s3wc1750_nofp16_mwd0017` at `1.22620977` with `15,408,917` total bytes.
- Strong over-cap near misses were `20260321T124149Z_runpod_h100_1gpu_l11_d496_untied_verify_stride256_bs80_int4l9s2wc1750_mwd0019` (`1.22415430`, `16,485,097` bytes) and `20260321T131910Z_runpod_h100_1gpu_l11_d496_untied_verify_stride256_int4l6s2wc1750_mwd0021` (`1.22384182`, `16,948,237` bytes).
- The later step4 / control branch (`int4 0..6`, `step4`, related export and muon sweeps) stayed legal but did not beat the best legal step3 frontier once bytes were respected.

### Start-here rule
- Sync `upstream` before resuming an old branch.
- Check only `pg-*` pods and inspect ETA if anything is already running.
- If nothing useful is active, continue from the strongest legal frontier or a clearly novel upstream-inspired branch.
- Hypothesis: the next legal improvement is more likely to come from making the stronger step2-like RunPod frontier fit under `16,000,000` bytes, or from a genuinely new upstream approach, than from more step4 control sweeps.

### Append-only rule from reset onward
- From this reset forward, append new material updates here instead of rebuilding full historical narration.
