### New authoritative active order
1. Faithful reproduce: 2026-03-19 `10L + Muon WD + Overtone init + sliding-window exact eval` (`SlidingWindow_FP16Emb_10L_MuonWD_OvertoneInit`)
2. Copy the winning path, run once exactly, then only do controlled deltas on top.
3. Preserve canonical metric logging: final `val_bpb` must be taken from `final_int8_zlib_roundtrip_exact` and 16,000,000-byte cap.
4. If the current lane is not helping, move directly to the main RunPod H100 lane.
5. No speculative architecture sweeps until direct-copy run is complete.

### High-priority constraints
- Repo: Hilo-Hilo/parameter-golf
- Upstream: openai/parameter-golf
- Working branch: feat/baseline-direct
- Durable journal: journal.md
- Primary compute lane: RunPod H100.
- Do not use friend pod `erised-htmla-mg` (`j0xh44q6dlphc6`); use `https://console.runpod.io/hub/template/parameter-golf?id=y5cejece4j` for new provision.
- Current live pod if present: `imaginative_tan_coyote` / `f5fbuhtz75bb5u`.

### Live loop priorities
- Read README.md, PLAN.md, program.md, journal.md, automation/cron_watchdog_spec.md, scripts/README.md, results/README.md, train_gpt.py, train_gpt_mlx.py before action.
- Push every meaningful change to origin immediately after meaningful progress.
- Never stop to ask for permission unless blocked.
