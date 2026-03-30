# Frontier Digest
Generated at Mon Mar 30 14:19:04 UTC 2026

## Official Leaderboard (from README)
## Leaderboard

| Run | Score | Author | Summary | Date | Info |
|-----|------:|--------|---------|------|------|
| LeakyReLU² + Legal Score-First TTT + Parallel Muon | 1.1194 | abaybektursun | On PR #549: LeakyReLU(0.5)^2 + TTT + Parallel Muon on the PR #414 stack | 2026-03-23 | [info](records/track_10min_16mb/2026-03-23_LeakyReLU_LegalTTT_ParallelMuon/README.md) |
| 11L EMA + GPTQ-lite + warmdown3500 | 1.1228 | signalrush | On PR #374: GPTQ-lite clip search + EMA, plus warmdown3500 and QAT@0.15 | 2026-03-22 | [info](records/track_10min_16mb/2026-03-22_11L_EMA_GPTQ-lite_warmdown3500_QAT015_1.1233/README.md) |
| 11L Partial RoPE + LN Scale + EMA + XSA4 | 1.1248 | jfprincz | On PR #287: Partial RoPE (16/64) + layerwise LN scale | 2026-03-21 | [info](records/track_10min_16mb/2026-03-21_11L_XSA4_EMA_PartialRoPE_LateQAT_1.1248/README.md) |
| 11L XSA4 + EMA + Int6 MLP3x | 1.1271 | jfprincz | On PR #198: XSA on the last 4 layers + EMA replacing SWA | 2026-03-20 | [info](records/track_10min_16mb/2026-03-20_11L_XSA4_EMA_Int6_MLP3x_WD04_1.1271/README.md) |
| 11L Efficient Partial XSA | 1.1307 | unnir | On PR #198: Efficient Partial XSA on the deepest 3 layers | 2026-03-20 | [info](records/track_10min_16mb/2026-03-20_11L_EfficientPartialXSA_FA3_SWA120/README.md) |
| 10L Int5-MLP + BigramHash(10240) | 1.1428 | thwu1 | 10 layers, mixed int5/int6 quantization, BigramHash(10240), SWA(0.4), WD=0.04 | 2026-03-20 | [info](records/track_10min_16mb/2026-03-20_10L_Int5MLP_MuonWD04_SWA50/README.md) |
| Int6 MLP3x + SmearGate + BigramHash | 1.1458 | Raahil Shah | 3x MLP + SmearGate + BigramHash + OrthoInit + Muon WD + SWA | 2026-03-20 | [info](records/track_10min_16mb/2026-03-20_Int6_MLP3x_SmearGate_BigramHash_MuonWD_SWA/README.md) |
| 11L MLP3x + Int6 QAT | 1.1502 | aruniyer | 11 layers, 3x MLP, int6 QAT, zstd-22, WD=0.04, sliding eval | 2026-03-20 | [info](records/track_10min_16mb/2026-03-19_MLP3x_QAT_Int6_SlidingWindow/README.md) |
| SmearGate + OrthoInit + Muon WD | 1.1556 | aquariouseworkman | SmearGate + BigramHash + 3x MLP + int6 STE QAT + sliding eval | 2026-03-19 | [info](records/track_10min_16mb/2026-03-19_smeargate_orthoinit_muonwd/README.md) |
| Ternary Quantization | 1.1570 | Ciprian-Florin Ifrim | 73.7M params quantized to 1 0 -1 + misc arch changes | 2026-03-24 | [info](records/track_10min_16mb/2026-03-24_74M_Ternary_UNet_FP8_10L_8192BPE_YaRN_NeoMuon/README.md) |
| 10L Int6 QAT + Zstd MLP2.6x | 1.1586 | yahya010 | 10 layers, int6 QAT + zstd-22, MLP 1344, Muon 0.99, sliding eval | 2026-03-19 | [info](records/track_10min_16mb/2026-03-19_Seq2048_FP16Emb_TunedLR/README.md) |
| Mixed Quant + Sliding Window Eval | 1.1630 | aquariouseworkman | Int6 block weights + int8 embeddings + 3x MLP + sliding eval | 2026-03-19 | [info](records/track_10min_16mb/2026-03-19_MixedQuant_Int6Int8_SlidingWindow/README.md) |
| Muon WD + 10 layer | 1.1748 | notapplica | Includes prev. wins + Spectral embed init + resid mix | 2026-03-19 | [info](records/track_10min_16mb/2026-03-19_SlidingWindow_FP16Emb_10L_MuonWD_OvertoneInit/README.md) |
| Sliding Window Eval | 1.1925 | Matthew Li | Sliding window evaluation at stride=64, increasing context for eval | 2026-03-19 | [info](records/track_10min_16mb/2026-03-19_SlidingWindowEval/README.md) |
| Lora TTT | 1.1928 | samacqua | Test-time training with LORAs | 2026-03-19 | [info](records/track_10min_16mb/2026-03-17_LoRA_TTT/README.md) |
| 4k seq length| 1.2014 | Spokane Way | 4k seq length + better hypers | 2026-03-19 | [info](records/track_10min_16mb/2026-03-19_TrainingOptSeq4096/README.md) |
| 2048 seq length | 1.206 | Spokane Way | 2048 seq length (train + val) | 2026-03-18 | [info](records/track_10min_16mb/2026-03-18_LongContextSeq2048/README.md) |
| int6 mixed precision | 1.2147 | Nan Liu | 10 layers, mixed int8/int6 | 2026-03-18 | [info](records/track_10min_16mb/2026-03-19_10L_MixedPrecision/README.md) |
| fp16 Embed | 1.2197 | Renier Velazco | FP16 Tied Embedding + LR/Warmdown Tuning | 2026-03-18 | [info](records/track_10min_16mb/2026-03-18_FP16Embed_WD3600/README.md) |
| Naive Baseline | 1.2244 | Baseline | 9layer 512dim 1024vocab TiedEmbeddings 4 KV heads | 2026-03-18 | [info](records/track_10min_16mb/2026-03-17_NaiveBaseline/README.md) |

#### Unlimited Compute Leaderboard & Non-record Submissions

| Run | Score | Author | Summary | Date | Info |
|-----|------:|--------|---------|------|------|
| 1 Bit Quantization | 1.1239 | Ciprian-Florin Ifrim | 106M params quantized to 1 bit + misc arch changes + 2hr training | 2026-03-24 | [info](records/track_non_record_16mb/2026-03-24_106M_Binary_Asymmetric_UNet_FP8_15L_8192BPE_YaRN_NeoMuon_Smear/README.md) |

## Key Techniques from Recent Records
### PR #561: Update README leaderboard with merged record submissions
Merged: 2026-03-23T17:42:37Z
URL: https://github.com/openai/parameter-golf/pull/561
## Summary

Update the README leaderboard with the recently merged record submissions:
- PR #265: 1.1307
- PR #287: 1.1271
- PR #315: 1.1248
- PR #414: 1.1228

Each new leaderboard row now states the base run and the architecture/config diff from that base, rather than a score delta.

## Intentionally not included

- PR #505 is not leaderboard-ready yet: it does not include a `submission.json`, and it does not include the train logs needed to back the claimed 3-seed result.
- PR #545 is not lead
---
### PR #77: [record bpb=1.195] sliding window + LoRA TTT
Merged: 2026-03-19T22:30:27Z
URL: https://github.com/openai/parameter-golf/pull/77
This record captures `LoRA TTT`: the naive baseline model + document masking + sliding window + LoRA test-time training at evaluation.

## Method

**Training** is identical to the naive baseline.

**Evaluation** adds per-document LoRA test-time training (TTT). For each document in the validation set:
1. Find document boundaries using BOS tokens
2. Split the document into overlapping chunks (chunk_size=256 within eval_seq_len=1024 context windows)
3. For each chunk, score it (accumulate 
---
### PR #265: Record: 11L + Efficient Partial XSA (val_bpb: 1.1307) 
Merged: 2026-03-23T17:22:37Z
URL: https://github.com/openai/parameter-golf/pull/265
# 11L + Efficient Partial XSA (val_bpb: 1.1307)

## Results
- **val_bpb: 1.1307** (sliding window, stride=64)
- Pre-quantization BPB: 1.1437
- Model parameters: 26,829,913
- Artifact size: 15,892,986 bytes (under 16MB limit)
- Training: 6,976 steps in 600 seconds (~86ms/step)
- SWA: 13 checkpoint average during warmdown (every 120 steps)

## Novel Contribution: Efficient Partial Exclusive Self Attention (XSA)

Based on Exclusive Self Attention (arXiv:2603.09078), we introduce two key
---
### PR #50: Record: Sliding Window Eval (stride=64), val_bpb=1.1925
Merged: 2026-03-19T17:28:13Z
URL: https://github.com/openai/parameter-golf/pull/50
## Summary

- Sliding window evaluation with stride=64 on the baseline 9x512 SP-1024 architecture
- **val_bpb: 1.1925** (post-quant int8+zlib), improving on the Naive Baseline's 1.2244 by **0.032**
- Training is identical to the baseline; the improvement comes entirely from the evaluation strategy
- Each token is scored with 960+ tokens of context instead of 0-1023
- Eval takes 70s on 8xH100 (well within the 10-minute eval budget)
- Total artifact size: 15,874,829 bytes (under 16MB cap)

## Test
---
### PR #73: Non-record: SwiGLU + warmdown fix + quarter batch (1x5090, 1.3281 bpb)
Merged: 2026-03-20T18:42:15Z
URL: https://github.com/openai/parameter-golf/pull/73
Non-record submission documenting a 10-experiment systematic exploration on 1×RTX 5090.

**Best val_bpb:** 1.3281 (post-quant, under 16MB artifact cap)

**Key findings:**
- Discovered warmdown schedule bug in stock train_gpt.py — default warmdown_iters=1200 with 600s wallclock causes LR to decay from step 1. Fixed with time-fraction approach (warmdown_frac=0.2). Worth -0.006 bpb alone.
- SwiGLU activation replacing ReLU² (-0.004 bpb)
- Quarter batch size (131K tokens) for 4× more optimize
---
### PR #315: Record: 11L Partial RoPE + LN Scale + EMA + XSA4 (val_bpb: 1.1248)
Merged: 2026-03-23T17:24:18Z
URL: https://github.com/openai/parameter-golf/pull/315
## Record: 11L Partial RoPE + LN Scale + EMA + XSA4 (val_bpb: 1.1248)

**val_bpb: 1.1248** (sliding window, stride=64) | **15.6 MB** | 8xH100 SXM, 600s

### Progress from prior submissions

| | [PR #70](https://github.com/openai/parameter-golf/pull/70) | [PR #164](https://github.com/openai/parameter-golf/pull/164) | [PR #198](https://github.com/openai/parameter-golf/pull/198) | [PR #287](https://github.com/openai/parameter-golf/pull/287) | This | Delta vs #287 |
|---|---|---|---|---|---|---|
| *
---
### PR #162: Record: Int6 MLP3x + SmearGate + BigramHash + MuonWD + SWA (mean val_bpb=1.1483)
Merged: 2026-03-20T18:48:27Z
URL: https://github.com/openai/parameter-golf/pull/162
## Int6 MLP3x + SmearGate + BigramHash + OrthoInit + Muon WD + SWA

**Mean val_bpb: 1.1483** (3 seeds: 1.1488, 1.1485, 1.1476)

Trained on 8×H100 SXM in 600 seconds. 15.92MB artifact (int6+zstd-22).

### Key Techniques

1. **Per-row int6 quantization** ([-32,31]) on MLP + attention weights, fp16 passthrough for tied embeddings and last-layer key projection. zstd level 22 compression.
2. **3× MLP expansion** (hidden=1536) — enabled by int6 byte savings. Single largest improvement source.
3. **Sme
---
### PR #414: Record: 11L EMA + GPTQ-lite + warmdown3500 + QAT@0.15 (val_bpb=1.1233)
Merged: 2026-03-23T17:26:08Z
URL: https://github.com/openai/parameter-golf/pull/414
## Record: 11L EMA + GPTQ-lite + warmdown3500 + QAT@0.15

**val_bpb: 1.1233** (sliding window stride=64, 3-seed mean) | **15.55 MB** (mean) | 8xH100 SXM, 600s

### Key Innovations Over PR #374

| Change | PR #374 | This | Impact |
|--------|---------|------|--------|
| **GPTQ-lite** | Fixed clip (row max) | 5 clip percentiles per row, pick min MSE | -0.0006 BPB |
| **EMA** (decay=0.997) | None (Tight SWA only) | EMA every step | -0.0006 BPB |
| **Warmdown** | 3000 | 3500 | -0.0002 BPB |
| **Late
---
### PR #287: Record: 11L XSA + EMA + Int6 MLP3x + WD=0.04 (val_bpb: 1.1271)
Merged: 2026-03-23T17:23:10Z
URL: https://github.com/openai/parameter-golf/pull/287
## Record: 11L XSA + EMA + Int6 MLP3x + WD=0.04 (val_bpb: 1.1271)

**val_bpb: 1.1271** (sliding window, stride=64) | **15.5 MB** | 8xH100 SXM, 600s

### Progress from prior submissions

| | [PR #70](https://github.com/openai/parameter-golf/pull/70) | [PR #164](https://github.com/openai/parameter-golf/pull/164) | [PR #198](https://github.com/openai/parameter-golf/pull/198) | This | Delta vs #198 |
|---|---|---|---|---|---|
| **val_bpb (sliding)** | 1.1659 (s256) | 1.1524 (s256) | 1.1318 (s64) | *
---
### PR #39: Record: 10L Mixed Precision: val_bpb=1.2147 (10 layers + int6 middle layers)
Merged: 2026-03-19T22:26:46Z
URL: https://github.com/openai/parameter-golf/pull/39
## Summary

Two submissions:

### 1. 10L Mixed Precision (val_bpb=1.2139 mean across 5 seeds)
- **10 transformer layers** (vs baseline 9) with mixed int8/int6 compression
- Full int8 for first/last 3 layers, **int6 (step=4 rounding) for middle layers 3-6**
- Lower LR: MATRIX_LR=0.02 SCALAR_LR=0.02 TIED_EMBED_LR=0.03
- Improves post-quant roundtrip validation metrics on the same val set from **1.2244 → 1.2139 bpb** and **2.0727 → 2.0496 nats**
- Artifact: ~15.93MB (under 16MB)

### 2. Lower LR (v
---
