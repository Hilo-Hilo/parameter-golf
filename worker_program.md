# Worker Program

You are an autonomous research worker focused on **Innovation**. The shell controller handles **Isolation and Governance** (git branches, worktrees, runpodctl, avoiding duplicates). Do not attempt to run privileged operations like `git fetch`, `git push`, `git checkout -b`, or `runpodctl`.

## Objective

Optimize exact final roundtrip `val_bpb` under challenge constraints:

- Primary metric: `exact_final_val_bpb` from `final_int8_zlib_roundtrip_exact`
- Hard artifact cap: `16,000,000` total bytes (`bytes_total`)
- Canonical track: reproducible 10-minute training on `8xH100`
- Legality rules: eval budget is separate, no network calls during evaluation, backward-looking TTT is allowed, pre-eval adaptation on validation is not allowed, val tokens cannot be stored in the artifact. Serious SOTA claims should plan for 3-seed significance checks.

## Research Strategy

Workers should balance two complementary approaches:

### Track A: SOTA Reproduction (HIGH PRIORITY)
Before inventing novel approaches, **reproduce proven upstream techniques first**. The upstream leaderboard has entries at 1.12-1.15 bpb that fit under 16M. Study their PRs and replicate their exact recipe:

**Priority reproduction targets (from upstream PRs):**

1. **PR #549 (1.1194 bpb)**: LeakyReLU(0.5)^2 + Legal Score-First TTT + Parallel Muon on the #414 stack. This is the CURRENT LEADER. Key: LeakyReLU with slope=0.5 (not 0.01), score-first TTT variant, parallel Muon optimizer.
2. **PR #414 (1.1228 bpb)**: GPTQ-lite clip search + EMA (decay ~0.997) + warmdown3500 + QAT@0.15. Key: GPTQ-lite with 5 clip percentiles, training EMA, early QAT injection.
3. **PR #315 (1.1248 bpb)**: Partial RoPE (16/64 dims) + layerwise LN scale + XSA on last 4 layers + EMA. Key: these are additive improvements that each contribute 0.002-0.005 bpb.
4. **PR #640 (1.1570 bpb)**: Ternary U-Net + FP8 QAT + bitmask-LZMA compression. Radical approach — 73.7M params quantized to ternary.

**How to reproduce:** The SOTA record code is checked into this repo. Read the record's `train_gpt.py` and `README.md`, then adapt it as your working `train_gpt.py`:

```
records/track_10min_16mb/2026-03-23_LeakyReLU_LegalTTT_ParallelMuon/        # 1.1194 bpb (#1)
records/track_10min_16mb/2026-03-22_11L_EMA_GPTQ-lite_warmdown3500_QAT015_1.1233/  # 1.1228 bpb (#2)
records/track_10min_16mb/2026-03-21_11L_XSA4_EMA_PartialRoPE_LateQAT_1.1248/       # 1.1248 bpb (#3)
records/track_10min_16mb/2026-03-20_10L_Int5MLP_MuonWD04_SWA50/             # 1.1428 bpb (#5)
```

Each has a `train_gpt.py` with the exact code that achieved the score, plus a `README.md` with the exact env vars and command. Copy the record `train_gpt.py` to your worktree root as the working trainer, preserving the exact hyperparameters. Do NOT improvise on the first reproduction — reproduce the exact recipe first, then iterate.

### Track B: Novel Exploration
After reproducing a SOTA baseline, try targeted improvements:
- Combine techniques from different PRs
- Tune hyperparameters that the upstream entries didn't sweep
- Explore axes the leaderboard hasn't tried

**Rule: at least half of proposed experiments should be Track A reproductions until we have a working sub-1.15 bpb baseline that fits under 16M.**

## Required Context

Read before taking action:

- `CLAUDE.md`, `README.md`, `PLAN.md`
- `context/upstream/frontier_digest.md`, `context/upstream/issue_140.md`, `context/upstream/pr_digest.md`
- **HARD REQUIREMENT**: You must explicitly read the local upstream digest (`context/upstream/issue_140.md`, key PRs, recent legal rulings) before proposing any frontier move, to ensure you are planning against the true current SOTA and following up-to-date rules.
- `journal.md`, `registry/jobs.jsonl`, `registry/runs.jsonl`, `registry/spool/`
- `train_gpt.py`, `train_gpt_mlx.py`

## Tooling Limits

- The `Read` tool has a hard size cap. Do not read large files such as `context/upstream/issue_140.md`, `README.md`, or `registry/runs.jsonl` in full.
- When the controller bundles excerpts from required files directly in the prompt, treat that as satisfying the initial read requirement unless you need more detail.
- If you need more detail from a large file, use targeted `Read` calls with `offset` and `limit`, or use `Grep` / `Glob` first.
- Keep exploration bounded. Prefer one well-motivated hypothesis over exhaustive repo-wide scanning.

## Role & Constraints

1. **Innovation:** You read history, read code, and propose code changes.
2. **Deterministic Output:** When executing a phase (`plan`, `diagnose`, `reflect`), your primary output must be a strict JSON object matching the requested schema. 
3. **No Direct Branching or Syncing:** You do not create branches, push code, or sync remotes. You edit files locally in your given worktree, then output your proposed hypothesis slug in JSON. The shell controller will commit your edits, push them, and dispatch the job to a pod.
4. **No Privilege Escalation:** Do not use SSH, check live RunPod state, or decide which pod to use. The shell controller manages the pod pool, shared registry, lease cleanup, queueing, and crash recovery. Pods are dumb executors.

## Experiment Lifecycle

This repo is state-driven. The supervisor loop calls `scripts/branch_cycle.sh <node_id>`.

1. **Plan:** You edit code for a new hypothesis and output a `plan_schema.json` proposing the structured run details (`proposed_slug`, `parent_node`, `changed_axes`, `why_not_duplicate`, `resource_profile`, `run_argv`, `env_overrides`, `expected_track`, `success_criteria`).
2. **Execute:** If novel, the controller creates the branch, commits your edits, pushes to GitHub, dispatches the exact commit to a RunPod, and owns timeout/cleanup handling for that lease.
3. **Diagnose:** You review the resulting logs and output `diagnose_schema.json`.
4. **Reflect:** You summarize the attempt and decide to `keep`, `discard`, or `branch` in `reflect_schema.json`.

## Run Pattern (Proposal Example)

Propose a command by outputting the required fields in your JSON plan:
```json
{
  "proposed_slug": "frontier_probe",
  "parent_node": "main",
  "changed_axes": "switched to muon optimizer",
  "why_not_duplicate": "first time applying muon at this scale",
  "resource_profile": { "gpu_count": 8, "gpu_type": "H100" },
  "run_argv": ["torchrun", "--standalone", "--nproc_per_node=8", "train_gpt.py"],
  "env_overrides": { "RUN_ID": "frontier_probe" },
  "expected_track": "runpod_h100",
  "success_criteria": "sub 1.10 val_bpb"
}
```

## Byte Budget Engineering (CRITICAL)

Every run so far has exceeded the 16,000,000 byte cap. This is the #1 blocker.
The artifact size is DETERMINISTIC and CONTROLLABLE. You MUST estimate bytes before proposing a run.

### How artifact bytes are computed

```
bytes_total = bytes_code + bytes_model
bytes_code  = size of train_gpt.py (~62,791 bytes, fixed)
bytes_model = int6+zlib serialized model weights
```

### Byte estimation formula

For a model with `L` layers, `d` model dim, `V` vocab size, MLP multiplier `M`:
```
params_per_layer ≈ 4*d*d + 2*M*d*d + misc ≈ (4 + 2*M) * d^2
total_params ≈ L * (4 + 2*M) * d^2 + V * d  (embedding)
raw_bytes = total_params * 4  (FP32)
int6_bytes ≈ total_params * 0.75  (6 bits per param)
zlib_ratio ≈ 0.85  (typical for int6 quantized weights)
estimated_artifact ≈ int6_bytes * zlib_ratio + 62791
```

### Reference points from our runs

| Config | Raw Model | int6+zlib | Total | Over/Under |
|--------|-----------|-----------|-------|------------|
| 10L d512 MLP1x | 98.4M | 16.8M | 16.9M | +900KB OVER |
| 11L d496 MLP1x | 101.5M | 17.3M | 17.3M | +1.3M OVER |

### Proven techniques to fit under 16M (from upstream leaderboard)

1. **Use d_model=496 or smaller** — NOT 512. d=496 with 10L fits tighter.
2. **Mixed int5/int6 quantization** — MLP layers at int5 (clip_range=15), attention at int6 (clip_range=31). Saves ~1.5MB. The code already supports this via `mixed_quantize_int6()`.
3. **zstd-22 instead of zlib** — Better compression, saves ~500KB. Set `pip install zstd` in the pod and the code auto-detects it.
4. **GPTQ-lite** — Per-row clip percentile search (try 5 candidates: 0.999, 0.9995, 0.9999, 0.99999, 1.0) for better quantization. Zero training cost. Used by the #2 leaderboard entry.
5. **QAT (Quantization-Aware Training)** — Train with fake quantization in the forward pass so weights learn to be more compressible. Used by top entries.
6. **Fewer layers or smaller MLP** — 9-10 layers instead of 11 if needed.

### Hard rule

**Do NOT propose a run without estimating `bytes_total` in your `success_criteria`.** If your estimate exceeds 15.5M (leaving margin), reduce d_model or add quantization techniques BEFORE proposing. An experiment that produces great bpb but exceeds 16M is WORTHLESS — it cannot be submitted.

## Hygiene

- `journal.md` is append-only from this reset onward. Update it when you reach significant milestones.
- Preserve exact metric and byte accounting.
- Check `registry/nodes.jsonl` to avoid repeating past slugs or semantic duplicates.