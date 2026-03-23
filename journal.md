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

## 2026-03-22 — SOTA adoption + TTT approach

### Upstream recon
- Upstream main has no new commits since last sync.
- Leaderboard leader: thwu1 at 1.1428 bpb (10L, mixed int5/int6, BigramHash(10240), SWA(0.4), WD=0.04).
- Key gap vs our best (1.225): missing BigramHash, SmearGate, 3x MLP, mixed int5/int6 quant, SWA, zstd-22, extended warmdown.
- Unmerged PRs show TTT (Test-Time Training) as dominant lever:
  - PR #486: 1.0887 (TrigramHash + ValueResidual + GradQuant + Cosine TTT)
  - PR #481: 1.0970 (Cosine TTT + per-layer LR)
  - PR #508: 1.1215 (GPTQ + Early QAT + Legal TTT)
- TTT alone adds ~0.03-0.05 bpb improvement over non-TTT approaches.

### Extended baseline run (killed before completion)
- Pod `pg-sota-repro` (1xH100 NVL) ran stock baseline `train_gpt.py` from upstream main with MAX_WALLCLOCK_SECONDS=8550.
- Stopped at step 7529 after wallclock cap.
- Pre-quant val_bpb at step 7500: 1.1496.
- int6+zstd model: 15,897,453 bytes, total submission: 15,950,620 bytes.
- Killed during sliding window eval (969K windows) to free GPU.
- Status: invalid (not challenge-comparable, extended wallclock, no final roundtrip metric captured).

### Approach: cosine-ttt
- Branch: `approach/cosine-ttt`.
- Base: SOTA #1 entry code (thwu1, 1.1428 bpb).
- Change: added chunk-by-chunk TTT with cosine LR, per-layer LR (3x MLP output, 0.5x input), EMA scoring, embedding freeze.
- Fix: manually expand KV heads for GQA (PyTorch 2.4 on pod lacks enable_gqa kwarg).
- First run `cosine_ttt_v1` launched on `pg-sota-repro` (1xH100 NVL, 600s wallclock).
- Hypothesis: TTT will improve SOTA #1's post-quant roundtrip bpb by 0.02-0.05.
