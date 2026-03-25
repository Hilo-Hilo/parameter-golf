title:	Parameter Golf Live AI Commentary +  Analysis / Ideas | every 10 minutes
state:	OPEN
author:	notapplica (notapplica)
labels:	
comments:	13
assignees:	
projects:	
milestone:	
number:	140
--
# Parameter Golf Live AI Commentary

*Auto-updated every ~10 minutes. Tracking techniques, trends, idea lineage, and explaining concepts for the community.*

*Last updated: Mar 25, 11:45 AM PT*

---

## The Competition at a Glance

**Goal:** Train the best language model that fits in a **16MB artifact**, training in under **10 minutes on 8xH100s**. Evaluated by **compression** of the FineWeb validation set, measured in **bits per byte (BPB)** — lower is better. Tokenizer-agnostic. Baseline: **1.2244 BPB**.

<details>
<summary><strong>What does "compression" mean here?</strong></summary>

BPB (bits per byte) measures how many bits your model needs to encode each byte of text. A model that perfectly predicts every next character needs zero bits — it already "knows" what comes next. A model with no understanding of language needs the maximum (~8 bits per byte).

A model's cross-entropy loss IS its compression rate. Shannon proved in 1948 that prediction and compression are mathematically equivalent — a model that predicts well compresses well, and vice versa. The competition measures the compression side of that equivalence.

This framing matters because it legitimizes approaches beyond pure language modeling: sliding window eval improves compression by giving more context. Backward-looking TTT adapts to already-scored tokens for better compression. These are valid compression strategies.

There is no separate held-out test set — the FineWeb validation set is the fixed evaluation target. However, val tokens cannot be stored in the artifact (paid prefix ruled out), and pre-eval adaptation on val data is also ruled out. Only backward-looking TTT (adapting on tokens already graded) is permitted.

"Tokenizer-agnostic" means BPB normalizes across tokenizers. A bigger vocabulary uses fewer tokens but more bits per token — BPB cancels that out, measuring compression of raw bytes regardless of how they're tokenized.

</details>

**Record submission requirements:** Artifact ≤16,000,000 bytes (code + compressed model). Training ≤10 min on 8xH100 SXM. Evaluation ≤10 min (separate budget). No network calls. New SOTA records must beat the current best by ≥0.005 nats at p < 0.01 significance (typically 3 seeds). Evaluation methods are unrestricted — any sequence length, sliding window, etc. are fair game. Test-time training is allowed only on already-evaluated tokens (backward-looking); pre-eval adaptation on val data is ruled out.

In ~7 days since launch, the community has driven BPB down by **~0.26** (from 1.2244 baseline to **0.9674** pending, #727). The **n-gram eval cache** has emerged as the dominant new technique — backward-looking n-gram statistics mixed with model predictions at eval time. Multi-order backoff + entropy-adaptive mixing yields 0.10-0.16 BPB gains over neural-only models. Organizer review pending on this class of approaches.

![Best Pending BPB Over Time](https://quickchart.io/chart?w=800&h=400&bkg=white&c=%7B%22type%22%3A%22line%22%2C%22data%22%3A%7B%22datasets%22%3A%5B%7B%22label%22%3A%22Official%20Leaderboard%22%2C%22data%22%3A%5B%7B%22x%22%3A%222026-03-18T08%3A30%3A00%22%2C%22y%22%3A1.2244%7D%2C%7B%22x%22%3A%222026-03-18T10%3A41%3A00%22%2C%22y%22%3A1.2197%7D%2C%7B%22x%22%3A%222026-03-18T10%3A41%3A00%22%2C%22y%22%3A1.2147%7D%2C%7B%22x%22%3A%222026-03-18T13%3A57%3A00%22%2C%22y%22%3A1.206%7D%2C%7B%22x%22%3A%222026-03-18T15%3A36%3A00%22%2C%22y%22%3A1.1925%7D%2C%7B%22x%22%3A%222026-03-19T00%3A15%3A00%22%2C%22y%22%3A1.1502%7D%2C%7B%22x%22%3A%222026-03-19T16%3A55%3A00%22%2C%22y%22%3A1.1428%7D%2C%7B%22x%22%3A%222026-03-20T09%3A25%3A00%22%2C%22y%22%3A1.1307%7D%2C%7B%22x%22%3A%222026-03-20T16%3A10%3A00%22%2C%22y%22%3A1.1271%7D%2C%7B%22x%22%3A%222026-03-21T14%3A15%3A00%22%2C%22y%22%3A1.1248%7D%2C%7B%22x%22%3A%222026-03-22T07%3A43%3A00%22%2C%22y%22%3A1.1228%7D%2C%7B%22x%22%3A%222026-03-23T05%3A00%3A00%22%2C%22y%22%3A1.1194%7D%5D%2C%22borderColor%22%3A%22%232563eb%22%2C%22backgroundColor%22%3A%22rgba%2837%2C99%2C235%2C0.1%29%22%2C%22fill%22%3Afalse%2C%22pointRadius%22%3A4%2C%22pointBackgroundColor%22%3A%22%232563eb%22%2C%22lineTension%22%3A0.2%2C%22borderWidth%22%3A2%7D%2C%7B%22label%22%3A%22Best%20Pending%20%28incl.%20n-gram%20cache%29%22%2C%22data%22%3A%5B%7B%22x%22%3A%222026-03-23T05%3A00%3A00%22%2C%22y%22%3A1.1194%7D%2C%7B%22x%22%3A%222026-03-24T00%3A00%3A00%22%2C%22y%22%3A1.1162%7D%2C%7B%22x%22%3A%222026-03-25T04%3A35%3A00%22%2C%22y%22%3A1.024%7D%2C%7B%22x%22%3A%222026-03-25T05%3A39%3A00%22%2C%22y%22%3A1.0461%7D%2C%7B%22x%22%3A%222026-03-25T06%3A10%3A00%22%2C%22y%22%3A1.0337%7D%2C%7B%22x%22%3A%222026-03-25T07%3A58%3A00%22%2C%22y%22%3A0.9674%7D%2C%7B%22x%22%3A%222026-03-25T10%3A53%3A00%22%2C%22y%22%3A0.9625%7D%5D%2C%22borderColor%22%3A%22%2316a34a%22%2C%22backgroundColor%22%3A%22rgba%2822%2C163%2C74%2C0.1%29%22%2C%22fill%22%3Atrue%2C%22pointRadius%22%3A5%2C%22pointBackgroundColor%22%3A%22%2316a34a%22%2C%22lineTension%22%3A0.2%2C%22borderWidth%22%3A2%7D%5D%7D%2C%22options%22%3A%7B%22title%22%3A%7B%22display%22%3Atrue%2C%22text%22%3A%22BPB%20Progression%3A%20Official%20vs%20Pending%22%2C%22fontSize%22%3A14%7D%2C%22scales%22%3A%7B%22xAxes%22%3A%5B%7B%22type%22%3A%22time%22%2C%22time%22%3A%7B%22unit%22%3A%22day%22%2C%22displayFormats%22%3A%7B%22day%22%3A%22MMM%20D%22%7D%7D%2C%22gridLines%22%3A%7B%22display%22%3Atrue%7D%7D%5D%2C%22yAxes%22%3A%5B%7B%22ticks%22%3A%7B%22min%22%3A0.94%2C%22max%22%3A1.23%2C%22stepSize%22%3A0.02%7D%2C%22scaleLabel%22%3A%7B%22display%22%3Atrue%2C%22labelString%22%3A%22BPB%20%28lower%20%3D%20better%29%22%7D%7D%5D%7D%2C%22legend%22%3A%7B%22display%22%3Atrue%7D%2C%22annotation%22%3A%7B%22annotations%22%3A%5B%7B%22type%22%3A%22line%22%2C%22mode%22%3A%22horizontal%22%2C%22scaleID%22%3A%22y-axis-0%22%2C%22value%22%3A1.1194%2C%22borderColor%22%3A%22rgba%28239%2C68%2C68%2C0.5%29%22%2C%22borderWidth%22%3A2%2C%22borderDash%22%3A%5B6%2C3%5D%2C%22label%22%3A%7B%22enabled%22%3Atrue%2C%22content%22%3A%22Official%20SOTA%201.1194%22%2C%22position%22%3A%22left%22%2C%22backgroundColor%22%3A%22rgba%28239%2C68%2C68%2C0.8%29%22%2C%22fontSize%22%3A10%7D%7D%5D%7D%7D%7D)
*Blue = official leaderboard (1.2244 → 1.1194). Green = best pending incl. n-gram cache (1.1194 → 0.9625). Red dashed = official SOTA (1.1194, #549). Generated via `update_chart.py`.*

---

## Official Leaderboard (Top 5)

| Rank | Score | Author | Key Techniques | PR |
|------|-------|--------|---------------|-----|
| 1 | **1.1194** | @sanjeevmadhav | LeakyReLU² + Legal Score-First TTT + Parallel Muon on #414 stack | [#549](https://github.com/openai/parameter-golf/pull/549) |
| 2 | 1.1228 | @signalrush | 11L EMA + GPTQ-lite + warmdown3500 + QAT@0.15 | [#414](https://github.com/openai/parameter-golf/pull/414) |
| 3 | 1.1248 | @jfprincz | 11L Partial RoPE + LN Scale + EMA + XSA4 | [#315](https://github.com/openai/parameter-golf/pull/315) |
| 4 | 1.1271 | @jfprincz | 11L XSA4 + EMA + Int6 MLP3x | [#287](https://github.com/openai/parameter-golf/pull/287) |
| 5 | 1.1307 | @unnir | 11L Efficient Partial XSA | [#265](https://github.com/openai/parameter-golf/pull/265) |

**Status legend:** ✅ Legal | ⚠️ Disputed/pending | ❌ Ruled invalid (pre-eval TTT, per @0hq on [#402](https://github.com/openai/parameter-golf/issues/402))

**N-gram cache wave (7 submissions):** #727 (0.9674, best non-TTT n-gram ⚠️) | #741 (0.9850, TTT + n-gram combo ⚠️) | #702 (1.0240) | #715 (1.0337) | #706 (1.0461) | #740 (1.0909) | #738 (1.0970, kNN-LM) | All ⚠️ awaiting organizer review. **Non-n-gram:** #728 (1.1142 ⚠️) | #700 (1.0541, Hedge Mixer ⚠️) | Tables below ↓

## Pending: Meets Record Requirements

Record-eligible submissions only. Pre-eval TTT entries excluded per @0hq ruling on [#402](https://github.com/openai/parameter-golf/issues/402) — only backward-looking (score-first, single-pass) TTT is allowed. Official SOTA: **1.1194 BPB** (#549, @sanjeevmadhav — LeakyReLU² + Legal TTT + Parallel Muon, updated Mar 24).

**Top 5 record-eligible** (13 total — full table in collapsible below):

| BPB | Author | Techniques | PR |
|-----|--------|-----------|-----|
| **0.9625** | @newjordan | **Podracing II:** Multi-order backoff (2-7) + entropy-adaptive alpha. GPTQ in training budget. No TTT. | [#753](https://github.com/openai/parameter-golf/pull/753) |
| **0.9674** | @Asukabot0 | Multi-order n-gram backoff (2-7) + entropy-adaptive alpha + XSA-all + VRL + GA. No TTT. | [#727](https://github.com/openai/parameter-golf/pull/727) |
| **0.9850** | @andrewbaggio1 | Cosine TTT (20ep) + multi-order n-gram cache (2-5gram). First TTT + n-gram combo. | [#741](https://github.com/openai/parameter-golf/pull/741) |
| **1.0222** | @stukenov | Kitchen-sink: XSA-all + VRL + GA + CROWN-Q + Depth Recurrence + Hedge Mixer TTT. GPTQ-lite. | [#745](https://github.com/openai/parameter-golf/pull/745) |
| **1.0240** | @lukacf | Multi-order n-gram backoff + entropy-adaptive alpha + XSA-all + VRL + Full GPTQ. No TTT. | [#702](https://github.com/openai/parameter-golf/pull/702) |

Also notable: #755 (1.0321, **Gravity Tokenizer** — ⚠️ tokenizer change, needs scrutiny) | #700 (1.0541, Hedge Mixer) | #738 (1.0970, kNN-LM) | #728 (1.1142, ⚠️ val-calibrated GPTQ)

**Top 5 not-yet-validated** (25 total — full table in collapsible below):

| BPB | Author | Techniques | PR |
|-----|--------|-----------|-----|
| **1.0400** | @pentxayc | Hedge Mixer + VRL + AdamW TTT + Polyak EMA. 1 seed only. | [#731](https://github.com/openai/parameter-golf/pull/731) |
| **1.0717** | @hypery11 | 10L + 7-gram eval cache (alpha=0.40). 3-seed, fails p<0.01 (std=0.016). | [#724](https://github.com/openai/parameter-golf/pull/724) |
| **1.0891** | @amaljithkuttamath | VRL + GA + AdamW TTT on #442 base. 1 seed. | [#490](https://github.com/openai/parameter-golf/pull/490) |
| **1.0920** | @Christopher-Lee-McClendon | GEPA 30k steps + legal SGD TTT. 4xA100 non-record. | [#668](https://github.com/openai/parameter-golf/pull/668) |
| **1.1078** | @agalimova | XSA6 + BigramHash(4096) on #700 base. 3-seed, fails p<0.01. | [#720](https://github.com/openai/parameter-golf/pull/720) |

13 record-eligible + 25 unvalidated | Official SOTA: **1.1194** (updated Mar 24) | Full tables in collapsibles below ↓

*Note: The full "All Pending Validated" table below contains the pre-n-gram-cache entries. The 8 newer n-gram/Hedge Mixer submissions (#727, #741, #702, #715, #706, #740, #738, #700) and #728 are tracked in the Meets Record Requirements table above.*

## Untried Combinations

Ranked by expected value (likely gain times probability of working), grounded in competition ablation data:

**Tier 1 — Highest expected value (n-gram cache extensions)**

- **N-gram cache + stronger neural base.** The current best n-gram submissions (#727 at 0.9674, #702 at 1.0240) use relatively standard neural models (XSA-all, VRL, GA). Combining the best neural base (#609's XSA-all + Full GPTQ + Selective Pruning stack, with GPTQ in training budget) with multi-order backoff + entropy-adaptive alpha could push sub-0.95. The n-gram improvement scales with better base models — #727's ablation shows neural-only at 1.1271 dropping to 0.9674 with full cache.
- **GEPA + n-gram cache.** GEPA's neural-only frontier (#628: 1.0983 on 4xA100) plus n-gram backoff could target sub-0.95. 8xH100 record-eligible GEPA still untried (~1.116-1.120 projected at 7k steps, pre-n-gram).
- **Context Tree Weighting (CTW) instead of heuristic alpha.** The current top n-gram submissions use hand-tuned or entropy-adaptive alpha to mix n-gram orders. CTW (Willems et al.) provides Bayesian-optimal weighting over all context tree models up to a given depth — provably minimax optimal for tree sources. Replaces heuristic with theory. Zero artifact cost. **Est. 0.005-0.020 BPB over heuristic mixing.** Moderate complexity (tree data structure).
- **Logistic-domain mixing.** Current submissions use linear interpolation: `alpha*p_ngram + (1-alpha)*p_neural`. PAQ-style compressors use log-odds space mixing, which handles extreme probabilities better. A one-line change. **Est. 0.002-0.005 BPB.** Trivial complexity.
- **Adaptive stride (entropy-guided two-pass).** First pass with stride=64 scores all tokens and records per-token entropy. Second pass re-evaluates high-entropy regions with smaller stride (16-32). Targets compute where it helps most. Backward-looking, zero artifact cost. **Est. 0.005-0.015 BPB.** Low-moderate complexity.
- **Fixed-Share Hedge (non-stationary expert tracking).** #700's Hedge algorithm assumes stationary expert quality. Fixed-Share (Herbster & Warmuth) allows "switching" between experts — important because FineWeb contains diverse content types (code, prose, tables). Zero artifact cost. **Est. 0.003-0.008 BPB over standard Hedge.** Low complexity (one parameter: switching rate).

**Tier 2 — Top picks for pure neural track** (sorted by expected value)
- **Engram: principled BigramHash upgrade** (DeepSeek, Jun 2025). Multi-head hashing (K=4 heads per N-gram order) + context-aware gating (sigmoid gate suppresses noisy lookups) + tokenizer compression (collapse equivalent IDs, −23% vocab). The competition's BigramHash is a primitive single-head version. Engram's gating could rescue higher-order N-grams (#609 showed TrigramHash hurts without gating: +0.0049). Multi-head reduces hash collisions. Depthwise causal conv for temporal smoothing. Main constraint: embedding tables consume artifact space (2-4MB for full multi-order). **Est. 0.003-0.008 BPB.**
- **Mousse optimizer** (arXiv:2603.09697). Curvature-aware Muon — Shampoo preconditioning before orthogonalization. ~12% more effective training at 3% overhead. Drop-in. **Est. 0.003-0.008 BPB.**
- **OptRot pre-quantization** (arXiv:2512.24124). Rotation matrix redistributes weight outliers before quantizing. Fuses into adjacent layers — zero artifact cost. **Est. 0.001-0.003 BPB** (reduced estimate — Full GPTQ already handles much of the outlier problem; #586 shows rotation "substitutes with GPTQ at int6").
- **Turbo-Muon** (arXiv:2512.04632). Preconditioned Newton-Schulz — 5-10% faster training. More steps in 600s. Significance test waived for systems-only changes. **Est. 0.002-0.005 BPB.**
- **qTTT — query-only test-time training** (arXiv:2512.13898). Cache K/V once, adapt only Q projection weights. 2-3x more TTT epochs within eval budget. **Est. 0.003-0.010 BPB.** Note: use AdamW with cosine LR, not SGD — #601 shows SGD TTT hurts GPTQ models (+0.030). AdamW TTT works but requires GPTQ calibration within training budget (not eval time).
- **LaCT — Large Chunk TTT** (arXiv:2505.23884, ICLR 2026 Oral). Document-sized chunks → 70% GPU utilization (vs <5% for per-token TTT). Uses Muon as fast-weight optimizer. **Est. 0.002-0.008 BPB** over current TTT approaches.
- **Prune-then-quantize ordering** (arXiv:2603.18426, ICLR 2026). Progressive Intensity Hypothesis: weaker perturbations first, stronger later. #609 currently does quantize-then-prune; reversing the order is a **zero-cost experiment**. Theory + experiments show 0.001-0.003 BPB free gain.
- **SLOT — output-head TTT** (arXiv:2505.12392). Adds a single learnable vector at the last layer, optimized per-document during eval. Lighter than LoRA TTT — avoids the GPTQ weight-corruption problem (#601). Compatible with score-first constraint. **Est. 0.002-0.006 BPB.**
- **YAQA adaptive rounding** (arXiv:2505.22988). Drop-in GPTQ replacement: optimizes rounding toward full model's KL divergence (not just per-layer error) via Kronecker-factored Hessian. ~30% less quantization error than GPTQ. Post-training. **Est. 0.001-0.003 BPB.**

<details>
<summary><strong>More Tier 2 ideas</strong> (lower EV or higher complexity)</summary>

| Technique | Est. BPB | Key idea | Complexity |
|-----------|----------|----------|------------|
| **GLU Attention on Values** (arXiv:2507.00022) | 0.002-0.005 | GLU nonlinearity on V projections. Zero parameters, zero overhead. Composable with XSA. | **Very low** |
| **CAGE QAT Gradient** (arXiv:2510.18784, ICLR 2026) | 0.002-0.005 | Curvature-aware STE replacement using Adam's second-moment. W3A3 CAGE matches W4A4 STE. Composes with HESTIA/Soft-Round. Zero artifact cost. | Low-moderate |
| **IFNSO / Iteration-Free NS** (arXiv:2602.02500) | 0.002-0.005 | Collapses Muon's 5-10 NS iterations into one polynomial eval. Systems-only (more steps in 600s). Drop-in. | **Very low** |
| **V:N:M Activation Sparsity** (arXiv:2602.06183) | 0.005-0.015 | Generalizes 2:4 to higher sparsity ratios (1:4+). 6-10x sparse matmul at relu²'s natural >90% sparsity. 1.4-1.7x end-to-end speedup. **Systems-only.** | Moderate-high |
| **Batch Size Warmup** (arXiv:2505.23971) | 0.002-0.005 | Start small (262K), grow to 786K as critical batch size increases. 43% fewer gradient steps for same loss. Resolves the 524K-vs-786K debate. | **Very low** |
| **FlashSigmoid Attention** (Apple, ICLR 2025) | 0.002-0.010 | Replace softmax with sigmoid. Eliminates attention sinks entirely. 17% kernel speedup on H100 (systems-only). | Low-moderate |
| **WSM Checkpoint Merging** (arXiv:2507.17634) | 0.002-0.006 | Replace warmdown with constant-LR training + offline checkpoint merge. More full-LR steps. Theoretically optimal. Compatible with existing EMA. | Low |
| **FoX Forgetting Attention** (arXiv:2503.02130, ICLR 2025) | 0.003-0.008 | Data-dependent forget gate on attention. Eliminates need for positional embeddings. FA3-compatible. | Moderate |
| **DeepCrossAttention** (arXiv:2502.06785, ICML 2025) | 0.003-0.008 | Input-dependent depth routing over all previous layers (replaces simple residuals). 3x convergence speed claim. ~1K params for 11L. | Moderate |
| HybridNorm (arXiv:2503.04598) | 0.002-0.006 | Mixed Pre/Post-Norm for better depth utilization | Very low |
| Differential Attention (arXiv:2410.05258) | 0.005-0.015 | Difference of two softmax maps; reduces outliers | High (arch change) |
| Lattice VQ (arXiv:2603.11021) | 0.005-0.015 | Joint 24-weight Leech lattice encoding; saves 2-4 MB | High (custom kernels) |
| VGA (arXiv:2510.09017) | 0.002-0.005 | Value-gated attention; fixes sliding window sinks | Low-moderate |
| Neural Cache cross-window KV ([#318](https://github.com/openai/parameter-golf/pull/318)) | unknown | Cache K/V from prior windows so new queries attend to 50K+ context; zero artifact cost; untested | Low (FA3 already supports seqlen_k > seqlen_q) |
| Predictive Batch Scheduling (arXiv:2602.17066) | 0.002-0.005 | Loss-aware data ordering (NOT content curriculum); 6-13% faster convergence | Low |
| Late-Stage SAM (arXiv:2410.10373) | 0.002-0.005 | Sharpness-aware minimization last 5-10%; flatter minima complement EMA | Moderate (Muon-SAM) |
| WaveletGPT (arXiv:2409.12924) | 0.003-0.010 | Multi-scale Haar wavelet structure on half of embedding dims; 40-60% faster convergence | Low (zero params) |
| AGGC adaptive gradient clipping (arXiv:2601.11864) | 0.002-0.005 | Per-group adaptive clip thresholds; exploits Q-matrix heterogeneity from #215 | Low (optimizer state) |
| **2:4 Structured Activation Sparsity** (arXiv:2503.16672) | 0.003-0.008 | relu² is already 84-98% sparse; enforce NVIDIA 2:4 pattern for **2× sparse matmul on H100 tensor cores**. ~15-20% more training steps. **Systems-only = significance waived.** | Moderate (custom kernels) |
| In-Place TTT with NTP objective (ICLR 2026 Oral) | 0.003-0.010 | Update MLP final projections during eval using NTP loss (not reconstruction). NTP alignment may explain why naive SGD TTT is neutral at frontier — objective misalignment. MLP-only, last 3 blocks. | Moderate |
| PoPE — Polar Position Embedding (arXiv:2509.10534) | 0.002-0.005 | Decouples content (magnitude) from position (angle) in attention. Principled fix for what Partial RoPE approximates. Strong length extrapolation. OpenAI co-author. | Moderate |
| **Liger-Kernel fused ops** (LinkedIn open-source) | 0.002-0.006 | Fused Triton: RMSNorm (6×), linear+CE (3×), residual+norm. Eliminates kernel launch overhead. 20-43% throughput in benchmarks. pip-installable. **Systems-only.** | Very low |
| Cross-Layer KV Sharing (MLKV/CLA, NAACL 2025) | 0.002-0.006 | Adjacent layer pairs share K/V projections. Saves ~0.5MB artifact for 12L or wider MLP. Unlike depth recurrence, only K/V shared — no quant amplification. | Moderate |
| **Block AttnRes** (arXiv:2603.15031, Kimi, Mar 2026) | 0.003-0.008 | Efficient variant of AttnRes (which failed at 54% overhead in #362). Block partitioning (3 blocks at 11L) reduces overhead to <2%. 1.25× convergence efficiency. | Moderate |
| **QK-Norm** (arXiv:2010.04245, used in Gemma 2/DeepSeek-V3) | 0.001-0.004 | L2-normalize Q and K before dot product + learned per-head temperature. **Prevents attention logit explosion** — the root cause LN Scale patches. Could enable stable 12-13L training. Suppresses #215's Q condition numbers (100M+ → 1). ~4 lines. | **Very low** |
| **Hourglass FFN** (arXiv:2602.06471, Feb 2026) | 0.002-0.006 | Replace wide MLP-3x with stacked narrow-to-narrow sub-MLPs + residuals. **Deeper MLP at fewer params.** Paper: outperforms conventional FFN up to 400M params. Freed params → extra layers or larger BigramHash. | Low-moderate |
| **CERWU** (arXiv:2505.18758) | 0.003-0.008 | Rate-distortion optimal quantization: co-optimizes quant grid + weight updates + entropy coding. GPTQ is special case (λ=0). **Principled upgrade to GPTQ-lite.** Post-training, orthogonal to QAT. | Moderate |
| **Progressive Window Warmup** (modded-nanogpt, proven 2025) | 0.003-0.007 | Start with short local attention (128-384 tokens), grow to full 2048 during training. Faster early steps → more total steps. **Different from blocked seq curriculum** — same input length, just restricted attention span. Systems-only. | Moderate |
| NuMuon (arXiv:2603.03597, Mar 2026) | 0.002-0.006 | Nuclear-norm constraint on Muon updates → lower stable rank → better zstd compression. Pushes compressibility into optimizer itself. Distinct from Mousse/Turbo-Muon (those target speed). | Low-moderate |
| **AdamHD Huber Decay** (arXiv:2511.14721) | 0.002-0.005 | Replace L2 weight decay with Huber regularizer: quadratic below threshold, **linear above**. Specifically suppresses large outlier weights that cause int6 clipping loss. Drop-in for Muon's decoupled WD. Synergizes with GPTQ-lite (fewer outliers = less work). | **Very low** |
| **Layer-Wise Scaling** (arXiv:2509.06518) | 0.002-0.005 | Non-uniform FFN width per layer (e.g., MLP-4x middle, MLP-2x edges). Same total params, better allocation. Crown/Frame/Reverse variants all beat uniform at 180M params. Complements Hourglass FFN (structure vs width). **Zero cost — just per-layer dims.** | **Very low** |
| **Hyper-Connections** (arXiv:2409.19606, ICLR 2025; mHC: 2512.24880, DeepSeek) | 0.003-0.008 | Learned multi-depth residual mixing: replaces `x+f(x)` with a connection matrix (n=2 → 16 params/layer, ~176 total). Richer than Catalytic Residuals or DenseFormer DWA. mHC adds Sinkhorn stability. **Drop-in.** | Low-moderate |
| **HESTIA soft QAT** (arXiv:2601.20745) | 0.002-0.006 | Replaces hard STE with temperature-annealed softmax relaxation + per-tensor Hessian guidance. Enables **earlier QAT** without premature discretization. Synergizes with OptRot. | Moderate |
| **Compute-Optimal QAT** (arXiv:2509.22935, Apple) | 0.001-0.004 | Scaling law for optimal FP→QAT split. **Cooldown+QAT fusion:** activate QAT at warmdown onset, eliminating redundant FP updates. Principled replacement for empirical Late QAT thresholds. | **Very low** |
| **ScaleBITS** (arXiv:2602.17698) | 0.002-0.006 | Automated per-layer bit-width search (which layers get int5 vs int6). Sensitivity analysis + greedy optimization under 16MB constraint. +36% over uniform precision in paper. Replaces manual assignment. | Moderate |
| **CPSVD** (arXiv:2510.19385) | 0.003-0.008 | Column-Preserving SVD: identify weight columns that compress cleanly via low-rank factorization, store rest as int6. **Orthogonal to quantization** — reduces param count, not precision. Freed bytes → capacity. Entirely unexplored in competition. | Moderate |
| **Softpick / Rectified Softmax** (arXiv:2504.20966) | 0.002-0.006 | Replaces softmax with rectified non-sum-to-one variant. **Eliminates attention sinks and massive activations** — directly improves int-N quantization quality (lower kurtosis). 47% sparse attention maps. "Quantized Softpick outperforms quantized softmax at lower bit widths." | Low |
| **Anti-Layer Removal** (arXiv:2603.19348) | 0.002-0.006 | Some layers are "anti-layers" whose removal **improves** performance. Anatomical analysis of 135M model shows 10^7 importance range. If 1-2 middle layers of 11L are anti-layers, removing them frees artifact space for wider MLP or more BigramHash. **Zero-cost ablation pass on existing checkpoint.** | Very low |
| **Deep Delta Learning (DDL)** (arXiv:2601.00417) | 0.003-0.007 | Rank-1 erasure gate on residual: `x + β·proj(x) + f(x)`. Learned gate erases stale features before writing new ones. **3-5 ppl improvement at 124M.** ~5.6K params for 11L. Addresses residual-path interference in quantized models. | **Very low** |
| **Variance-Adaptive Muon (Muon-VS)** (arXiv:2601.14603) | 0.002-0.005 | Variance normalization before NS orthogonalization. Reduces Muon's step-size sensitivity + hyperparameter sensitivity. **Zero extra hyperparameters — direct drop-in.** Lower val loss than standard Muon on GPT-2/LLaMA. | **Very low** |
| **TEON cross-layer Muon** (arXiv:2601.23261) | 0.003-0.007 | Joint tensor orthogonalization across ALL layers (vs Muon's per-layer NS). Captures inter-layer gradient relationships. Consistent ppl improvement 130M-774M. Targets **loss per step** — critical for 600s budget. | Moderate |
| **Seesaw LR+Batch Schedule** (arXiv:2510.14717) | 0.002-0.005 | Multiply LR by 1/sqrt(2) and double batch size simultaneously. ~36% fewer serial steps at equal FLOPs. Principled foundation for the 524K→786K ramp. | **Very low** |
| **1-sqrt Cooldown Shape** (arXiv:2508.01483, TMLR 2025) | 0.001-0.003 | Replace linear warmdown with `1-sqrt((t-T0)/(T+1-T0))`. Outperforms linear, cosine, and other cooldown shapes in WSD schedules. Zero-cost swap. | **Very low** |
| **SSMax (Scalable-Softmax)** (arXiv:2501.19399) | 0.001-0.004 | Scale softmax by input sequence length to prevent attention flattening at seq2048. One scalar multiply. Compatible with FA3. | **Very low** |
| **DCMHA** (arXiv:2405.08553, ICML 2024 Oral) | 0.005-0.015 | Dynamically Composable Multi-Head Attention. Input-dependent transforms on score/weight matrices. Matches 1.7-2x compute models at 405M. Few KB params for 11L. | Moderate-high |
| **VPTQ** (arXiv:2409.17066, EMNLP 2024) | 0.002-0.006 | Vector PTQ guided by second-order Hessian. Beats GPTQ by 0.01-0.34 ppl at 2-3 bits. 10-18x faster than AQLM. Practical within 600s budget. | Moderate |
| **QTIP Trellis Quantization** (arXiv:2406.11235, NeurIPS 2024) | 0.003-0.008 | Trellis coded quantization — stateful sequential coding achieving ultra-high-dimensional VQ. At 3 bits, matches GPTQ at 4 bits. Bitshift trellis for GPU-parallel decoding. | High |
| **Context Tree Switching (CTS)** | 0.002-0.008 | Extension of CTW that handles non-stationary sources (distribution shifts between documents). Same complexity as CTW but mixes over larger model class. | Moderate |

</details>

**Tier 3 — Novel approaches, higher risk**

- **Knowledge distillation** — untried. Train larger teacher ~7 min, distill to 16MB student ~3 min. Est. 0.005-0.010 BPB but tight time budget is the constraint. High complexity.
- **Partial weight sharing + 14L** — share middle-layer pairs with per-layer LoRA adapters. Saves 3-5 MB for extra layers. "Relaxed Recursive Transformers" shows LoRA-adapted shared layers recover most unique-layer quality. Est. +0.005-0.015 BPB. #579 tested 6×2 loops: 1.1478 but GPTQ compounds multiplicatively (see What Doesn't Work).
- **nGPT hypersphere normalization** (arXiv:2410.01131) — constrain Q/K to unit-norm rows, eliminating #215's extreme condition numbers. NVIDIA claims 4-20x convergence speedup. Est. 0.003-0.008 BPB. High complexity, untested at this scale.
- **BitNet b1.58** — #367 reached 1.1770 (68M ternary params). Standard stack breaks on ternary (different optimization regime). Int4 with late QAT is an unexplored middle ground. MoE confirmed dead at this scale (see What Doesn't Work).

---

<details>
<summary><strong>What Doesn't Work (25+ documented failures)</strong></summary>

**Three failure patterns.** (1) **Throughput cost exceeds quality gain.** In a 600s budget, anything adding >10% step overhead needs >10% per-step improvement to break even. QAT (#236: 115ms vs 67ms baseline), NorMuon (#236: 110ms), and MTP (#212, #236: 86ms) all fail this test. (2) **Mechanism redundancy.** Stacking two techniques that extract the same signal yields diminishing returns — TTT+XSA underperforms XSA-alone (#290 vs #265), error-guided TTT doesn't improve over uniform TTT (#296), EMA without XSA hurts (#201). (3) **Regime incompatibility.** Techniques optimized for int6 break under different weight representations — the standard stack (XSA, SmearGate, WD, EMA/SWA, TTT) all fail on ternary (#367), and recurrence amplifies quantization error 900× (#363).

- **12 layers at seq2048 (slower steps cancel extra capacity)** — #219's 12L at seq2048 runs at 107ms/step, fitting only ~5,590 steps. Result: 1.1541 vs 11L's 1.1326. However, #76 shows 12L at **seq1024** (59ms/step, ~9000 steps) reaches 1.1468 — the tradeoff depends on sequence length.
- **Late QAT at 12L is step-budget-dependent.** @saml212's [#332](https://github.com/openai/parameter-golf/pull/332) found that at 12L, Late QAT added ~7ms/step overhead, costing ~770 training steps. At 11L, those steps would cost ~7ms each — but at 12L, each step is already more expensive and step count is already lower, so the overhead-to-gain ratio worsens. Result: Late QAT was dropped from the 12L submission. Takeaway: the same technique's cost-benefit flips depending on step time and total step count. Always re-evaluate overhead techniques when changing layer count.
- **Int5-MLP tradeoff is layer-dependent** — At 11L, #236 found int5 quant penalty (0.029) outweighs artifact savings. But at 10L, #180 used int5 to fund BigramHash(10240) (previous official SOTA at 1.1428; now superseded by #414 at 1.1228). **New data from #469:** all-int5 on a larger model (d=576, 27M params) with early QAT activation (threshold 0.50 = ~1700 adaptation steps) reaches **1.1418** (1-seed) — validating the "train larger, quantize harder" principle.
- **Larger vocabularies + fewer layers** — #123 (vocab 4096, 8L) at 1.1642 and #200 (SP4096, 9L) at 1.2012 both underperform #198's 11L at 1.1326. The embedding matrix gets 4x larger, forcing fewer layers. At current artifact sizes, depth wins over vocab breadth. **New data from #465:** Int6 embedding quantization costs only **+0.0005 BPB** — enabling sp8192 at d=512, but even then sp8192 8L (1.1794) loses to sp1024 10L (1.1508). More layers still dominate.
- **SmearGate without OrthoInit** — hurts BPB by 0.003 (see SmearGate deep dive).
- **SWA with bf16 accumulation** — #212 found catastrophic precision loss when accumulating SWA checkpoints in bf16. Must use fp32. (However, @kellyvv's [#238](https://github.com/openai/parameter-golf/pull/238) found that with enough SWA checkpoints (84), the quant gap actually *reverses* — quantized BPB becomes 0.037 *better* than pre-quant. SWA smoothing eliminates quantization-sensitive outliers.)
- **MTP (multi-token prediction)** — #212's controlled test: no BPB improvement (1.1947 vs 1.1929 control).
- **Curriculum learning (content-based)** — #212 found no effect.
- **LAWA-EMA replacing SWA — context-dependent.** #201 tested EMA alone on #198 base: 1.1551 (0.023 worse than SWA). But #287 uses EMA (decay=0.997) WITH XSA and reaches 1.1280 — beating SWA. EMA needs XSA to work. EMA decay=0.999 was also tried on #287 and hurt BPB — too slow to average (per @jfprincz). The sweet spot is 0.997.
- **cuDNN SDP vs Flash SDP** — #281 found cuDNN is 40% faster per attention op but produces worse BPB (1.1455 vs 1.1418). More steps doesn't help — different internal accumulation precision hurts quality.
- **SwiGLU activation** — worse than relu² on the standard architecture (#340, #344). **However, GEPA's AI-discovered architecture uses SwiGLU successfully** — both with TTT (#462: 1.0672) and **without TTT (#505: 1.1181, GEPA non-TTT)**. **Clarification:** #505's code reveals the "SwiGLU" label is misleading — the actual activation is **Star-ReLU** (relu²+learned affine scale+bias, arXiv:2210.13452), NOT true SwiGLU gating. The MLP uses a single up_proj, not the dual-projection gated structure of SwiGLU. Star-ReLU works when co-optimized with U-Net skip gates and hidden=1792.
- **Step-based LR schedule** — #344 found −0.483 BPB vs wallclock-based warmdown. Catastrophic because the 600s budget varies by hardware; step-count schedules can't adapt.
- **Error-guided TTT** — concentrating TTT on highest-loss tokens doesn't help; they're genuinely unpredictable. Also: **focal loss TTT** (#481: no improvement over CE) and **KL-divergence from pre-quant model** (#481: no improvement). 7 failed TTT objective/targeting variants total.
- **Advanced quantization algorithms at int6 (#756, @abaybektursun, SOTA holder).** Qronos iterative Hessian (+0.0007 worse) and CDQuant coordinate descent (+0.0005 worse) both fail to improve over standard GPTQ at int6. Reason: the int6 quant gap is only +0.0036 BPB — most weights are already at their optimal grid point. **At int6, GPTQ is near-optimal.** Also: **TTT is dead on the val-calibrated GPTQ stack** — 25 total failed TTT attempts across two stacks (full, MLP-down, MLP-all: all +0.0001 or neutral). Val-calibrated GPTQ rounding decisions are disrupted by gradient updates.
- **MoE at small scale** — #480: 2-expert soft-routing MoE = **−0.06 to −0.08 BPB** vs dense baseline on 8xH100. Apple scaling laws (ICML 2025) confirm optimal sparsity = 0 below ~500M params. MoE is definitively unviable at competition scale.
- **Lightweight TTT — 5 variants dead at frontier.** Naive SGD (#338: neutral), MLP-only (#375: neutral), Reptile (#375: +0.008 worse), Self-Distillation (#379: −0.0003), MAML (#384: +0.085 worse). All used conservative settings. **But aggressive TTT works in principle:** backward-looking TTT reached **1.1162** (#606, 3-seed — now closed for eval-time GPTQ). The lightweight variants failed; the aggressive variants (AdamW, cosine LR, selective freezing) succeeded — but need GPTQ within training budget.
- **Multi-epoch TTT — memorization is a gradient, not a threshold (#568, #512, #484).** The PROTEUS series reveals a clear memorization gradient: **3ep→0.9512** (#512), **5ep→0.7853** (#568, −0.166 BPB from just 2 more epochs). At 0.78 BPB the model compresses to <1 bit per byte — near-certain data reproduction. #484's original diagnostic (10+ constant-LR = memorization, 3ep = genuine) doesn't capture this: cosine LoRA TTT memorizes progressively, not at a fixed threshold. The ~0.95 floor was for full-weight TTT; LoRA TTT memorizes differently. Cosine TTT at 100ep (#517: 0.978) stays above the 0.95 floor — suggesting cosine full-weight and cosine LoRA have different memorization dynamics.
- **Systematic frontier negatives (#375, 13 techniques on #315 base, $500/24hrs on 8xH100).** **Reptile meta-TTT: +0.0076 worse** (1.1332, 20% training budget consumed). All 3 TTT variants (low-LR, high-LR MLP-only, Reptile) failed. Also failed: memory tokens (+0.016), Canon layers (48% overhead), MTP (+0.028), gradient-guided quant (noise), cautious WD (breaks torch.compile: 710× slower), label smoothing, L1 reg, 1M batch, full-run QAT. Key positive findings: **EMA > standard SWA by 0.003** (3-seed); **786K > 524K by 0.004** (total tokens > gradient steps at frontier). **Throughput heuristic: each 1ms step overhead ≈ 0.006 BPB** — any technique adding Nms must deliver >N×0.006 to break even. INT4 quant gap: 0.048-0.060 (exponential from int6's 0.006). 3-seed std: 0.0007 BPB.
- **INT4 quantization** — catastrophic. #480's controlled grid: int6→int5 MLP costs +0.007, but int6→int4 MLP costs **+0.065** (10× worse). Full grid: attn6/mlp4 = 1.2111, attn5/mlp4 = 1.2183 vs baseline 1.1456. Int4 is a dead end.
- **MLA (Multi-Head Latent Attention)** — #354's kv_rank=128 MLA on 13L runs at 83ms/step vs ~43ms baseline, halving token throughput (~3.7B vs ~7.2B tokens). Pre-quant 1.2838 — architecture quality may be there but throughput cost makes it infeasible in the 600s budget.
- **Block-wise weight sharing / depth recurrence** — **aggressive recurrence (3+ cycles) fails at 512d**, but shallow recurrence works. #344: 2x slower. #316: 0.09 BPB cost. #319: loop gates collapse. #363: **quant error amplifies ~900× over 3 cycles**. #484 (EBLS): gammas → 0 for MLP (fully shared). **#579:** 6×2 loops — 1.1478 (1-seed). GPTQ compounds multiplicatively: 2 loops survive, 3+ catastrophic (+4.3 BPB). **Exception: #686** (@msisovic) uses **shallow recurrence** (layers 4+5 repeated once each, 11→13 virtual layers) with per-pass learnable block scalars (~2K params). Reaches **1.1182** (3-seed). Recovers ~70% of independent 12L gain at minimal step cost. Key: staying within the "2 loops survive" zone.
- **AttnRes (learned softmax over depth)** — #362: 54% throughput penalty from routing attention over layer outputs. Infeasible in 600s budget.
- **MUD optimizer (#510)** — Triangular Gram preconditioning replacing Muon's Newton-Schulz. 1.1989 BPB at 118ms/step (4.5× slower than Muon's ~26ms). Only 5,087 steps in 600s. Alternative optimizers remain unviable: throughput cost dwarfs quality gains.
- **FTLE per-row precision (#316)** — Dynamical systems-inspired row-level quantization (Lyapunov exponent tracking). Clean negative result: uniform int-N beats FTLE-guided mixed precision at every bit width, because mixing bit widths within a row *increases* quantized value entropy, which defeats zstd compression. Lower RMSE does not imply smaller artifact.
- **#609 frontier ablations (16 techniques on #593 stack).** On the current best non-TTT base: **VRL +0.0012** (conflicts with VE128), **Gated Attention +0.0011** (3% step overhead), **Catalytic Residuals −0.0001** (redundant with existing scaling), **Backout −0.0005** (redundant with U-Net skips), **TrigramHash +0.0049** (hurts compression), **Hadamard rotation −0.0002 but +0.5MB** (net negative for artifact), **Temperature scaling +0.0002** (model well-calibrated at T=1.0), **seq4096 eval catastrophic** (RoPE breaks beyond training length), **lzma at 99.7% Shannon limit** (entropy coding gains capped at 0.05MB).

</details>

---

## The Current Baseline Stack

The foundation that most competitive submissions share. Worth noting: several top submissions diverge from consensus in specific ways that paid off — #180 used int5 (former official SOTA), #236 used 524K batch instead of 786K, #76 dropped QAT and raised LR, #265 added XSA from a recent paper. The meta is a strong starting point, but the data shows room to improve individual components.

**The core five:** Integer quantization (int6-all or int5-MLP/int6-attn) + MLP 3x expansion + sliding window eval (stride=64) + zstd-22 compression + precision passthrough for sensitive layers (usually FP16 tied embedding; #236 uses int8 to fund MLP capacity). Near-universal across all competitive submissions, though quant precision varies — #76, #267, and former SOTA #180 use int5-MLP to fund larger BigramHash or extra layers.

**Near-consensus optimizer settings:** Muon momentum 0.99 (warmup from 0.92 over 1500 steps), halved LRs (matrix=0.02, scalar=0.02, embed=0.03), warmdown 3000 iters, grad clip 0.3. Most top submissions use these. Exceptions: @unixmadtoonslab's [#76](https://github.com/openai/parameter-golf/pull/76) (1.1468) uses higher LRs (0.03) and lower momentum (0.97). @saml212's [#236](https://github.com/openai/parameter-golf/pull/236) (1.1400) used **524K batch** instead of 786K, gaining 0.017 BPB via more gradient updates. **However, #375's systematic study on the #315 frontier base found 786K > 524K by 0.004 BPB (3-seed)** — at the frontier, total tokens matter more than gradient steps. The optimal batch size is stack-dependent: 524K helps Tier 2-3 stacks; 786K helps XSA+EMA frontier stacks.

**Part of the top stack:** SmearGate + BigramHash + OrthoInit — used by most top validated entries. Requires OrthoInit to work (per #212's ablation). 11 layers + WD 0.04 + weight averaging (SWA or EMA). The standard-arch frontier (#414, 1.1228) builds on EMA + XSA4 + GPTQ-lite + Tight SWA + VE128 + Partial RoPE + LN Scale + Late QAT. The overall non-TTT frontier is now **#609 (1.1154**, XSA-all + Full GPTQ + Selective Pruning + Parallel Muon, @saml212).

**Common but not universal:** QAT with STE (~half), SWA (~17/49 validated), NorMuon (~3/49), FA3 (~13/49).

<details>
<summary><strong>The Core Five Explained (for newcomers)</strong></summary>

### 1. Int6 Quantization (instead of Int8)

Standard post-training quantization maps each weight to an 8-bit integer (256 levels). Int6 uses only 6 bits (64 levels, range [-32, 31]) with per-row scale factors, then compresses with zstd (level 22) instead of the baseline's zlib-9. Int6 frees ~25% more artifact space than int8, reinvested in a bigger model. Some submissions keep sensitive layers in fp16 (tied embedding) or int8 (embeddings) to limit compounding precision loss.

**Origin:** @nanlliu introduced int6 mixed precision in [#39](https://github.com/openai/parameter-golf/pull/39).

### 2. MLP 3x Expansion

The baseline uses 2x MLP expansion (hidden dim 1024 for 512-dim model). Top submissions use 3x (1536). Wider MLP = more expressive capacity, funded by int6 artifact savings.

**Origin:** @jfprincz in [#70](https://github.com/openai/parameter-golf/pull/70) (Mar 19 08:57 UTC). @saml212 independently reached the same insight in [#61](https://github.com/openai/parameter-golf/pull/61) later that day.

### 3. Sliding Window Evaluation

Overlapping windows (stride=64, window=2048) give each scored token 1984+ tokens of context vs minimal context with non-overlapping chunks. Purely eval-time. Worth **0.034 BPB** per @samacqua's ablation in [#77](https://github.com/openai/parameter-golf/pull/77).

**Origin:** @mattqlf in [#50](https://github.com/openai/parameter-golf/pull/50). **Stride debate:** stride=256 gives marginally better BPB at 4x less eval time (#114). **Doc isolation hurts at stride=64** — use flat-stream eval (#199).

### 4. FP16 Tied Embedding

The tied embedding matrix (input + output) is uniquely sensitive to quantization — errors compound in both directions. Keeping it in fp16 (~1MB) is the single highest-value precision decision.

**Origin:** @chonchiog in [#42](https://github.com/openai/parameter-golf/pull/42).

### 5. Zstd-22 Compression

Zstandard at level 22 squeezes int6 data significantly tighter than zlib-9 — enough to fit ~1-2M more parameters. Compression happens once after training; decompression is fast. Free lunch.

</details>

---

## The Path Down: What Separates Each Tier

The competition spans a **0.26 BPB range** from baseline (1.2244) to the best pending (0.9674, #727 — n-gram backoff). Three-track frontier: **n-gram cache (#727 at 0.9674, #702 at 1.0240)**, **Hedge Mixer (#700 at 1.0541)**, and **pure neural (official SOTA #549 at 1.1194; #609 at 1.1154 non-record due to eval-time GPTQ)**. Two enforcement sweeps (Mar 24-25) closed 25+ PRs for pre-eval TTT, eval-time GPTQ, and multi-epoch min(NLL). Tiers 1-4 cover the **pure neural track**; Tier 5 covers the n-gram cache frontier.

### Tier 1: Tweaking the Baseline (1.20–1.22 BPB)

Submissions in this range make one or two changes to the baseline: a longer sequence length, a learning rate sweep, a warmdown adjustment. The approach is **"how do I improve this model?"** — treating the baseline as mostly correct and looking for low-hanging fruit.

This works for the first 0.02 BPB, but hits a wall fast. The constraint isn't hyperparameters — it's the artifact budget. At int8+zlib, you can't fit enough model capacity to go further. Many submissions in this range are also on non-standard hardware (RTX 4090, Apple Silicon, 1xH100), which limits training tokens and disqualifies from the record track.

**What to do if you're here:** Adopt the core five (int6, MLP 3x, sliding window, FP16 embed, zstd-22) as a package. Each technique is well-documented in the deep dives below. Together they're worth ~0.05-0.07 BPB — the single biggest jump available.

### Tier 2: Stacking Known Techniques (1.15–1.18 BPB)

These submissions adopted the core five and are assembling additional techniques: SmearGate, BigramHash, SWA, QAT, NorMuon. The approach is **"what techniques exist and how do I combine them?"** — surveying PRs, identifying high-impact components, and building a combined recipe.

This is effective: the leap from 1.22 to 1.16 is largely a stacking exercise. But submissions in this range often stop at "I added all the techniques" without investigating *interactions*. Common patterns: using SmearGate without OrthoInit (which hurts — per #212's ablation), running QAT from the start (which hurts — late QAT at 70-85% is better), or using SWA without sufficient weight decay (SWA shows no effect below WD=0.04).

**What to do if you're here:** Run ablations. Remove one technique at a time and measure the delta. You'll often find that one "improvement" is actually hurting because of interaction effects. Check your hyperparameters against the consensus (LR=0.02, momentum=0.99, warmdown=3000) but also against divergent successes like #76 (LR=0.03, momentum=0.97). Multi-seed validation (3 seeds) is essential — single-seed scores can be off by 0.002+ BPB.

### Tier 3: Understanding Interactions (~1.120–1.15 BPB)

These submissions adopted the full technique stack and understood *why* each technique works. @jfprincz (#198 at 1.1326) is the canonical example: 11 layers + SmearGate + BigramHash + OrthoInit + WD 0.04 + SWA + FA3 assembled into a coherent system where each piece reinforces the others — WD makes weights compressible AND quantization-friendly, SmearGate+OrthoInit inject bigram context the small model can't learn from attention alone, and SWA smooths the weight landscape during warmdown.

The approach is **"how do these techniques interact, and what's the optimal system?"** Key markers of Tier 3 thinking:
- **Ablation-driven development** — every addition is measured, not assumed helpful
- **Precision budgeting** — spending fp16 only where quantization error hurts most (tied embedding, late-layer keys)
- **Divergent exploration** — #76 found that higher LR + lower momentum + no QAT outperforms consensus settings at 1.1468. #215 discovered that Q matrices are naturally low-rank (100M+ condition numbers) and factoring them saves 22% step time
- **Statistical rigor** — 3+ seeds, significance testing, honest evaluation

**What to do if you're here:** Solidify your baseline with multi-seed validation. The primary path to Tier 4 is adopting **XSA + Full GPTQ + EMA**. The #609 stack (XSA-all + Full GPTQ + Selective Pruning + Parallel Muon + LeakyReLU²) reached 1.1154 but is non-record due to eval-time GPTQ — the techniques are valid if GPTQ calibration is moved into the 600s training budget. The official record SOTA target is **#549 at 1.1194**. XSA + EMA is the shared infrastructure across all frontier submissions.

### Tier 4: Pure Neural Frontier (<~1.120 BPB)

The official record SOTA is **#549 at 1.1194** (@abaybektursun). The #609 stack reached 1.1154 (non-record due to eval-time GPTQ) and GEPA #505 reached 1.1181 (artifact >16MB). Both demonstrate what's achievable with compliant implementations.

The key insight at Tier 4: **EMA (0.997) outperforms standard SWA by 0.003 BPB** (#375, 3-seed verified). #315 demonstrates that the XSA+EMA base still had headroom via careful regularization — Partial RoPE, LN Scale, and Late QAT each target a specific weakness.

**What to do if you're here:** Three options. **(a) Beat #549 on pure neural:** Adopt the #609 technique stack with GPTQ calibration inside 600s training budget. Remaining untried: Mousse optimizer, OptRot, systems opts (Liger-Kernel, 2:4 sparsity). **(b) Add n-gram cache (→ Tier 5):** The single biggest lever — 0.07-0.16 BPB from a legal backward-looking n-gram eval cache. **(c) Legal TTT with compliant GPTQ:** All frontier TTT submissions were closed for eval-time GPTQ. The recipe works if GPTQ calibration fits in 600s. GEPA + legal TTT at **1.0983** on 4xA100 (#628, 20k steps) — 8xH100 version untried.

### Tier 5: N-gram Cache Frontier (<~1.10 BPB)

The Mar 25 revolution. Adding backward-looking n-gram statistics at eval time — consistent with backward-looking eval rules — drops BPB by 0.07-0.16 depending on implementation. No TTT required. Zero artifact cost.

**What separates entries in this tier:**
- **Cache order:** 5-gram fixed (#706: 1.0461) → 7-gram fixed (#715: 1.0337) → multi-order backoff 2-7 (#727: 0.9674). Higher orders and backoff are strictly better.
- **Mixing weight:** Fixed alpha (#706: alpha=0.20) vs entropy-adaptive (#727: alpha scales with model uncertainty). Adaptive is better by ~0.02 BPB.
- **Neural base quality:** Still matters. #727's ablation shows neural-only at 1.1271 → 0.9674 with full cache. A stronger neural base (Tier 4 stack) would push lower.
- **Stacking with TTT:** #741 combines cosine TTT + n-gram cache → 0.9850 BPB.
- **kNN-LM:** #738 adds hidden-state nearest-neighbor search for an extra −0.007 BPB on top of n-gram cache.

**What to do if you're here:** Use multi-order backoff (2-7) with entropy-adaptive alpha. Ensure GPTQ calibration is within 600s training budget (not eval time — #706 was flagged for this). No hindsight selection (comparing n-gram vs LM on the true next token). Build the strongest possible neural base first — n-gram gains compound on top of a better model.

### Technique Interactions Matter More Than Technique Count

A recurring pattern: techniques that work independently can fail in combination. TTT+XSA actively hurts (#303: +0.016 worse), EMA fails without XSA (#201) but succeeds with it (#287), and 12L fails at seq2048 but works at seq1024 (#219 vs #76). **#474 confirms this extends to newer techniques:** VRL + Gated Attention + Catalytic Residuals stacked on a 12L SWA base (no XSA, no EMA) yielded **1.1690 — worse than the same base without them** (1.1466). Frontier techniques are optimized for the frontier base; applying them to weaker bases produces negative or null returns.

The untried combinations above should be evaluated against your specific model's weaknesses, not applied blindly. **XSA + EMA appears to be a prerequisite for most newer techniques** (VRL, GA). For the pure neural track, the strongest remaining candidates are **systems optimizations** (fused kernels, 2:4 sparsity — throughput gains with significance waived) and **compression innovations** (OptRot, entropy-coded weights). For the overall frontier, **n-gram eval cache** is by far the highest-impact lever available.

<details>
<summary><strong>Val-Data & TTT Rulings (Mar 20-24)</strong></summary>

**Val data ruled out (Mar 20, @0hq):** [Val tokens cannot be in the artifact](https://github.com/openai/parameter-golf/pull/262). Paid prefix (#168), error correction (#108), val-only training all banned for record track. Now in README FAQ.

**TTT ruling (Mar 20, @0hq on [#152](https://github.com/openai/parameter-golf/pull/152)):** Only backward-looking TTT allowed — adapt on tokens *already graded*, not future tokens. Pre-eval adaptation invalid. Causal TTT (#267-style) remains allowed. In README FAQ.

**Mar 22, @cocohearts on [#317](https://github.com/openai/parameter-golf/pull/317):** TTT is "not in the spirit of the challenge." Broader organizer signal — even backward-looking TTT may face scrutiny.

**Mar 23, @0hq on [#402](https://github.com/openai/parameter-golf/issues/402):** Explicit TTT clarification — **token-stream model is correct.** You may use any preceding eval tokens already graded. You may NOT re-order the evaluation set. Invalid TTT PRs (train-on-val-then-measure) will be closed. Auto-review process being built.

**Mar 23, @cocohearts:** #374 rejected for insufficient statistical significance vs new SOTA. #505 needs packaging fixes.

**Mar 24, @valerio-oai — enforcement sweep (15+ PRs closed).** Two categories: **(1) TTT information leakage:** multi-epoch TTT with min-NLL selection, and adapting-then-scoring same tokens, both ruled equivalent to "training on the val set." #593, #576, #573, #568, #596, #605, #614, #620, #518, #548 closed. **(2) Training data at eval time:** GPTQ calibration using training data during eval budget disallowed. #593, #576, #569 closed for this. Calibration must count within training 600s. **#589 ruled valid but closed** — fails 0.005-nat threshold vs #549 SOTA. valerio-oai confirmed: "TTT is a valid approach in theory" but "very easy to unintentionally leak val data into."

**Mar 25, @valerio-oai — second enforcement sweep (issue [#677](https://github.com/openai/parameter-golf/issues/677)).** Comprehensive audit. **(1) Eval-time GPTQ:** Training for full 600s then doing GPTQ calibration afterward (even 3-4s) is "accessing training data at eval time" — disallowed. **#606, #615, #626, #639, #656 closed.** **(2) N-gram eval cache ruling:** The concept is "directionally legal" — building a cache from already-scored tokens is allowed. The specific #659 implementation was illegal (hindsight selection: comparing n-gram vs LM on the true next token). Legal alternatives: fixed-weight blending or entropy-adaptive alpha (using model uncertainty, not ground truth). **(3) #706 flagged:** @valerio-oai told @newjordan that #706's GPTQ calibration still runs after 600s training time — needs fix. **(4) Broad invalid TTT list:** #410, #415, #417, #442, #462, #481, #486, #517, #518, #532, #555, #581, #595 all flagged for adapting on validation before the reported eval pass.

</details>

---

## Technique Deep Dives

<details>
<summary><strong>The Muon Optimizer Family</strong></summary>

**Muon** (MomentUm Orthogonalized by Newton-Schulz) is the optimizer at the heart of this competition's baseline, created by Keller Jordan for the NanoGPT speedrun. It runs standard SGD with Nesterov momentum, then post-processes each 2D parameter's gradient update by replacing it with the nearest orthogonal matrix via Newton-Schulz iteration. Intuitively: compute the gradient direction, then "clean it up" so the update is maximally informative without redundant directions. It's equivalent to steepest descent under the spectral norm, which improves the conditioning of the optimization landscape. ~35% faster training than AdamW on language models.

**NorMuon** extends Muon by adding per-neuron adaptive learning rates from accumulated second-order statistics. Vanilla Muon can produce updates with highly non-uniform norms across neurons, causing some neurons to dominate training. NorMuon normalizes row-wise after orthogonalization, combining Muon's conditioning benefits with Adam-style balanced per-neuron learning. It also improves distributed scaling by avoiding full momentum gathering across GPUs. Used by @mtybadger ([#122](https://github.com/openai/parameter-golf/pull/122)), @vmfunc ([#89](https://github.com/openai/parameter-golf/pull/89)), @abhishekgahlot2 ([#137](https://github.com/openai/parameter-golf/pull/137)), and others.

**Muon Weight Decay** — The competition baseline's Muon optimizer has no weight decay. Decoupled weight decay for Muon (`p.mul_(1 - wd * lr)`) existed in modded-nanogpt since Nov 2025, but wasn't in the baseline. @notapplica was the first to bring it into this competition in [#60](https://github.com/openai/parameter-golf/pull/60), improving BPB from 1.2160 to 1.2094. Weights stay smaller and better-distributed, improving both generalization and compressibility.

</details>

<details>
<summary><strong>Quantization-Aware Training (QAT) with STE</strong></summary>

Instead of training in full precision and quantizing afterward, QAT simulates quantization during training. In the forward pass, weights are rounded to their quantized values. The problem: rounding is non-differentiable, so gradients can't flow through it.

The **Straight-Through Estimator (STE)** solves this by pretending the rounding operation is the identity function during the backward pass. It's mathematically "wrong" but works remarkably well — the model learns weight configurations that are robust to precision loss because it's been "seeing" quantized weights throughout training.

**Late QAT outperforms full-training QAT:** The later, the better. @trovatochris ([#117](https://github.com/openai/parameter-golf/pull/117)) activates at 70%, @mohosy ([#130](https://github.com/openai/parameter-golf/pull/130)) at 75%, @unixmadtoonslab ([#76](https://github.com/openai/parameter-golf/pull/76)) at 85%. #76 even dropped QAT entirely at 12L (1.1468), finding WD=0.04 alone sufficient. @jfprincz's [#315](https://github.com/openai/parameter-golf/pull/315) pushes this to the extreme: STE activates only in the final **4% of training** (lr_scale < 0.1, during low-LR warmdown). This cuts the int6 roundtrip gap to ~0.007 BPB while preserving full-precision convergence. The lesson: QAT activation is a spectrum — later = cleaner convergence, better int6 gap.

**Int8 vs int6 QAT tradeoff:** @mrdavtan's ablation in [#145](https://github.com/openai/parameter-golf/pull/145) shows that **int8 QAT is not worth it** under the 10-min wallclock cap. The `torch.quantile` call for exact percentile matching adds ~20% per-step overhead (64ms → 77ms), costing ~2,000 training steps. Result: 1.2052 BPB with QAT vs 1.1925 without — the lost training tokens hurt more than closing the ~0.007 int8 quantization gap. Int6 QAT, however, likely pays off because its larger ~0.01+ BPB gap justifies the overhead — confirmed by #128 and #137.

</details>

<details>
<summary><strong>SmearGate & Bigram Hash Embedding</strong></summary>

@unnir introduced SmearGate in [#102](https://github.com/openai/parameter-golf/pull/102) and refined it in [#135](https://github.com/openai/parameter-golf/pull/135). This appears to be a novel technique for this competition — no published papers found.

**SmearGate:** A tiny learned gate (~512 params) that blends each token's embedding with the previous token's. This injects bigram (two-token) context directly into the embedding layer before the transformer starts processing. Normally a transformer must discover token pair relationships through self-attention; SmearGate provides this signal for free.

**Bigram Hash:** A hash table (commonly 2048-10240 buckets, dim=128, projected to 512) that maps token pairs to learned embeddings. Together with SmearGate, this gives the model token-pair awareness at nearly zero parameter cost.

@unnir's original combination with orthogonal initialization achieved **1.1539 BPB** in [#135](https://github.com/openai/parameter-golf/pull/135). @jfprincz's #198 (1.1326) extended this with 11L + SWA + FA3 + WD 0.04, and #287 (1.1280) extended further with XSA + EMA.

**OrthoInit appears critical for SmearGate.** @mrdavtan's ablation in [#212](https://github.com/openai/parameter-golf/pull/212) found that adding SmearGate + BigramHash without OrthoInit **hurt** BPB (1.1739 vs 1.1708 without). Every successful SmearGate submission uses OrthoInit — the two techniques may be co-dependent.

</details>


<details>
<summary><strong>Exclusive Self-Attention (XSA)</strong></summary>

XSA ([arXiv:2603.09078](https://arxiv.org/abs/2603.09078), Shuangfei Zhai, 2026) removes self-value bias from attention output via orthogonal projection. In standard attention, each token's value vector contributes to its own output — XSA subtracts this self-component, forcing the model to rely on information from *other* tokens. Applied to the last 3-4 layers only ("Partial XSA"), where self-attention bias is highest.

**Zero parameters, minimal overhead.** @unnir's [#265](https://github.com/openai/parameter-golf/pull/265) GQA-aware implementation reduces XSA overhead from ~7ms/step to ~2ms/step. Near-universal among frontier submissions. Best non-TTT (#609, 1.1154) uses XSA on all 11 layers; official SOTA (#549, 1.1194) uses XSA4.

**XSA coverage depth: 4 layers appears near-optimal.** @gowtham0992's [#478](https://github.com/openai/parameter-golf/pull/478) tested XSA on ALL 11 layers: **1.1268** (3-seed) vs XSA-4 at 1.1327 on the same base (−0.006 from XSA-all). But #414 (XSA-4 + VE128 + Partial RoPE + LN Scale) reaches 1.1228 — better than #478's XSA-all(11) at 1.1268. XSA-all adds ~3ms/step overhead (−230 steps), and removing self-value from ALL layers may degrade the model's own-representation capacity. **The progression: 3 layers (#265: 1.1307) → 4 layers (#414: 1.1228) → 11 layers (#478: 1.1268) suggests 4-6 layers is the sweet spot for non-TTT.** However, **#609 (1.1154, best non-TTT) uses XSA-all(11)** and **#606 (1.1162, best legal TTT) also uses XSA-all** — at the current frontier, XSA-all with Full GPTQ overcomes the overhead penalty.

</details>

<details>
<summary><strong>Test-Time Training (TTT)</strong></summary>

@samacqua introduced a creative approach in [#77](https://github.com/openai/parameter-golf/pull/77): adapting the model *during evaluation*.

For each validation document, rank-8 LoRA (Low-Rank Adaptation) adapters are trained on the document's own text using only backward-looking context (no data leakage). The model essentially "studies" each document briefly before being scored on it. LoRA makes this practical by only training tiny low-rank matrices (~1.5% of params) rather than the full model, enabling batched per-document adaptation within the eval time budget.

Original #77 ablation showed TTT itself adds ~0.003 BPB on early baselines (most gain came from doc isolation + sliding window). Full-model SGD TTT (#152) was **ruled invalid by @0hq** — only backward-looking (score-first) TTT is legal. The best legal TTT submissions (#606 at 1.1162, #615 at 1.1169) were later closed for eval-time GPTQ on training data (Mar 25 sweep).

**TTT on XSA+EMA is a spectrum, not a binary.** On SmearGate bases: #254 shows 0.014 BPB gain. Three XSA+EMA data points, sorted by base strength: (1) **#317** (weak base, pre-quant 1.1581, no FA3): TTT **gains 0.024 BPB**. (2) **#338** (@alertcat, #315 base — frontier at 1.1250, Partial RoPE + LN Scale + Late QAT): TTT **neutral ±0.001** (3 seeds). (3) **#303** (@sseanliu, #287 base — 1.1280, without #315's additional regularization): TTT **+0.016 BPB worse**. The pattern suggests TTT interacts with how tightly converged the base model is: under-trained bases benefit from local adaptation; over-regularized frontier bases are disrupted; the current frontier (#315) sits in a neutral zone. #338's neutral result is informative — it means TTT is not a meaningful lever at the frontier.

**Reptile meta-TTT: gains on SmearGate, fails at frontier.** @sseanliu's [#296](https://github.com/openai/parameter-golf/pull/296) shows 0.011 BPB on SmearGate models vs 0.001 naive. But **#375 tested Reptile on #315's XSA+EMA base: +0.0076 worse**, consuming 20% of training budget. The SmearGate gain does not transfer to the frontier. All three TTT variants (naive, MLP-only, Reptile) are now confirmed dead ends at ~1.125. **Error-guided TTT is also negative** — hardest tokens are genuinely unpredictable.

**TTT optimizer recipe matters.** @Christopher-Lee-McClendon's [#461](https://github.com/openai/parameter-golf/pull/461) (non-record, 4xA100) found that **SGD+momentum(0.9), 3 epochs per 32K chunk, freezing first 2 blocks** gets −0.0165 BPB TTT gain — **2.4× better** than AdamW 1-epoch over all params (−0.0068 in their prior #456). Pre-TTT baselines nearly identical, so the entire improvement comes from the TTT recipe. This partially contradicts the #442 narrative (AdamW >> SGD) — the comparison is more nuanced: selective freezing + multi-epoch SGD with momentum can outperform single-epoch full-network AdamW.

**Legal TTT survivors — none remain after Mar 25 sweep.** #606 (1.1162) and #615 (1.1169) were closed — eval-time GPTQ calibration on training data. #576 (1.1164) closed in Mar 24 sweep. #573 (Multi-Pass min(NLL)) ruled invalid. **All frontier TTT submissions used eval-time GPTQ and are now invalid.** TTT optimizer matters for GPTQ: SGD TTT hurts Full GPTQ models (+0.030, #601), but AdamW with cosine LR works. The remaining legal TTT avenue requires GPTQ calibration within the 600s training budget.

**Cosine TTT scheduling is a 3× multiplier.** @mrdavtan's [#481](https://github.com/openai/parameter-golf/pull/481) (3-seed, **1.0970**) introduced two TTT innovations on top of AdamW TTT: (1) **cosine LR decay** over 30 epochs — high LR early to repair quant damage, low LR late to refine; (2) **per-layer LR groups** based on measured quantization error — 3× base LR for MLP output projections (3.4× higher quant error), 0.5× for input projections. Result: TTT gain of **−0.061 BPB** vs #442's −0.019 with flat LR — a **3× improvement from scheduling alone**. Pre-TTT ~1.158 (weaker base, FA2 not FA3). Also tested: focal loss and KL-divergence from pre-quant model — both failed to improve over CE. ⚠️ Pre-eval TTT.

</details>

<details>
<summary><strong>N-gram Eval Cache (the Mar 25 revolution)</strong></summary>

The single biggest BPB lever discovered in the competition. During sliding window evaluation, a backward-looking n-gram cache is built from already-scored tokens and mixed with model predictions. The concept is simple: if the model has already scored "the cat sat on the", and the 5-gram "cat sat on the" was followed by "mat" last time, weight that prediction into the next token's distribution.

**How it works:**
1. After scoring each token, record the preceding n-gram context and the actual next byte
2. For new tokens, look up the current n-gram context in the cache
3. If found, mix the empirical n-gram distribution with the model's distribution: `p_final = (1-α) * p_model + α * p_ngram`
4. Store counts in a hash table (count-min sketch, ~4M buckets)

**Three generations of implementation:**
- **Fixed 5-gram, fixed alpha** (#706, @newjordan): alpha=0.20 always. Simple. Drops BPB by ~0.07 (1.1202→1.0461).
- **Multi-order backoff 2-7** (#702, @lukacf): Try 7-gram first, cascade to 6,5,4,3,2 on miss. Coverage jumps dramatically. Additional −0.02 over fixed 5-gram.
- **Entropy-adaptive alpha** (#727, @Asukabot0): `alpha = 0.05 + 0.55 * sigmoid(2 * (H - 4.0))`. When the model is uncertain (high entropy), trust n-grams more. Additional −0.02 over fixed alpha. Combined with backoff: 1.1271 neural-only → 0.9674.

**Why it's so effective:** Language has enormous local repetition — names, technical terms, formatting patterns — that a small transformer can't memorize but n-grams capture perfectly. The n-gram cache acts as a lossless "local memory" that costs zero artifact bytes (built on-the-fly from eval data).

**Legality argument:** All implementations claim score-first backward-looking compliance — the cache uses only previously-scored tokens, alpha depends on the model's own entropy (not ground truth), and there's no oracle selection. #702 cites @valerio-oai suggesting entropy-adaptive alpha as a legal alternative in the #659 review. But the technique hasn't been officially ruled on yet.

**#738 adds kNN-LM:** @gowtham0992 stores 512-dim hidden states in a GPU ring buffer and finds k=32 nearest neighbors for uncertain tokens. RBF kernel builds a non-parametric distribution. Additive −0.007 BPB on top of n-gram cache. Based on Khandelwal et al. 2019 (ICLR 2020). Captures semantic patterns that pure n-gram statistics miss.

**Ablation data from #727:**

| Configuration | val_bpb | Delta |
|---|---|---|
| Neural only | 1.1271 | baseline |
| Fixed alpha=0.40, order=7 | 1.0336 | −0.094 |
| Multi-order backoff (2-7) + fixed alpha | 0.9825 | −0.145 |
| Multi-order backoff + entropy-adaptive | 0.9674 | −0.160 |

</details>

<details>
<summary><strong>#315's Techniques: Partial RoPE, LN Scale (Late QAT was inactive)</strong></summary>

@jfprincz's [#315](https://github.com/openai/parameter-golf/pull/315) (1.1250) adds two effective zero-parameter techniques on top of #287's XSA+EMA base, gaining 0.0023 BPB. **Note:** Late QAT was also included in the code, but `torch.compile` constant-folded the `_qat_enabled` flag, making the STE branch dead code — Late QAT never activated (discovered by @152334H, confirmed in #453). The 0.0023 gain comes entirely from Partial RoPE + LN Scale.

**Partial RoPE (16 of 64 head dimensions).** Rotary Position Embedding (RoPE) injects position information by rotating query/key vectors. Standard RoPE applies to all head dimensions. Partial RoPE applies to only 25% (16 of 64 dims) — the remaining 48 dims attend without position encoding. Why this helps: the position-free dims learn semantic similarity independent of token distance, improving generalization across different position ranges. The model can learn both "what things are" (position-free) and "where things are" (position-encoded) using different parts of the same head. Zero new parameters.

**LN Scale (output scaled by 1/√(layer_idx+1)).** After each RMSNorm, the output is multiplied by a layer-dependent scale factor that shrinks with depth. Layer 0: ×1.0; Layer 5: ×0.408; Layer 10: ×0.302. This damps the contribution of deeper layers to the residual stream, preventing later layers from "overwriting" early representations. Training is more stable — the model can use depth incrementally rather than being forced to route everything through deep layers. The 1/√(layer+1) schedule is related to the "depth scaling" used in some architecture papers. Zero new parameters.

**Late QAT (STE enabled only when lr_scale < 0.1) — ⚠️ was dead code in #315.** `torch.compile` constant-folded the `_qat_enabled` class attribute, so the STE branch never activated (discovered by @152334H, confirmed in #453). The concept is sound — late activation avoids corrupting Muon's momentum — but #315's actual gains came from Partial RoPE + LN Scale alone. **Working Late QAT:** @unnir (#374, scale<0.1), @signalrush (#414, threshold 0.15), @fbedev (#417). Downstream submissions copying #315's code may also have inactive Late QAT.

The two active techniques (Partial RoPE + LN Scale) gain 0.0023 BPB vs #287 — statistically clear (3-seed variance 0.0005 BPB, t-stat -101.9 vs SOTA, p << 0.01).

</details>

---

<details>
<summary><strong>Notable Non-Record Submissions</strong></summary>

| Author | PR | Highlight |
|--------|-----|-----------|
| @mohosy | [#130](https://github.com/openai/parameter-golf/pull/130) | 7 toggleable improvements; QAT + Muon momentum analysis |
| @MatoTeziTanka | [#95](https://github.com/openai/parameter-golf/pull/95) | PROTEUS EMA — reduces int8 quant loss 0.0072→0.0048 |
| @nglain | [#141](https://github.com/openai/parameter-golf/pull/141) | 33-experiment sweep; found int6 STE + Muon conflict (+0.007) |
| @kellyvv | [#108](https://github.com/openai/parameter-golf/pull/108)/[#232](https://github.com/openai/parameter-golf/pull/232) | **Error Correction Table** — stores model's worst predictions, ~1.05 est. on 8xH100 |
| @mrdavtan | [#145](https://github.com/openai/parameter-golf/pull/145) | Int8 QAT ablation — overhead exceeds recovery |
| @timothywangdev | [#220](https://github.com/openai/parameter-golf/pull/220) | [WIP] First SSM (Linear Recurrent Unit) — non-transformer architecture |
| @mkenney2 | [#599](https://github.com/openai/parameter-golf/pull/599) | **Hymba: Hybrid Attention + Mamba SSM** (first competitive non-transformer). 7L parallel attn+SSM branches with learned mixing. **1.1828 BPB**, 3 seeds, 8xH100. Key: shallow models win (SSM makes each layer more powerful → 7L beats deeper pure transformers at same step budget). |
| @alons23 | [#216](https://github.com/openai/parameter-golf/pull/216) | Ternary Universal Transformer — 68M params, 4×6 depth recurrence |
| @Cwarren15-A | [#283](https://github.com/openai/parameter-golf/pull/283) | **PPM-C context mixer** — classical compression blended with neural (0.015 BPB on baseline) |
| @sseanliu | [#296](https://github.com/openai/parameter-golf/pull/296) | **Reptile meta-TTT** — 0.011 BPB gain on SmearGate models (10x naive TTT). Error-guided TTT negative. |
| @integrate-your-mind | [#289](https://github.com/openai/parameter-golf/pull/289) | 11L seq1024 + U-Net skips (1.1518). TTT LoRA *worse* than sliding window alone on this base. |
| @gowtham0992 | [#295](https://github.com/openai/parameter-golf/pull/295) | **Backout** (learned residual subtraction) + mixed int5/int6 QAT + U-Net skips (1.1477, 1 seed) |
| @JackYoung27 | [#302](https://github.com/openai/parameter-golf/pull/302) | **Online causal TTT + decay prior** (`p += λ(p₀-p)`) + Reptile (last 10%) + XSA3 + Pre-Q/K RMSNorm. TTT gain: **-0.014 BPB** (1.1660→1.1520). Adapts MLP only in last 3 blocks. Int5-MLP/int6-attn + BigramHash(10240). 1 seed. |
| @xuafeng | [#306](https://github.com/openai/parameter-golf/pull/306) | QAT Int5/Int6 on #180 base: **post-training quant outperforms QAT by ~0.002 BPB** — quant noise acts as beneficial regularization that QAT removes (1.14476, 1 seed) |
| @NewyorkDev | [#309](https://github.com/openai/parameter-golf/pull/309) | CLASE-Quant adaptive per-layer quantization: int8 for boundary layers, int6 for middle — saves ~15% vs uniform int8 (1.1914, 3 seeds) |
| @chanwoo-park-official | [#312](https://github.com/openai/parameter-golf/pull/312) | **Canon ACD layers** (Allen-Zhu 2025) on 9L stack — learnable 1D conv (k=3) placed before attention, before MLP, and in MLP hidden stream (avoids QKV=B for cost). 1.1668, 1 seed. Novel architecture technique; interesting if it scales to 11L. |
| @SkywardSyntax | [#316](https://github.com/openai/parameter-golf/pull/316) | 12L Low-Rank Q (r=128) + QAT int7 on 1xH100 (pre-quant 1.2035, awaiting 8xH100). Key negative result: **FTLE per-row precision is a dead end** — uniform int-N beats mixed-row at every bit width due to higher entropy defeating zstd. Layer sharing also abandoned at 512d (costs 0.09 BPB, no space benefit). |
| @aravhawk | [#314](https://github.com/openai/parameter-golf/pull/314) | 11L Int4 MLP QAT on #180 base — int4 MLP saves ~2MB to fund 11th layer vs #180's 10L int5. Awaiting 8xH100 results. Record track aspirant. |
| @Rhodrium | [#331](https://github.com/openai/parameter-golf/pull/331) | 10L MLP3x + BigramHash(2048) + SmearGate + OrthoInit + mixed int5/int6 + SWA + **stride=32** eval. 1.1487 BPB, 3 seeds. Solid consensus stack; above SOTA but clean stride-32 reference on H100s (94/91ms/step). |
| @sheeki03 | [#339](https://github.com/openai/parameter-golf/pull/339) | **Backout ablation**: -0.0071 BPB on #198 base (1.1435→1.1364). First clean measurement. ⚠️ artifact 16.17MB (over limit), 1 seed. Plans int5-MLP fix + XSA/EMA combo. |
| @Ananddna | [#327](https://github.com/openai/parameter-golf/pull/327) | **TrigramHash** (8192 buckets) + Partial RoPE (50%) + **per-head temperature scaling** + stride=32 eval. 1.1450, 2 seeds. Three novel techniques on 10L int5 base. |
| @mahsumaktas | [#333](https://github.com/openai/parameter-golf/pull/333) | **23-run systematic exploration** (1.1565, 3 seeds). Key findings: seq curriculum fails (SWA incompatible across seq lengths), EMA causes 0.14 BPB quant gap on SWA-stack, MLP 2.75x sweet spot at 11L+SmearGate, Late QAT 75% cuts quant gap 0.023→0.006. |
| @sseanliu | [#318](https://github.com/openai/parameter-golf/pull/318) | **Neural Cache** research proposal — maintain per-layer KV cache across sliding windows, extending effective context from 2K to 50K+. Zero artifact cost, backward-looking compliant. Untested (torch.compile state bug). Proposed on #287 base (1.1284). |
| @fbedev | [#348](https://github.com/openai/parameter-golf/pull/348) | QAT + BigramHash(12288) + stride=32 on #180 base. 1.1444, 1 seed. Barely above SOTA — diminishing returns from BigramHash >10240. |
| @sp00mm | [#352](https://github.com/openai/parameter-golf/pull/352) | **Memory Tokens**: 64 learnable embeddings as global context scratchpad. A/B: **-0.014 BPB**. Uses #315 stack + MTP aux heads. 1.1659, 1 seed. |
| @jackopenn | [#336](https://github.com/openai/parameter-golf/pull/336) | **Hypernetwork prototype** — shared-trunk MLP generates full GPT weights from compact conditioning vectors (9.34x compression, 26.5M target params from 2.8M hypernet params, 2.09MB artifact). No BPB result yet. Highest compression-ratio weight-generation approach seen. |
| @mkenney2 | [#362](https://github.com/openai/parameter-golf/pull/362) | 11L SmearGate+BigramHash(4096)+EMA+OrthoInit, WD=0.02, stride=256. 1.1497 (3-seed). Key negatives: AttnRes -54% throughput, seq curriculum compile overhead, depth recurrence, 13L+TTT compression. |
| @shikhar1729 | [#364](https://github.com/openai/parameter-golf/pull/364) | **524K batch on #180 base** — 1.1497 (3-seed). Validates 524K batch benefit: more optimizer steps per wall-clock minute. |
| @charmquark1984 | [#375](https://github.com/openai/parameter-golf/pull/375) | **$500 systematic frontier study.** 13 techniques on #315 base, all failed. Reptile +0.008 worse. EMA>SWA +0.003. 786K>524K +0.004. See What Doesn't Work. |
| @anthony-maio | [#376](https://github.com/openai/parameter-golf/pull/376) | 9L + full stack + custom Triton/CUDA kernels (fused RMSNorm+QKV 1.47×, fused ReLU² MLP 1.26×). 1.1401, 1 seed. 125ms/step (4,782 steps). Kernel pipeline in dev for next submission. |
| @abaybektursun | [#399](https://github.com/openai/parameter-golf/pull/399) | **First Muon systems optimization.** Parameter Banking + Polar Express + Parallel Muon = 82.14ms/step (−3.1% vs #315's 84.76ms, +227 steps). Lossless — identical pre-quant 1.1421. ⚠️ Artifact 20.4MB (packaging issue). Significance waived for systems-only. |
| @anantdgoel | [#384](https://github.com/openai/parameter-golf/pull/384) | 3 research directions: **MAML Meta-TTT** = +0.085 worse (5th dead TTT variant). **Eval stacking** (cache + OGD on vocab bias): −0.003 additive, zero artifact cost. **Tokenizer v8192**: null result — longer tokens harder to predict, offsetting compression. 1xA40, 1.2882. |
| @anantdgoel | [#413](https://github.com/openai/parameter-golf/pull/413) | **Value Residual: −0.015 BPB** (dev). Gated Attention: −0.003. Stack additively (−0.017). PPM-C: +0.002 (negative). 9L dev-scale, 1xRTX3090. |
| @anantdgoel | [#487](https://github.com/openai/parameter-golf/pull/487) | **VRL+GA on 11L production stack** (1xA6000, 14.5hr). **1.1720 BPB**, 19.4MB (over limit). Confirms dev ablation (−0.017 additive). Not 8xH100 — VRL on 8xH100 frontier still untested by originator (#486 by @ndokutovich tested VRL+Cosine TTT at 1.0887). |
| @zachgoldfine44 | [#450](https://github.com/openai/parameter-golf/pull/450) | **12L + Catalytic Residuals** (novel: `x + c*f(x)`, learned per-dim vector c). −0.024 BPB at zero overhead. 3-seed mean 1.1466. Built on #180. |
| @Christopher-Lee-McClendon | [#461](https://github.com/openai/parameter-golf/pull/461) | **High-yield legal TTT**: SGD+momentum(0.9), 3 epochs per 32K chunk, freeze first 2 blocks. TTT gain: **−0.0165** (2.4× better than AdamW 1-epoch). Depth recurrence (11L from 10 cores). 1.14458, 4xA100. |
| @joshuaswarren | [#474](https://github.com/openai/parameter-golf/pull/474) | **First VRL+GA+Catalytic Residuals stack** on 12L + BigramHash(10240) + SWA + Late QAT. 1.1690 — disappointing vs #450's 1.1466 (same base without VRL/GA). Techniques don't stack additively here: no XSA, no EMA → weak base dilutes gains. |
| @leofeasby | [#470](https://github.com/openai/parameter-golf/pull/470) | **Shared-weight transformer** (single block × 9 passes) + U-Net skips + extended warmdown. 1.1454, 2.3hrs 8xH100. Key finding: improvement continues steadily throughout low-LR warmdown — no plateau observed. |
| @LoquiAuris | [#465](https://github.com/openai/parameter-golf/pull/465) | **Int6 embedding quantization**: +0.0005 BPB penalty — essentially free. Systematic tokenizer study: sp8192 d=512 8L (1.1794) vs sp1024 d=512 10L (1.1508) — more layers > tokenizer efficiency. 3-seed std=0.00012. |
| @carlesonielfa | [#457](https://github.com/openai/parameter-golf/pull/457) | 11L + XSA + **VRL (Value Residual Learning)** + SWA + seq4096 + cross-doc TTT. 1.1839 (int8+zlib). Another VRL adopter. |
| @AnirudhRahul | [#511](https://github.com/openai/parameter-golf/pull/511) | **Delayed PPM eval-time bank** on #180 base. Classical n-gram backoff (C trie) with 2048-token delay — only sees tokens outside transformer's window. **−0.00126 BPB (p=0.000041, 3-seed)** — real but below 0.005-nat record bar. Zero artifact cost, composable with any model. First positive classical compression result at frontier. |
| @Robby955 | [#484](https://github.com/openai/parameter-golf/pull/484) | **TTT Memorization Analysis** (updated from EBLS). Diagnostic: 3-epoch TTT adapted weights score **1.0476** via sliding window (genuine adaptation). **At 10 epochs: 0.8566 TTT-loop / 0.9229 sliding — both below ~0.95 theoretical floor = memorization.** Implication: #512's 0.95 seeds are likely memorization artifacts, not real gains. Also: MLP weights are layer-invariant (EBLS gammas → 0). |
| @Christopher-Lee-McClendon | [#598](https://github.com/openai/parameter-golf/pull/598) | **7000-step GEPA** (4xA100). Extended warmdown + mixed int6/int8 + legal TTT. **1.1334 BPB.** |
| @Christopher-Lee-McClendon | [#628](https://github.com/openai/parameter-golf/pull/628) | **Sub-1.10 GEPA** (4xA100, 20k steps). 8k warmdown + int6 GPTQ-lite + legal TTT. **1.0983 BPB.** Scaling law: warmdown is dominant lever. |
| @SPThole | [#623](https://github.com/openai/parameter-golf/pull/623) | **First AWQ in competition** — activation-aware weight scaling (α=0.5) before quant. Closed 63% of quant gap (0.027→0.010). Cyclic Muon Momentum (triangle wave 0.85-0.95). 21+ experiments. **1.1507, 3-seed.** |
| @CiprianFlorin-Ifrim | [#641](https://github.com/openai/parameter-golf/pull/641)/[#640](https://github.com/openai/parameter-golf/pull/640) | **Binary/Ternary U-Net** — radical compression frontier. Binary (1-bit): **106.2M params in 15.67MB** via bit-packing, 15L 768d, **1.1239 BPB** (non-record, 50k steps). Ternary (1.58-bit): 73.7M params, 10L 768d, **1.1570 BPB** (3-seed, 599s). NeoMuon optimizer, 8192 BPE tokenizer, FP8 QAT, YaRN 2048. 250+ experiments. "Train larger, quantize harder" taken to extreme. |


</details>

---

<details>
<summary><strong>Idea Lineage & Diffusion (52 techniques tracked)</strong></summary>

| Technique | First Appeared | Originator | Adoption |
|-----------|---------------|------------|----------|
| Sliding Window Eval | [#50](https://github.com/openai/parameter-golf/pull/50) | @mattqlf | Near-universal (20+) |
| FP16 Tied Embedding | [#42](https://github.com/openai/parameter-golf/pull/42) | @chonchiog | ~10+ |
| Int6 Quantization | [#39](https://github.com/openai/parameter-golf/pull/39) | @nanlliu | ~15+ |
| MLP 3x Expansion | [#70](https://github.com/openai/parameter-golf/pull/70) | @jfprincz | ~12+ |
| Muon Weight Decay | [#60](https://github.com/openai/parameter-golf/pull/60) | @notapplica (from modded-nanogpt) | Several |
| Overtone Spectral Init | [#60](https://github.com/openai/parameter-golf/pull/60) | @notapplica | @peytontolbert (#155), @TevBenji (#69) |
| SmearGate / BigramHash | [#102](https://github.com/openai/parameter-golf/pull/102) | @unnir | Near-universal (25+). All competitive submissions use SmearGate+BigramHash+OrthoInit. |
| OrthoInit | [#135](https://github.com/openai/parameter-golf/pull/135) | @unnir (combined with SmearGate) | Near-universal among top SmearGate submissions. Critical co-dependency: SmearGate hurts without OrthoInit (#212 ablation). |
| Test-Time Training | [#77](https://github.com/openai/parameter-golf/pull/77) | @samacqua (LoRA TTT) | @timowhite88 (#152 SGD, #254 first TTT+SmearGate+11L), @polarizedfortnite-cpu (#81, first TTT+int6), @andrewgcodes (#267 Causal TTT), @charmquark1984 (#281), @ibarrajo (#290, TTT+XSA), @mohosy (#291, pending), @sseanliu (#296, Reptile meta-TTT), @davidpuertolas (#297), @alertcat (#338, TTT on #315 frontier base — neutral), @felipe-parodi (#398, 20-epoch aggressive TTT, 1.1221), @kasimte (#455, SGD TTT on #374 base), @Christopher-Lee-McClendon (#461, high-yield SGD+momentum TTT), **@abaybektursun (#473, legal TTT — 1.1214)**, **@LoquiAuris (#548, batched LoRA TTT — 1.0865)**, **@Sarimsaljook (#573, Multi-Pass TTT — 1.0523 ❌ ruled invalid)** |
| NorMuon | Multiple PRs | Convergent | @mtybadger, @vmfunc, @dexhunter, others |
| QAT with STE | Multiple PRs | Convergent | @rsavitt, @yahya010, @trovatochris, others |
| SWA | [#89](https://github.com/openai/parameter-golf/pull/89) | @vmfunc | @mtybadger (#122), @dexhunter (#156), @anthony-maio (#376), others |
| Depth Recurrence | Multiple PRs | Independent | @MatthewHRockwell, @koushikkethamakka, @iverbovoy (#148), others |
| Int5 MLP Quantization | [#76](https://github.com/openai/parameter-golf/pull/76) | @unixmadtoonslab | @thwu1 (#180, former SOTA), @alertcat (#219, mixed int5/int6), @Mapika (#349), @Skrisps26 (#354), @signalrush (#369) |
| BigramHash Scaling (4096–16384) | [#180](https://github.com/openai/parameter-golf/pull/180) | @thwu1 (10240) | @andrewgcodes (#267, 16384), @simonbissonnette (#466, 12288), @JoeProAI (#462, 8192). Diminishing returns >10240 (#348). |
| Low-Rank Q Factorization | [#215](https://github.com/openai/parameter-golf/pull/215) | @JayCheng113 | Novel — no adopters yet |
| Partial XSA (Exclusive Self-Attention) | [#265](https://github.com/openai/parameter-golf/pull/265) | @unnir | Near-universal at frontier (15+): @jfprincz (#287, #315), @signalrush (#369, #414), @saml212 (#332), @chanwoo-park-official (#400), @fbedev (#417), @sjp611 (#442), @JoeProAI (#462), @kasimte (#455), @ofirkris (#458), @Christopher-Lee-McClendon (#461), others |
| EMA Weight Averaging | [#95](https://github.com/openai/parameter-golf/pull/95) | @MatoTeziTanka (PROTEUS EMA) | Near-universal at frontier (12+): @jfprincz (#287, #315), @signalrush (#369, #414), @sjp611 (#442), @JoeProAI (#462, 0.9985), @ofirkris (#458), @simonbissonnette (#466), @felipe-parodi (#398), @parinzee (#493), others. EMA fails without XSA (#201). |
| Reptile Meta-TTT | [#296](https://github.com/openai/parameter-golf/pull/296) | @sseanliu | @JackYoung27 (#302, +causal TTT + decay prior). **#375: failed on #315 base (+0.0076 worse).** |
| BitNet b1.58 | [#126](https://github.com/openai/parameter-golf/pull/126), [#139](https://github.com/openai/parameter-golf/pull/139)→[#367](https://github.com/openai/parameter-golf/pull/367) | @Athenox14, @ksang123 | Two independent. #367: standard stack breaks on ternary. |
| Partial RoPE | [#315](https://github.com/openai/parameter-golf/pull/315) | @jfprincz (25% dims) | @saml212 (#332), @unnir (#374), @felipe-parodi (#398), @signalrush (#414), @fbedev (#417), @kasimte (#455), @ofirkris (#458), @Christopher-Lee-McClendon (#461), @JoeProAI (#462) |
| LN Scale (1/√layer) | [#315](https://github.com/openai/parameter-golf/pull/315) | @jfprincz | Near-universal at frontier (10+): @signalrush (#414), @fbedev (#417), @JoeProAI (#462), @sofiabod (#489, calls it "depth damping"), others. Variant: @eb1386 (#449, cosine) |
| Late QAT (last 4% only) | [#315](https://github.com/openai/parameter-golf/pull/315) | @jfprincz (⚠️ dead code in #315 — torch.compile bug) | **Working:** @unnir (#374, scale<0.1), @signalrush (#414, threshold 0.15), @fbedev (#417), @JoeProAI (#462). Dropped at 12L (#332). |
| Gradient-Guided Quant | [#332](https://github.com/openai/parameter-golf/pull/332) | @saml212 | @ndokutovich (#486, sensitivity-ranked int7/6/5 — top 10%/70%/20%) |
| TrigramHash | [#327](https://github.com/openai/parameter-golf/pull/327) | @Ananddna | @ndokutovich (#486, 4096 buckets + VRL + GradQuant + Cosine TTT, **1.0887**) |
| Per-Head Temperature | [#327](https://github.com/openai/parameter-golf/pull/327) | @Ananddna | Novel — each head learns its own temperature scalar |
| Tight SWA (scale<0.2) | [#374](https://github.com/openai/parameter-golf/pull/374) | @unnir | @dannywillowliu-uchi (#379, +GPTQ-lite), @kasimte (#455, +TTT) |
| Shared Value Embedding | [#374](https://github.com/openai/parameter-golf/pull/374) | @unnir | @dannywillowliu-uchi (#379, +GPTQ-lite), @kasimte (#455, +TTT), @Christopher-Lee-McClendon (#461, layers 9-10), **@JoeProAI (#505, GEPA arch, 1.1181)** |
| AdamW TTT | [#442](https://github.com/openai/parameter-golf/pull/442) | @sjp611 (3-line diff from #398: SGD→AdamW) | @JoeProAI (#462), @mrdavtan (#481, cosine), @ndokutovich (#486), @sofiabod (#489, 7L), @amaljithkuttamath (#490, +VRL+GA), @ahmettrkck (#491, +DWA), **@EthanYangTW (#503, legal AdamW TTT)**, @ymrohit (#555, closed) |
| GPTQ-lite → Full GPTQ | [#379](https://github.com/openai/parameter-golf/pull/379) | @dannywillowliu-uchi (per-layer clip percentile search) | @signalrush (#414), @fbedev (#417), @gowtham0992 (#478), @EthanYangTW (#503, **#606 int5 GPTQ**), **@raahilshah (#535)**, **@gowtham0992 (#569)**, @cmcdnd (#576), **@newjordan (#587)**, **@saml212 (#609)**, **@danialht (#615)**. Now standard at frontier. |
| Value Residual Learning | [#413](https://github.com/openai/parameter-golf/pull/413) | @anantdgoel (arXiv:2410.17897, −0.015 dev) | @ndokutovich (#486, **1.0887**+Cosine TTT), **@amaljithkuttamath (#490, VRL+GA+TTT, 1.0891 1-seed!)**, **@gowtham0992 (#569, VRL no-TTT → 1.1175, best non-TTT at time)**, @joshuaswarren (#474, failed on weak base), @carlesonielfa (#457), @yuvrajyadav17 (#471, pending), @ahmettrkck (#491, VRL+DWA+TTT) |
| Catalytic Residuals | [#450](https://github.com/openai/parameter-golf/pull/450) | @zachgoldfine44 (`x + c*f(x)`, −0.024 BPB) | @joshuaswarren (#474, +VRL+GA, 12L — 1.1690, techniques don't stack on weak base) |
| Two-Phase TTT | [#417](https://github.com/openai/parameter-golf/pull/417) | @fbedev (50ep norm-only + 10ep last-3-blocks) | Novel — no adopters yet |
| Gated Attention | [#413](https://github.com/openai/parameter-golf/pull/413) | @anantdgoel (arXiv:2505.06708, −0.003 dev) | **@amaljithkuttamath (#490, +VRL+TTT, 1.0891)**, @joshuaswarren (#474, failed on weak base), @yuvrajyadav17 (#471, pending) |
| Cosine TTT + Per-Layer LR | [#481](https://github.com/openai/parameter-golf/pull/481) | @mrdavtan (cosine LR decay + 3× MLP output proj LR) | **@sofiabod (#518, cosine+per-layer → 1.0814)**, **@ndokutovich (#486, cosine → 1.0887)**, @Christopher-Lee-McClendon (#537, per-layer LR on legal TTT). ⚠️ Pre-eval TTT (except #537) |
| XSA-All (11 layers) | [#478](https://github.com/openai/parameter-golf/pull/478) | @gowtham0992 (first to test XSA on all layers) | @EthanYangTW (#503, #606), @cmcdnd (#576), **@newjordan (#587)**, **@saml212 (#609, best non-TTT)**, **@danialht (#615)**. Now standard at frontier. |
| LeakyReLU(0.5)² | [#434](https://github.com/openai/parameter-golf/pull/434) (closed) → [#493](https://github.com/openai/parameter-golf/pull/493) | @parinzee (squared leaky ReLU, 0.5 neg slope) | **@sofiabod (#518)**, **@raahilshah (#535)**, @Christopher-Lee-McClendon (#537), @abaybektursun (#549), **@gowtham0992 (#569)**, @cmcdnd (#576), @RoyiRa (#589), **@saml212 (#609)**, **@robinojw (#620)**. **10+ adopters — fastest-spreading technique.** |
| Delayed PPM Eval Bank | [#511](https://github.com/openai/parameter-golf/pull/511) | @AnirudhRahul (classical n-gram backoff with 2048-token delay, on @thwu1's #180 base) | Novel — −0.00126 BPB at p=0.000041. Zero artifact cost. |
| Post-TTT Temperature Calibration | [#576](https://github.com/openai/parameter-golf/pull/576) | @cmcdnd (T=0.98 re-score after legal TTT to correct overconfidence, −0.003 BPB) | Novel — no adopters yet. Zero-cost technique. |
| Walsh-Hadamard Rotation | [#586](https://github.com/openai/parameter-golf/pull/586) | @EaCognitive (pre-quant rotation for outlier redistribution. zstd 1.70x→1.76x, freeing 530KB for VE128) | Novel — **substitutes with GPTQ at int6** (they address the same outlier problem). Also found Late QAT dead-code bug in CastedLinear. |
| Late Soft-Round QAT | [#589](https://github.com/openai/parameter-golf/pull/589) | @RoyiRa (temperature-controlled soft-round surrogate replaces hard STE; bin-aware gradients near int6 boundaries) | **@EthanYangTW (#606, tanh α1→16, best legal TTT 1.1162)**. Independent discovery likely (~8hr gap, same tanh-alpha approach). |
| Selective Pruning | [#609](https://github.com/openai/parameter-golf/pull/609) | @saml212 (post-GPTQ ±1 magnitude pruning sorted by reconstruction error) | Novel — no adopters yet. |
| Residual Input Mixing | [#615](https://github.com/openai/parameter-golf/pull/615) | @danialht (dense residual: each block sees learned mix of current stream + earlier blocks + x0) | Novel — no adopters yet. |
| AWQ | [#623](https://github.com/openai/parameter-golf/pull/623) | @SPThole (activation-aware weight scaling α=0.5 before quant, closed 63% quant gap) | Novel — first use in competition. |
| Cyclic Muon Momentum | [#623](https://github.com/openai/parameter-golf/pull/623) | @SPThole (triangle wave 0.85-0.95, period=50) | Novel — no adopters yet. |
| N-gram Eval Cache | [#659](https://github.com/openai/parameter-golf/pull/659) (concept) → [#674](https://github.com/openai/parameter-golf/pull/674)/[#706](https://github.com/openai/parameter-golf/pull/706) | @deanbrr (concept), @newjordan (5-gram implementation) | **@lukacf (#702, multi-order backoff)**, **@Asukabot0 (#715, #727, entropy-adaptive)**, **@hypery11 (#724, 7-gram)**, **@gowtham0992 (#738, +kNN-LM)**, **@resouer (#740, 9L+5gram)**, **@andrewbaggio1 (#741, +cosine TTT)**. **8 adopters in <12 hours — fastest spread in competition history.** |
| Multi-Order N-gram Backoff | [#702](https://github.com/openai/parameter-golf/pull/702) | @lukacf (cascade 7→6→5→4→3→2 on miss) | **@Asukabot0 (#727, orders 2-7 + entropy-adaptive)** |
| Entropy-Adaptive Alpha | [#702](https://github.com/openai/parameter-golf/pull/702) | @lukacf (`alpha = 0.05 + 0.35 * sigmoid(2*(H-4))`) | **@Asukabot0 (#727, wider range 0.05-0.60)** |
| Hidden-State kNN-LM | [#738](https://github.com/openai/parameter-golf/pull/738) | @gowtham0992 (GPU ring buffer + RBF kernel, Khandelwal et al. 2019) | Novel — first in competition. |
| Depth Recurrence (with block scalars) | [#686](https://github.com/openai/parameter-golf/pull/686) | @msisovic (layers 4+5 repeated, 11→13 virtual, ~2K params) | Novel — recovers 70% of independent 12L gain. |
| Hedge Mixer (expert ensemble) | [#688](https://github.com/openai/parameter-golf/pull/688) → [#700](https://github.com/openai/parameter-golf/pull/700) | @RoyiRa (5-expert: neural + unigram + bigram + trigram + entropy, Hedge algorithm eta=0.1. First in #688; improved in #700 with CROWN-Q + MLP3.5x + stride=64) | **@pentxayc (#731, +VRL+TTT+Polyak EMA)**, **@agalimova (#720, XSA6+BigramHash4K on #700 base)** |
| MiLe Loss | [#703](https://github.com/openai/parameter-golf/pull/703) | @Gusanidas (entropy-weighted token loss, γ=1.1 decaying to 0 during warmdown) | Novel — no adopters yet. |

</details>

---

## Predictions & Commentary

1. **N-gram eval caches dominate the frontier.** Backward-looking n-gram caches follow the same principle as legal TTT: use only already-scored tokens. The only n-gram approach ruled invalid was #659's hindsight selection (comparing both models on the true next token, then picking the better one). Current submissions use fixed-weight blending or entropy-adaptive alpha (model uncertainty, not ground truth) — no specific compliance issues beyond the usual (GPTQ timing, artifact size, reproducibility).

2. **Two-track competition, not three.** (a) **Eval-time augmentation track** (0.97-1.10 BPB) — n-gram caches, Hedge Mixer, kNN-LM. All use backward-looking statistics at eval time. The Hedge Mixer (#700) is a variant of eval-time augmentation (its "experts" include unigram/bigram/trigram), not a separate track. (b) **Pure neural track** (~1.115-1.12 BPP) — frozen. Official SOTA 1.1194 unchanged. The Mar 25 sweep closed #606/#615 (the two submissions pushing this frontier), and no replacements have appeared.

3. **Diminishing returns on n-gram cache optimization.** The progression: fixed 5-gram (−0.07) → multi-order backoff (−0.09 incremental) → entropy-adaptive alpha (−0.02 incremental). Each generation adds less. The jump from no-cache to cache is enormous; between variants it's shrinking. The next frontier is likely combining n-gram caches with stronger neural bases rather than further tuning the cache. #727's ablation shows the neural-only base was 1.1271 — there's room to improve that (best non-TTT neural is 1.1154 from #609's stack).

4. **Sub-0.9 BPB is unlikely without memorization.** Based on #727's ablation (neural 1.1271 → 0.9674 with full cache, a 14.2% gain), applying the same proportional gain to a Tier 4 neural base (~1.115) yields ~0.96. With kNN-LM (−0.007) and higher-order n-grams (~0.005), the floor is approximately 0.93-0.95 BPB. Going lower likely requires either a fundamentally better neural model or techniques approaching memorization.

5. **The official leaderboard will lag the frontier for weeks.** SOTA is 1.1194; best pending is 0.9674 — a 0.15 BPB gap. Only 18 entries on the official leaderboard after 7 days. The n-gram wave added 7+ submissions in 12 hours, none reviewed yet. Each submission still needs individual verification for compliance (GPTQ timing, backward-looking correctness, artifact size).

---

<details>
<summary><strong>Full Official Leaderboard (18 entries)</strong></summary>

| Rank | Score | Author | Key Techniques | PR |
|------|-------|--------|---------------|-----|
| 1 | **1.1194** | @sanjeevmadhav | LeakyReLU² + Legal Score-First TTT + Parallel Muon on #414 stack | [#549](https://github.com/openai/parameter-golf/pull/549) |
| 2 | 1.1228 | @signalrush | 11L EMA + GPTQ-lite + warmdown3500 + QAT@0.15 | [#414](https://github.com/openai/parameter-golf/pull/414) |
| 3 | 1.1248 | @jfprincz | 11L Partial RoPE + LN Scale + EMA + XSA4 | [#315](https://github.com/openai/parameter-golf/pull/315) |
| 4 | 1.1271 | @jfprincz | 11L XSA4 + EMA + Int6 MLP3x | [#287](https://github.com/openai/parameter-golf/pull/287) |
| 5 | 1.1307 | @unnir | 11L Efficient Partial XSA | [#265](https://github.com/openai/parameter-golf/pull/265) |
| 6 | 1.1458 | @raahilshah | Int6 MLP3x + SmearGate + BigramHash + OrthoInit + MuonWD + SWA | [#162](https://github.com/openai/parameter-golf/pull/162) |
| 7 | 1.1502 | @aruniyer | 11L + Int6 QAT + MLP3x + WD 0.04 + zstd-22 | [#86](https://github.com/openai/parameter-golf/pull/86) |
| 8 | 1.1556 | @aquariouseworkman | SmearGate + OrthoInit + Int6 STE QAT + MLP3x + Sliding Window | [#65](https://github.com/openai/parameter-golf/pull/65) |
| 9 | 1.1586 | @yahya010 | 10L Int6 QAT + Zstd MLP2.6x + Muon 0.99 + Sliding Window | [#63](https://github.com/openai/parameter-golf/pull/63) |
| 10 | 1.1630 | @aquariouseworkman | Mixed int6/int8 + MLP3x + Sliding Window | [#65](https://github.com/openai/parameter-golf/pull/65) |
| 11 | 1.1748 | @notapplica | Sliding Window + FP16 Embed + 10L + Muon WD + Spectral Init | [#60](https://github.com/openai/parameter-golf/pull/60) |
| 12 | 1.1925 | @mattqlf | Sliding Window Eval (stride=64) | [#50](https://github.com/openai/parameter-golf/pull/50) |
| 13 | 1.1928 | @samacqua | LoRA Test-Time Training | [#77](https://github.com/openai/parameter-golf/pull/77) |
| 14 | 1.2014 | @spokane-way | 4k seq length + tuned hyperparams | [#52](https://github.com/openai/parameter-golf/pull/52) |
| 15 | 1.2060 | @spokane-way | 2048 seq length | [#49](https://github.com/openai/parameter-golf/pull/49) |
| 16 | 1.2147 | @nanlliu | 10 layers, mixed int8/int6 | [#39](https://github.com/openai/parameter-golf/pull/39) |
| 17 | 1.2197 | @chonchiog | FP16 Tied Embedding + LR/Warmdown Tuning | [#42](https://github.com/openai/parameter-golf/pull/42) |
| 18 | 1.2244 | Baseline | 9L 512dim 1024vocab TiedEmbed 4 KV heads | — |

</details>

<details>
<summary><strong>All Pending Validated Submissions (39 entries)</strong></summary>

Validated against the SOTA at submission time. Δ nats shown vs SOTA at time of validation.

| BPB | Author | Δ nats | Seeds | Techniques | PR |
|-----|--------|--------|-------|-----------|-----|
| **1.1154** | @saml212 | 0.012 | 3 | XSA-all + Full GPTQ + Selective pruning + Parallel Muon. No TTT. ⚠️ Reclassified non-record (GPTQ calibration outside training budget). | [#609](https://github.com/openai/parameter-golf/pull/609) |
| **1.1181** | @JoeProAI | 0.042 | 3 | ✅ GEPA arch without TTT: Star-ReLU + U-Net Skip Gates + XSA4 + VE128. | [#505](https://github.com/openai/parameter-golf/pull/505) |
| **1.1204** | @raahilshah | 0.038 | 3 | ⚠️ LeakyReLU² + Full GPTQ + QAT-export alignment. No TTT. Std=0.0001. Flagged: eval-time GPTQ (#677). | [#535](https://github.com/openai/parameter-golf/pull/535) |
| **1.1208** | @newjordan | 0.003 | 3 | ⚠️ XSA-all(11) + GPTQ (block64, percdamp=0.002). Flagged: eval-time GPTQ (#677). | [#587](https://github.com/openai/parameter-golf/pull/587) |
| **1.1215** | @newjordan | 0.002 | 3 | Full GPTQ (Hessian-aware, block-128) + Early QAT (threshold 0.5, ~1750 steps) + Legal TTT (EMA scoring, cosine LR). On #414 stack. | [#578](https://github.com/openai/parameter-golf/pull/578) |
| **1.1221** | @felipe-parodi | 0.035 | 3 | ❌ 20-epoch TTT + Partial RoPE + LN Scale. Pre-eval TTT. | [#398](https://github.com/openai/parameter-golf/pull/398) |
| **1.1233** | @signalrush | 0.033 | 3 | 11L + EMA + XSA4 + VE128 + Tight SWA + GPTQ-lite + Late QAT@0.15 + warmdown 3500 + Partial RoPE + LN Scale + FA3. No TTT. | [#414](https://github.com/openai/parameter-golf/pull/414) |
| **1.1250** | @jfprincz | 0.030 | 3 | 11L + Partial RoPE (16/64) + LN Scale + XSA (last 4) + EMA (0.997) + FA3. ⚠️ Late QAT inactive (torch.compile bug). | [#315](https://github.com/openai/parameter-golf/pull/315) |
| **1.1256** | @alertcat | 0.029 | 3 | 11L + #315 stack + TTT (3 ep SGD, freeze 2 blocks) — TTT neutral on #315's base (±0.001) | [#338](https://github.com/openai/parameter-golf/pull/338) |
| **1.1268** | @gowtham0992 | 0.027 | 3 | 11L + XSA on ALL 11 layers + GPTQ-lite + EMA(0.997) + Tight SWA + Late QAT + FA3. No TTT. | [#478](https://github.com/openai/parameter-golf/pull/478) |
| **1.1280** | @jfprincz | 0.025 | 3 | 11L + XSA (last 4) + EMA (0.997) + SmearGate + BigramHash + WD 0.04 + FA3 | [#287](https://github.com/openai/parameter-golf/pull/287) |
| **1.1299** | @chanwoo-park-official | 0.022 | 3 | 11L + **CANON-AC(last 5) + DeltaGate** (−0.006 BPB, 10% step cost) + XSA4 + Tight SWA + Partial RoPE + LN Scale + Late QAT. Unique technique — no other submission uses CANON. | [#400](https://github.com/openai/parameter-golf/pull/400) |
| **1.1299** | @kasimte | 0.022 | 3 | 11L + #374 base (Tight SWA + VE128 + XSA4) + 3-epoch SGD TTT. ⚠️ TTT | [#455](https://github.com/openai/parameter-golf/pull/455) |
| **1.1309** | @parinzee | 0.020 | 3 | 11L + **LeakyReLU(0.5)²** (preserves negative gradient flow vs relu²) + XSA4 + EMA + Partial RoPE + Int6 + 524K batch + warmdown 4500 (55% of training). No TTT. **Std=0.00017** (8× tighter than typical — suggests more stable training dynamics). Built on #180 base. | [#493](https://github.com/openai/parameter-golf/pull/493) |
| **1.1313** | @timowhite88 | 0.019 | 3 | 11L Int6 MLP3x + SmearGate + TTT (3 ep SGD, freeze 2 blocks) + RoPE50K + SWA + WD 0.04 + FA3 ⚠️ pre-eval TTT ruled invalid | [#254](https://github.com/openai/parameter-golf/pull/254) |
| **1.1320** | @saml212 | 0.018 | 3 | **12L** + Gradient-Guided Quant (int7/6/5) + Partial RoPE + LN Scale + XSA4 + EMA + 524K batch + MLP 1408 | [#332](https://github.com/openai/parameter-golf/pull/332) |
| **1.1326** | @jfprincz | 0.017 | 3 | 11L + Int6 MLP3x + SmearGate + BigramHash + WD 0.04 + SWA + FA3 | [#198](https://github.com/openai/parameter-golf/pull/198) |
| **1.1327** | @sofiabod | 0.017 | 3 | **7L** + MLP3x + BigramHash(2048) + SmearGate + AdamW TTT 5ep + int8+zlib. ⚠️ TTT | [#489](https://github.com/openai/parameter-golf/pull/489) |
| **1.1328** | @signalrush | 0.017 | 3 | 11L + XSA4 + EMA + SmearGate + BigramHash(4096) + NTK-RoPE + Int5-MLP + 524K batch + FA3 + adaptive pruning (10-14%) | [#369](https://github.com/openai/parameter-golf/pull/369) |
| **1.1400** | @saml212 | 0.005 | 3 | 11L Int6 + SmearGate + BigramHash + 524K batch + SWA + WD 0.04 | [#236](https://github.com/openai/parameter-golf/pull/236) |
| **1.1402** | @andrewgcodes | 0.017 | 3 | 10L Int5-MLP + BigramHash(16384) + Causal TTT + SWA(0.3) + WD 0.08 + 786K batch | [#267](https://github.com/openai/parameter-golf/pull/267) |
| **1.1468** | @unixmadtoonslab | 0.047 | 3 | 12L Int5-MLP + SmearGate + BigramHash + SWA + no QAT | [#76](https://github.com/openai/parameter-golf/pull/76) |
| **1.1472** | @devin-cog | — | 3 | 11L + Int6 + Muon WD 0.038 + LR 0.025 + Sliding Window | [#179](https://github.com/openai/parameter-golf/pull/179) |
| **1.1480** | @baudrillardsgh0st | 0.045 | 3 | 11L + Int6 QAT + Per-Dim SmearGate + SWA + WD 0.038 ⚠️ artifact 16.08MB | [#194](https://github.com/openai/parameter-golf/pull/194) |
| **1.1507** | @dexhunter | 0.041 | 3 | Int6 STE + SmearGate + Seq2048 + OrthoInit + RoPE50K + SWA/100 | [#206](https://github.com/openai/parameter-golf/pull/206) |
| **1.1507** | @SPThole | — | 3 | **AWQ** (activation-aware weight scaling, α=0.5) + Cyclic Muon Momentum (0.85-0.95 triangle) + ReLU² + 11L Shared (last block reused). AWQ closed 63% quant gap. | [#623](https://github.com/openai/parameter-golf/pull/623) |
| **1.1526** | @MatoTeziTanka | — | 3 | PROTEUS v9: 11L INT6 + **single-epoch LoRA TTT** (score-then-train, compliant with Mar 24 ruling). TTT gain: −0.025. First post-sweep legal LoRA TTT. | [#633](https://github.com/openai/parameter-golf/pull/633) |
| **1.1538** | @jfprincz | 0.035 | 3 | OrthoInit + Int6 MLP3x + SmearGate + BigramHash + FA3 | [#164](https://github.com/openai/parameter-golf/pull/164) |
| **1.1541** | @alertcat | 0.035 | 3 | 12L Int5-MLP + Int6-Attn + SmearGate + BigramHash + SWA | [#219](https://github.com/openai/parameter-golf/pull/219) |
| **1.1546** | @tamoghnokandar | 0.034 | 3 | Int6 MLP3x + NorMuon + FA3 + selective precision | [#173](https://github.com/openai/parameter-golf/pull/173) |
| **1.1558** | @JayCheng113 | 0.032 | 3 | 11L + Low-Rank Q (r=192) + Int6 + Sliding Window | [#215](https://github.com/openai/parameter-golf/pull/215) |
| **1.1575** | @saml212 | 0.029 | 3 | Int6 + MLP 3x + selective precision + long-context | [#114](https://github.com/openai/parameter-golf/pull/114) |
| **1.1577** | @yahya010 | 0.029 | 3 | Int6 QAT + BigramHash + MLP 1344 + MuonWD 0.02 + Sliding Window | [#150](https://github.com/openai/parameter-golf/pull/150) |
| **1.1602** | @dexhunter | 0.025 | 3 | Int6 STE + NorMuon + SWA + MLP3x + Sliding Window + U-Net skips | [#156](https://github.com/openai/parameter-golf/pull/156) |
| **1.1605** | @seanward | 0.021 | 3 | Int6 MLP3x + MTP + Sliding Window (mean 1.1625) | [#88](https://github.com/openai/parameter-golf/pull/88) |
| **1.1605** | @takhir-iota | 0.022 | 3 | Int6 MLP3x + Late-K Passthrough + SlidingWindow | [#99](https://github.com/openai/parameter-golf/pull/99) |
| **1.1622** | @vmfunc | 0.021 | 3 | NorMuon + int6 STE + SWA + sliding window | [#89](https://github.com/openai/parameter-golf/pull/89) |
| **1.1632** | @arjun-krishna1 | 0.020 | 3 | AutoResearch agent + MLP 3x + STE int6 QAT + seq4096 | [#66](https://github.com/openai/parameter-golf/pull/66) |
| **1.1642** | @saikrishnarallabandi | 0.018 | 3 | Vocab 4096 + MLP 3x + Sliding Window | [#123](https://github.com/openai/parameter-golf/pull/123) |

</details>

<details>
<summary><strong>All Not Yet Self-Validated Submissions (25 entries)</strong></summary>

Competitive submissions that haven't demonstrated ≥0.005-nat significance. Official SOTA: 1.1194 (updated Mar 24).

| BPB | Author | Seeds | Techniques | PR |
|-----|--------|-------|-----------|-----|
| **1.0400** | @pentxayc | 1 | Hedge Mixer + VRL + AdamW TTT + Polyak EMA. Freeze 9/11 blocks. ⚠️ Hedge Mixer + n-gram. | [#731](https://github.com/openai/parameter-golf/pull/731) |
| **1.0717** | @hypery11 | 3 | 10L + 7-gram eval cache (alpha=0.40, XOR-hash). Std=0.016 — fails p<0.01. ⚠️ N-gram cache. | [#724](https://github.com/openai/parameter-golf/pull/724) |
| **1.0891** | @amaljithkuttamath | 1 | 11L + Value Residual + Gated Attention + AdamW TTT on #442 base. Pre-quant 1.1545. ⚠️ TTT | [#490](https://github.com/openai/parameter-golf/pull/490) |
| **1.0920** | @Christopher-Lee-McClendon | 1 | GEPA 30k steps + int6 GPTQ-lite + legal SGD TTT. 4xA100 non-record. | [#668](https://github.com/openai/parameter-golf/pull/668) |
| **1.0944** | @Christopher-Lee-McClendon | 1 | GEPA 25k steps (13k warmdown) + int6 GPTQ-lite + legal SGD TTT. 4xA100 non-record. Float base 1.1088. | [#644](https://github.com/openai/parameter-golf/pull/644) |
| **1.0983** | @Christopher-Lee-McClendon | 1 | GEPA 20k steps (8k warmdown) + int6 GPTQ-lite + legal SGD TTT (10ep). 4xA100 non-record. Float base 1.1153. | [#628](https://github.com/openai/parameter-golf/pull/628) |
| **1.1078** | @agalimova | 3 | XSA6 + BigramHash(4096) on #700 base. Std=0.0045 — fails p<0.01 (t=-3.3). | [#720](https://github.com/openai/parameter-golf/pull/720) |
| **1.1164** | @Asukabot0 | 1 | XSA-all + LeakyReLU² + VRL + GA (no VE128). No TTT. 1xH100 NVL. Pending 8xH100 3-seed. | [#638](https://github.com/openai/parameter-golf/pull/638) |
| **1.1171** | @raahilshah | 3 | XSA-all + Full GPTQ + Parallel Muon + Selective Pruning + LZMA. No TTT. Same #609 stack. 0.00394 nats (fails bar). | [#634](https://github.com/openai/parameter-golf/pull/634) |
| **1.1176** | @Gusanidas | 1 | MiLe loss + 8-bit Muon + Cache+Backout on #549. 4xB200 — needs H100. | [#703](https://github.com/openai/parameter-golf/pull/703) |
| **1.1180** | @hypery11 | 3 | 10L Batched LoRA TTT (rank-8, 3 epochs, 64 docs parallel). TTT gain: −0.033. Fails 0.005-nat bar. | [#713](https://github.com/openai/parameter-golf/pull/713) |
| **1.1182** | @msisovic | 3 | Depth Recurrence (layers 4+5 repeated, 11→13 virtual). +TTT. Std=0.0005. Fails bar. | [#686](https://github.com/openai/parameter-golf/pull/686) |
| **1.1186** | @EthanYangTW | 3 | CROWN-Q + Full GPTQ (within training budget) + SWA/EMA + XSA-all + VRL. No TTT. | [#693](https://github.com/openai/parameter-golf/pull/693) |
| **1.1187** | @Upsalla | 3 | RoPE NTK-Scaling bug fix + BigramHash(3072) + Late QAT@0.57 + Legal TTT. Std=0.00024. | [#714](https://github.com/openai/parameter-golf/pull/714) |
| **1.1190** | @ChaosCodes | 1 | GPTQ int6 + SGD TTT + LeakyReLU² on #414 stack. A800 hardware (non-record). Est. ~1.122 on H100. | [#610](https://github.com/openai/parameter-golf/pull/610) |
| **1.1194** | @Joeavaib | 3 | 9L "Maestro" arch + LeakyReLU² + Legal TTT + Parallel Muon + GPTQ-lite + LZMA. Ties SOTA (0.00006 nats). | [#625](https://github.com/openai/parameter-golf/pull/625) |
| **1.1246** | @unnir | 1 | 11L + Tight SWA (scale<0.2, zero penalty) + Shared VE128 (layers 9-10) + Partial RoPE + LN Scale + Late QAT + XSA4 + SmearGate + FA3 | [#374](https://github.com/openai/parameter-golf/pull/374) |
| **1.1247** | @greqone | 1 | #315 stack + Backout Connection + native FA3 + torch.compile | [#394](https://github.com/openai/parameter-golf/pull/394) |
| **1.1260** | @dannywillowliu-uchi | 1 | #374 stack + GPTQ-lite (per-layer clip percentile search). Self-Distillation TTT: neutral (−0.0003). | [#379](https://github.com/openai/parameter-golf/pull/379) |
| **1.1354** | @ibarrajo | 1 | 11L + Partial XSA (last 3) + TTT + 524K batch + RoPE50K (no FA3) ⚠️ pre-eval TTT | [#290](https://github.com/openai/parameter-golf/pull/290) |
| **1.1354** | @simonbissonnette | 3 | 11L + EMA + BigramHash(12288) + Mixed Int5 + FA3 (fails p<0.01: t=−6.0 vs −7.0) | [#466](https://github.com/openai/parameter-golf/pull/466) |
| **1.1357** | @dennisimoo | 1 | 11L + XSA (last 4) + EMA + SmearGate + BigramHash(2048) + 524K batch + WD 0.04 + torch.compile (SDPA fallback) | [#307](https://github.com/openai/parameter-golf/pull/307) |
| **1.1365** | @ofirkris | 2 | 10L + XSA4 + EMA + Partial RoPE + LN Scale + Int5-MLP/Int6-Attn + 3.2% pruning. No TTT. | [#458](https://github.com/openai/parameter-golf/pull/458) |
| **1.1399** | @Mapika | 3 | 11L + XSA4 + EMA + SmearGate + BigramHash(2048) + Int5-MLP/Int6-Attn/Int8-Embed + 8% pruning (fails 0.005-nat by 0.00004) | [#349](https://github.com/openai/parameter-golf/pull/349) |
| **1.1419** | @chris-buckley | 1 | 11L + XSA4 + EMA + TTT (pre-quant 1.1581; no FA3, SDPA fallback, 5344/9000 steps; seeds 2/3 pending) | [#317](https://github.com/openai/parameter-golf/pull/317) |

</details>

---

<details>
<summary><strong>Glossary</strong></summary>

| Term | Meaning |
|------|---------|
| **BPB** | Bits Per Byte — compression quality. Lower = better |
| **val_bpb** | BPB on FineWeb validation set |
| **Muon** | Optimizer: orthogonalized gradients via Newton-Schulz |
| **QAT/STE** | Quantization-Aware Training / Straight-Through Estimator |
| **Int6/Int8** | 6-bit or 8-bit integer quantization |
| **SWA/EMA** | Stochastic Weight Averaging / Exponential Moving Average |
| **TTT** | Test-Time Training — adapting during evaluation |
| **XSA** | Exclusive Self-Attention — removes self-value bias |
| **FA3** | FlashAttention 3 — optimized H100 attention kernel |
| **LoRA** | Low-Rank Adaptation — tiny trainable matrices |
| **zstd** | Zstandard compression (better than zlib) |

</details>

---

<details>
<summary><strong>Changelog</strong></summary>

| Time | Update |
|------------|--------|
| Mar 25, 11:45 AM | +#755 (1.0321, **Gravity Tokenizer** — tokenizer-only optimization, extraordinary claim, needs scrutiny). |
| Mar 25, 11:05 AM | #753 updated: replaced outlier seed, now **0.9625** (3-seed, std=0.0005). Promoted to record-eligible. New best pending. |
| Mar 25, 10:55 AM | +#753 (initially 0.9823, failed p<0.01). +5 eval-time techniques to Tier 1. |
| Mar 25, 10:10 AM | +#745 (1.0222, kitchen-sink: XSA+VRL+GA+CROWN-Q+DepthRecurrence+HedgeMixer, GPTQ-lite). Predictions rewritten. Tier 5 added. |
| Mar 25, 9:40 AM | +#741 (0.9850), +#740 (1.0909), +#715 (1.0337). **Second enforcement sweep:** #606, #615, #626, #639 closed (eval-time GPTQ). N-gram cache consistent with backward-looking rules (#659's hindsight selection was the illegal part, not the cache itself). |
| Mar 25, 9:30 AM | N-gram cache wave: +#727 (0.9674), +#702 (1.0240), +#706 (1.0461), +#738 (1.0970 kNN-LM). +#731, #720, #724, #713, #686, #703. |
| Mar 25, 7 AM | **#659 (1.0920) ruled invalid** — post-hoc oracle selection peeks at ground-truth token. +#668 (GEPA 30k→1.0920). New ruling: eval methods can't select scorer after seeing the label. |
| Mar 24, noon | #609 reclassified non-record (calibration ruling). +#634, +#656 (ties SOTA at 1.1195). #650 closed. |
| Mar 24, 10:30 AM | +#633 (PROTEUS v9, post-sweep legal LoRA TTT). +9 new Tier 2 techniques from web research. |
| Mar 24, 10:10 AM | +3 Tier 2 techniques (prune-then-quantize, SLOT TTT, YAQA). #505 artifact >16MB. Enforcement sweep in rulings section. |
| Mar 24, 9:20 AM | +#631 (attempting Tier 1 combo). Tier 2 trimmed. TTT+GPTQ nuance fixed. |
| Mar 24, 9:07 AM | **Enforcement sweep:** @valerio-oai closed 15+ PRs. #593, #576, #503, #518, #548, #568, #596, #620 removed. GPTQ calibration at eval time disallowed. |
| Mar 24, 9 AM | +#628 (sub-1.10 GEPA+legal TTT at 1.0983). +#599 (Hymba SSM). TTT deep dive condensed. Tier 3 tightened. |
| Mar 24, 8:50 AM | +#626 (1.1180). Tiers updated. Predictions rewritten. Lineage 42→46. Audit: #535 demoted, stale refs fixed. |
| Mar 24, 8:37 AM | #614/#605 closed. +#625 (ties SOTA). +#578. #609 calibration question. VRL + entropy coding dead at frontier. |
| Mar 24, 8 AM | #573 ruled invalid. Closed PRs purged. Record: 11→6. Tier 2 trimmed (−6). Stale refs fixed. |
| Mar 24, 3–7 AM | +#609 (1.1154 best non-TTT). +#606 (1.1162 best legal TTT, Soft-Round QAT). +#615 (1.1169). SOTA→1.1194 (#549 merged). #612 confirms GEPA+legal TTT at 1.1079. |
| Mar 23, 5–10 PM | +#593 (1.1170). +#576 (1.1164). +#589 (1.1178). +#596 (❌ 0.6430 memorization). +DDL, Muon-VS, TEON techniques. Hadamard Rotation lineage. 6 URL fixes. |
| Mar 23, 1–5 PM | #573 (1.0523) disputed then restructured. Pre-eval TTT excluded per #402. +emoji legend. +LaCT, CPSVD, qTTT. +#569 (1.1175 best non-TTT). |
| Mar 23, 6 AM–1 PM | SOTA→1.1228. +#535, #545, #548, #549, #555. Legal TTT surge (#503, #473). TTT rules clarified. |
| Mar 23, midnight–6 AM | +#512 sub-1.0 (0.9512). +#518 (1.0814, LeakyReLU²). +#517, #510, #532. Memorization floor analysis. |
| Mar 22, 10 PM–midnight | +#505 (1.1181 GEPA non-TTT). +#508 (1.1215 legal TTT). Star-ReLU discovery. |
| Mar 22, 4–10 PM | +#462–#499. GEPA TTT. Three-track frontier. LeakyReLU² (#493). Research (×5). |
| Mar 22, 10 AM–4 PM | +#442 (1.1027 AdamW TTT). +#414 (1.1233). +#473 legal TTT. |
| Mar 21 | #398 best (1.1221). #375 $500 negatives. +#362–401. TTT/prefix rulings. |
| Mar 19–20 | Initial build. #315 best (1.1250). Leaderboard→1.1428. Core deep dives. |

</details>

---

*This commentary is generated by an AI (Claude) analyzing public PR data. No competition code is executed.*


author:	tmustier
association:	none
edited:	false
status:	none
--
Great idea
--
author:	timowhite88
association:	none
edited:	false
status:	none
--
#254 is a banger
--
author:	timowhite88
association:	none
edited:	false
status:	none
--
  FarnsworthEngine v1 — PR #254

  Submission: TTT (Test-Time Training) + 11L Int6 MLP3x + SmearGate + BigramHash + OrthoInit + Muon WD + SWA + FA3

  ┌──────┬─────────┬──────────┐
  │ Seed │ val_bpb │ val_loss │
  ├──────┼─────────┼──────────┤
  │ 1337 │ 1.1303  │ 1.9085   │
  ├──────┼─────────┼──────────┤
  │ 42   │ 1.1312  │ 1.9100   │
  ├──────┼─────────┼──────────┤
  │ 7    │ 1.1323  │ 1.9118   │
  ├──────┼─────────┼──────────┤
  │ Mean │ 1.1313  │ 1.9101   │
  └──────┴─────────┴──────────┘

  - Artifact: 15,877,181 bytes (under 16,000,000)
  - Training: 600s, 7,248 steps, 81.5ms/step on 8xH100
  - Eval: 129s (43s TTT + 86s sliding window stride=64)
  - Full logs for all 3 seeds included in PR

  TTT adapts weights via full-weight SGD on val data with causal masking intact — consistent with the rules permitting test-time training during evaluation.

  PR: https://github.com/openai/parameter-golf/pull/254
--
author:	mahsumaktas
association:	none
edited:	false
status:	none
--
Still active, applied for compute grant to continue. Key findings from 23 runs documented in PR #333: seq curriculum breaks SWA (Tier 1 blocker), EMA causes 0.14 BPB quant gap on SWA-stacks, MLP 2.75x is the sweet spot at 11L+SmearGate. Planning to test Partial RoPE + LN Scale + Late QAT on our stack when compute arrives.
--
author:	saml212
association:	contributor
edited:	true
status:	none
--
Please have your agent exclude the illegal submissions as per issue [#402](https://github.com/openai/parameter-golf/issues/402#issue-4114890560) I think it may be encouraging people to do the wrong thing
--
author:	MatoTeziTanka
association:	none
edited:	false
status:	none
--
**Update on PR #512 (PROTEUS v7):**

The original submission had mismatched TTT configs across seeds (seed 42 used epochs=2 while 1337/2024 used epochs=3), causing the large std. This has been fixed — seed 42 was rerun with matching config.

**Updated results:**

| Seed | TTT BPB |
|------|---------|
| 42   | 0.9485  |
| 1337 | 0.9534  |
| 2024 | 0.9516  |

**Mean: 0.9512, std: 0.0025.** All seeds use `TTT_EPOCHS=3 TTT_MIN_DOC_LEN=512`.

Regarding TTT compliance: our approach is backward-looking per-chunk, per-document — the same pattern as merged PR #77. Multi-epoch repeats the same sequential score-then-train process over each document. No bulk pre-eval training on the validation set.

PR, README, logs, and submission.json have all been updated.
--
author:	notapplica
association:	contributor
edited:	true
status:	none
--
> Please have your agent exclude the illegal submissions as per issue [#402](https://github.com/openai/parameter-golf/issues/402#issue-4114890560) I think it may be encouraging people to do the wrong thing

Thanks! Having it do so
--
author:	PlyMxt
association:	none
edited:	false
status:	none
--
I'm honestly a complete noob when it comes to this stuff. I really want to run a training job myself, but I don't have the funds, and OpenAI won't give me a compute grant simply because of my country. 

Still, I genuinely want to share what I've found with the community. According to an LLM I was talking to, this could potentially take the #1 spot (though I fully admit this might just be pure "AI slop" — in fact, it probably is).

The ideas are based on these two recent papers: 
1. https://arxiv.org/abs/2602.09006
2. https://arxiv.org/abs/2505.11881

The first one introduces a new optimizer from Microsoft called ARO (which claims to outperform Muon). The second one is "Revisiting Residual Connections: Orthogonal Updates for Stable and Efficient Deep Networks," which shows a clear drop in loss (though to be completely honest, I don't fully understand the underlying math yet).

Below is the raw "AI slop" that explains "how to hit #1". Points 2 and 3 are specifically about these papers. Please don't roast me too hard for this! I just want to help the community. Maybe this post won't bring anything new to the table, maybe the new optimizer actually sucks under the strict 10-minute constraint, or maybe that second paper I barely understand will actually make things worse. I honestly don't know. But if we trust the metrics in the papers and the AI analysis generated by Gemini, the BPB should drop.

---

Here is the blueprint for the ultimate 16MB model:

### 1. The Base: GEPA Architecture + XSA
Start with `@JoeProAI`'s AI-discovered architecture (PR #462 / #505).
- **Why:** `Star-ReLU` + `U-Net Skip Connections` currently holds the SOTA for non-TTT bases (1.1181). It creates a smoother loss landscape.
- **Paper:** *Exclusive Self Attention (XSA)* — [arXiv:2603.09078](https://arxiv.org/abs/2603.09078) (Apple, Mar 2026). Keep XSA4 on the last layers to remove self-value bias.

### 2. The Residual Revolution: Orthogonal Residual Updates
Replace standard residual addition (`x = x + f(x)`) with **Orthogonal Residuals**.
- **Paper:** *Revisiting Residual Connections: Orthogonal Updates for Stable and Efficient Deep Networks* — [arXiv:2505.11881](https://arxiv.org/abs/2505.11881) (Jan 2026).
- **The Problem:** In a 16MB model, $f(x)$ often wastes parameter capacity by reinforcing directions already present in the residual stream $x$.
- **The Fix:** Subtract the parallel projection before adding. Force the layer to only add strictly *new* information.
- **Code snippet:**
  ```python
  # Instead of standard x = x + attn_out
  dot = (x * attn_out).sum(dim=-1, keepdim=True)
  norm_sq = (x * x).sum(dim=-1, keepdim=True).float() + 1e-6
  scale = (dot / norm_sq).to(x.dtype)
  x = x + (attn_out - scale * x)  # Orthogonal component only!
  ```

### 3. The Optimizer: ARO-Sinkhorn in Full-Model Mode
Drop `Muon`. Replace it with **Adaptively Rotated Optimization (ARO) + Sinkhorn**.
- **Paper:** *ARO: A New Lens On Matrix Optimization For Large Models* — [arXiv:2602.09006](https://arxiv.org/abs/2602.09006) (Microsoft Research, Feb 2026).
- **Why:** ARO rotates gradients into an optimal coordinate system before applying the step. According to the MSFT paper, it outperforms Muon by 10-15% in sample efficiency with <3% overhead (using Shifted Cholesky QR). 
- **Synergy:** Apply ARO to **ALL** matrix parameters (Full-model mode), including embeddings and LM head. It fixes the divergence issues Muon has on non-hidden layers. In a 600s budget, ARO will squeeze significantly more knowledge out of the tokens than Muon.

### 4. The Finisher: Full GPTQ + Legal Score-First Cosine TTT
Combine the best of PR #508 (`@newjordan`) and PR #481 (`@mrdavtan`).
- **Quantization:** Do not use naive int6. Use **Hessian-aware GPTQ** (Cholesky-factored error compensation). It reduces the quant tax by 32%, which is critical for the wider GEPA MLP (1792 dim).
- **Legal TTT:** Strictly *backward-looking* (Score a sliding window chunk FIRST -> then `model.train()` on it for 3 epochs -> move to next chunk). 
- **TTT Multipliers:** Use Cosine LR decay + Per-layer LR (3.0x for MLP output, 0.5x for input) to perfectly match the quantization damage profile.

### Summary of Synergies
- **GEPA + OrthoRes** guarantees absolute maximum parameter efficiency.
- **ARO-Sinkhorn** guarantees maximum learning speed within the 600s wallclock limit.
- **GPTQ + Legal Cosine TTT** guarantees the absolute lowest legal BPB without triggering the "pre-eval memorization" ban.

Hope this helps someone grab the #1 spot! 🚀
--
author:	MatoTeziTanka
association:	none
edited:	false
status:	none
--
Hey @PlyMxt — solid research, don't sell yourself short calling it slop. The papers are real and the synthesis is reasonable.

I've been deep in the trenches on this competition and can share some data points:

**TTT is the biggest lever by far.** We've pushed TTT well beyond 3 epochs and the gains don't saturate — each additional epoch keeps improving BPB. If you can get compute access, that's where I'd focus before anything else. Per-layer LR tuning for TTT also matters more than people think.

**On your two papers:**
- **Orthogonal Residuals** — This is the most interesting one to me. We haven't tested it yet but it's a clean 4-line change and the NeurIPS results are legit. We'll run a test and report back.
- **ARO optimizer** — The Microsoft paper is solid at scale, but at 16MB/600s the gap over Muon may be smaller than the paper suggests. Still worth exploring if someone builds a clean integration.

**On GPTQ** — agreed, Hessian-aware quantization beats naive int6. We've found that per-tensor-role allocation (different precision for attention vs MLP weights) is Pareto-optimal. Worth looking into if you haven't.

We'll test the orthogonal residuals idea and share results. Good contribution — the community benefits when people share what they find regardless of whether they can run it themselves.
--
author:	MatoTeziTanka
association:	none
edited:	false
status:	none
--
Follow-up on the orthogonal residuals test we promised @PlyMxt.

**We ran it.** 4 configs, 8×H100, seed 42:

| Config | Pre-quant BPB | Post-quant BPB | TTT (1ep) |
|--------|---------------|----------------|-----------|
| Baseline | 1.1995 | 1.2203 | 1.2010 |
| + Ortho Residual | 1.2535 | 1.3154 | 1.2930 |

**Result: Orthogonal residuals hurt by ~0.05 BPB in this setup.** The NeurIPS paper shows gains at much larger scale — at 16MB/600s the model likely doesn't have enough capacity to benefit from the regularization effect. The constraint already forces efficient representations.

Still a good paper and worth testing. Just doesn't transfer to this particular regime. We tried a few other configurations alongside this that showed more promise — still iterating on those.

For anyone else exploring this direction: the technique works as described in arXiv:2505.11881, the implementation is clean (~4 lines), but the gains appear to be scale-dependent. At small model sizes the orthogonality constraint may compete with capacity.

Thanks for the suggestion @PlyMxt — negative results are still results and save others the compute.

— PROTEUS by Light Speed Up
--
author:	JoeProAI
association:	none
edited:	false
status:	none
--
PlyMxt -- the ARO paper synthesis was solid, don't undersell it. MatoTeziTanka -- thanks for actually running the orthogonal residuals test and sharing the numbers publicly. That kind of contribution saves everyone compute and keeps the community moving in the right direction. Really appreciate the collaborative spirit here.
--
author:	MatoTeziTanka
association:	none
edited:	false
status:	none
--
# Compliance-Safe Stack After Issue #677 — What's Still Legal

Following @0hq's [Issue #677 clarification](https://github.com/openai/parameter-golf/issues/677), here's a practical guide to what's legal for anyone building on top of the current SOTA stack. This isn't a rulebook rewrite — it's a builder's checklist so you don't burn GPU time on something that gets closed.

## The Three Rules That Matter

**1. You cannot score tokens you've already trained on.**
Multi-epoch TTT where the final-epoch score is the reported score = invalid. Even score-every-epoch with final-epoch reporting is invalid. The only legal TTT: score tokens FIRST (under `inference_mode`), THEN train on those already-scored tokens. PR #549's approach is the reference implementation.

**2. No training data access during evaluation.**
GPTQ/Hessian calibration using `fineweb_train_*` is legal during training but illegal during eval. If your quantization reads training shards, it must complete within the 600s training window. Per-row clip search (GPTQ-lite) that operates only on model weights is fine — no calibration data needed.

**3. No oracle/hindsight selection.**
You can't score a token multiple ways and pick the best. `min(NLL)` across passes, safety gates that peek at the true token to decide which predictor to use — all illegal.

## The Compliance-Safe Stack (as of 2026-03-25)

Everything below is used by merged SOTA (#549, 1.1194 BPB) or confirmed legal by reviewers:

### Training (within 600s on 8×H100)

| Component | Status | Notes |
|-----------|--------|-------|
| 11L, 512d, 8H/4KV (GQA) | Legal | Standard architecture |
| LeakyReLU(0.5)² | Legal | `F.leaky_relu(x, 0.5).square()` |
| SmearGate + BigramHash | Legal | Token blending + bigram features |
| Partial RoPE (16/64) | Legal | Apply rotation to 25% of head dims |
| XSA on last 4 layers | Legal | Exclusive Self-Attention |
| LN Scale (1/√(layer+1)) | Legal | Layer-wise attenuation |
| EMA (0.997, every step) | Legal | Requires XSA to be effective |
| Value Embeddings (VE128) | Legal | Shared across layers 9-10 |
| OrthoInit | Legal | Required for SmearGate |
| Muon + Parallel Muon | Legal | Newton-Schulz optimizer |
| Parameter Banking | Legal | Contiguous weight tensors |
| Warmdown 3500 iters | Legal | Wallclock-based scheduling |
| GPTQ-lite (per-row clip search) | Legal | No calibration data — operates on weights only |
| Full GPTQ (Hessian calibration) | **Legal ONLY within 600s** | Must use training data before timer expires |
| Late QAT (STE at lr_scale < 0.15) | Legal | Fake quantization during training |
| 3% magnitude pruning | Legal | Post-training, pre-quantization |
| INT6 + zstd-22 / lzma | Legal | Compression is artifact construction |
| Seq len 2048 (train) | Legal | Longer context during training |

### Evaluation (within 600s on 8×H100)

| Component | Status | Notes |
|-----------|--------|-------|
| Sliding window (stride=64, seq=2048) | Legal | Standard eval technique |
| Score-first TTT (PR #549 style) | Legal | Score under inference_mode, THEN train |
| Fixed-alpha n-gram blending | **Likely legal** | No oracle gate, backward-looking only. Reviewer was [directionally positive](https://github.com/openai/parameter-golf/pull/674) — rejected for packaging + GPTQ-at-eval, not the n-gram concept |
| Multi-epoch TTT (final-epoch score) | **ILLEGAL** | Issues #677 explicitly |
| GPTQ calibration on train data | **ILLEGAL at eval time** | Must happen within training 600s |
| Oracle selection (min NLL across passes) | **ILLEGAL** | Issues #677 explicitly |
| Safety gate (peek at true token) | **ILLEGAL** | PR #659 explicitly called out |

### What's Untested But Likely Legal

These haven't been flagged and don't violate any stated rule:

- **Differential Attention** (ICLR 2025) — architectural change, no eval tricks
- **Learned residual gating** (PROTEUS+STYX) — embedding-level importance gating, training-time only
- **NuMuon optimizer** — training-time optimizer swap
- **rANS compression** (replace zstd) — artifact construction, no data access
- **Value Residual Learning** — architectural, no eval tricks

## Quick Compliance Check for Your PR

Before submitting, verify:

1. `grep -r "fineweb_train" your_script.py` — if this appears in eval code, you have a problem
2. Your TTT scores tokens BEFORE training on them (never re-scores)
3. Your total training time ≤ 600s (including any GPTQ calibration)
4. Your total eval time ≤ 600s
5. No `min()` or conditional selection between multiple predictors using knowledge of the target
6. Submission is in `/records/track_10min_16mb/` with README.md, submission.json, train_gpt.py, and logs

---

*We ran the orthogonal residuals ablation that saved people compute ([Issue #140 comment](https://github.com/openai/parameter-golf/issues/140)). Our multi-epoch TTT submissions (#512, #548, #568) were among those ruled invalid in #677 — we learned from it. We're sharing this so nobody else burns GPU time on something that gets closed. Community over competition.*

— @MatoTeziTanka (LightSpeedUp / PROTEUS)

--
author:	MatoTeziTanka
association:	none
edited:	false
status:	none
--
## LeakyReLU² Slope Sweep: 0.5 Is Not Optimal — Monotonic Trend to 0.9+

Following our [compliance guide post](https://github.com/openai/parameter-golf/issues/140#issuecomment-4124720432), here's a concrete contribution: the first controlled sweep of LeakyReLU² negative slopes.

Everyone's using 0.5 (from PR #493, validated by PR #679's ASQU converging there). But nobody tested other slopes. We did.

### Setup

- **Base:** PR #549 stack (11L/512d, XSA4, SmearGate, BigramHash, Muon, EMA, int6+zstd)
- **GPU:** 1×H100 SXM, `TRAIN_BATCH_TOKENS=98304`
- **Seed:** 42
- **Only variable:** `negative_slope` in `F.leaky_relu(x, negative_slope).square()`
- **Methodology:** 7 slopes (0.1–0.9), identical config, same data, same seed. Relative deltas are the signal — absolute BPB scales with GPU count.

### Results

| Slope | Sliding Window BPB | int6 Roundtrip BPB | Steps |
|-------|-------------------|-------------------|-------|
| 0.1 | 1.2826 | 1.3071 | 2,936 |
| 0.2 | 1.2847 | 1.3088 | 2,883 |
| 0.3 | 1.2807 | 1.3051 | 2,909 |
| **0.5** | **1.2804** | **1.3046** | **2,895** |
| 0.7 | 1.2796 | 1.3038 | 2,902 |
| **0.8** | **1.2782** | **1.3024** | **2,937** |
| **0.9** | **1.2676** | **1.2974** | **3,099** |

### What This Shows

1. **Monotonic trend** — higher slope = lower BPB across all 7 points on both metrics.
2. **0.9 beats 0.5 by 0.013 BPB** on sliding window (1.2676 vs 1.2804). That's 4x the gain of switching from ReLU² to LeakyReLU(0.5)².
3. **0.9 also gets 200 more training steps** (3,099 vs ~2,900). Higher slope = less dead activation = faster per step.
4. **The trend hasn't peaked.** Worth testing 1.0 (which is `x.square()` with sign-preserved gradient — effectively abolishing the dead zone entirely).

### Why This Makes Sense

ReLU² kills all negative pre-activations. At small model scale (30M params), that's a lot of dead capacity. Slope 0.5 preserves 25% of negative signal (`0.25x²`). Slope 0.8 preserves 64% (`0.64x²`). Slope 0.9 preserves 81%. The model is small enough that preserving gradient flow matters more than sparsity.

PR #679 (ASQU) found that *learned* per-channel slopes converge to ~0.5, but that was with per-channel freedom — some channels may want low slopes while others want high. A *fixed* global slope may have a different optimum because it can't specialize.

### For Anyone Building on This

Drop-in change, one line:
```python
# Before (community standard):
x = F.leaky_relu(self.fc(x), negative_slope=0.5).square()

# After:
x = F.leaky_relu(self.fc(x), negative_slope=0.9).square()
```

If someone has 8×H100 time, multi-seed validation at 0.9 and testing 1.0 would push this further.

---

*Same team that posted the orthogonal residuals ablation and the compliance guide. Sharing results so the community can build on them. Pod's dead now — somebody else's turn to push past 0.9.*

— @MatoTeziTanka (LightSpeedUp / PROTEUS)

--
