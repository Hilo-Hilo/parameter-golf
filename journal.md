# journal.md

Append-only project journal for `Hilo-Hilo/parameter-golf`.

Rules for future updates:
- Never edit or rewrite prior entries.
- Only append new entries at the end of this file.
- Append whenever there is a material project update: attempt, code edit, result, hardware change, infra change, or directional decision.

## 2026-03-18 23:37 PDT — Journal initialized + retroactive project history

### Project identity and scope
- Repo: `Hilo-Hilo/parameter-golf`
- Upstream reference: `openai/parameter-golf`
- Active working branch during this phase: `research/continuous-mar18`
- Local repo path: `/Users/hansonwen/Library/CloudStorage/GoogleDrive-wenhanson0@gmail.com/My Drive/Clawd Workspace/OpenAI Parameter Golf/parameter-golf`
- Goal: minimize exact `final_int8_zlib_roundtrip` `val_bpb` under the 16,000,000-byte artifact cap and preserve a path to a valid 10-minute 8xH100 submission.

### Hardware and runtime used so far
- Main hardware used in recorded attempts so far: local Apple Silicon / MLX workflow via `train_gpt_mlx.py`
- Observed runtime details from logs:
  - `mlx_version: 0.31.1`
  - tokenizer: `./data/tokenizers/fineweb_1024_bpe.model`
  - train shards: `./data/datasets/fineweb10B_sp1024/fineweb_train_*.bin`
  - validation shards: `./data/datasets/fineweb10B_sp1024/fineweb_val_*.bin`
  - validation size repeatedly logged as `62021632` tokens
  - local fast-iteration regime used only `1/195` train shards for cheap comparable search
- RunPod / DGX Spark were explicitly approved later for faster training, but were **not yet used in the recorded attempts below**.

### Repo / automation work completed before or during this phase
- `008dc0b` — added lightweight experiment harness and research plan
- `3055a96` — added cron watchdog scripts for continuous worker
- `0ea3ea2` — improved experiment runner wallclock tracking
- `0eacdde` on `main` — deterministic watchdog tick helper added and later merged into the working flow via branch history
- Continuous worker infrastructure added in repo:
  - `automation/continuous_worker_prompt.md`
  - `automation/cron_watchdog_spec.md`
  - `scripts/start_continuous_worker.sh`
  - `scripts/check_continuous_worker.py`
  - `scripts/stop_continuous_worker.sh`
  - `scripts/watchdog_tick.py`
- Continuous worker / watchdog behavior during this session:
  - detached Codex worker used for long-running autonomous experimentation
  - cron watchdog used to monitor and restart the worker when needed
  - worker was later explicitly stopped and watchdog disabled when Hanson said there was no need to continue

### Main technical bug discovered and fixed
Problem discovered:
- repeated MLX runs were crashing with `exit_code=137`
- the pattern suggested the training phase itself could finish, but final full validation / roundtrip evaluation was unstable
- root cause determined from the code path: MLX validation accumulation was retaining a large lazy graph over the full validation sweep instead of materializing per-batch losses immediately

Fix merged:
- `28966e9` — `Fix MLX validation accumulation for smoke runs`
- The effective change was to stop accumulating a lazy MLX tensor for the whole validation scan and instead materialize each batch loss immediately, then accumulate in Python scalar space.

Code snippet of the core fix:

```python
# old pattern (caused large lazy accumulation across the full validation scan)
# total_loss = total_loss + compiled_loss(x, y).astype(mx.float32) * chunk_token_count

# new pattern
 total_loss_sum = 0.0
 batch_loss = compiled_loss(x, y).astype(mx.float32)
 mx.eval(batch_loss)
 total_loss_sum += float(batch_loss.item()) * chunk_token_count
 val_loss = total_loss_sum / total_tokens
```

Why this mattered:
- this unlocked the first valid canonical MLX run
- after the fix, the local MLX lane became usable for structured hyperparameter exploration instead of dying at final eval

### Side diagnostic work that informed the fix
- A separate isolated diagnosis branch (`fix/mlx-final-eval`) was used to test an alternative hypothesis: dropping training/optimizer state and reloading the quantized checkpoint into a fresh eval-only model before final validation.
- That branch was useful for diagnosis, but the simpler fix that actually landed on the main research branch was the validation accumulation change above.
- The side branch was not the final merged solution for this phase.

### Attempts and results recorded in `results/results.tsv`

#### Crash / invalidating attempts
1. `20260319T020650Z_mlx_smoke_seq1024_t8192_i50`
   - status: `crash`
   - exit code: `137`
   - note: smoke interrupted after live runner edit; training killed before final validation

2. `20260319T021557Z_mlx_smoke_v2_val32768_i20`
   - status: `crash`
   - exit code: `137`
   - wallclock: `380.079434s`
   - note: larger eval batch / zero warmup probe still died before valid canonical metric

3. `20260319T022024Z_mlx_smoke_v3_val32768_i20`
   - status: `crash`
   - exit code: `137`
   - wallclock: `467.125354s`
   - note: baseline-shaped current config still failed before canonical final metric

4. `20260319T022905Z_mlx_smoke_small_d256_l6_i10`
   - status: `crash`
   - exit code: `137`
   - wallclock: `160.118993s`
   - note: even a smaller 6x256 / 10-step smoke still crashed, confirming the issue was structural rather than only model size

5. `20260319T042202Z_mlx_l6_d256_i400`
   - status: `crash`
   - exit code: `1`
   - wallclock: `0.073331s`
   - note: immediate failed start before successful rerun of the same experiment

#### First valid canonical MLX row
6. `20260319T023241Z_mlx_smoke_small_d256_l6_i10_evalfix`
   - status: `discard`
   - exact final `val_bpb`: `3.49374268`
   - pre-quant `val_bpb`: `3.4913`
   - final val loss: `5.89903817`
   - bytes total: `2,987,370`
   - wallclock: `516.474763s`
   - conclusion: the validation accumulation fix worked; local MLX lane was now viable

#### Iteration ladder on validated 6x256 shape
7. `20260319T032341Z_mlx_l6_d256_i100`
   - status: `keep`
   - exact final `val_bpb`: `2.68893497`
   - bytes total: `3,188,883`
   - wallclock: `533.853678s`
   - conclusion: large improvement from 10 -> 100 iterations with similar total runtime because full validation dominated wallclock

8. `20260319T033404Z_mlx_l6_d256_i200`
   - status: `keep`
   - exact final `val_bpb`: `2.54909245`
   - bytes total: `3,212,025`
   - wallclock: `554.165823s`
   - conclusion: more steps still clearly paid off and byte headroom remained huge

9. `20260319T034438Z_mlx_l6_d256_i300`
   - status: `keep`
   - exact final `val_bpb`: `2.23501331`
   - bytes total: `3,347,584`
   - wallclock: `566.723766s`
   - conclusion: continued improvement; step count remained the strongest cheap axis at that moment

10. `20260319T042303Z_mlx_l6_d256_i400`
    - status: `keep`
    - exact final `val_bpb`: `2.15883947`
    - bytes total: `3,499,734`
    - wallclock: `600.032175s`
    - conclusion: still improving, still far under byte cap

11. `20260319T050231Z_mlx_l6_d256_i500_rerun`
    - status: `keep`
    - exact final `val_bpb`: `2.10856141`
    - bytes total: `3,579,890`
    - wallclock: `617.801195s`
    - conclusion: returns from more iterations were shrinking but still positive

12. `20260319T054208Z_mlx_l6_d256_i600_rerun`
    - status: `keep`
    - exact final `val_bpb`: `2.09778821`
    - bytes total: `3,639,308`
    - wallclock: `642.123846s`
    - conclusion: additional steps still helped, but the gain from 500 -> 600 was small enough to justify exploring a new axis

#### Depth shift after iteration gains began to compress
13. `20260319T055436Z_mlx_l7_d256_i600`
    - status: `keep`
    - exact final `val_bpb`: `2.07206045`
    - bytes total: `4,145,729`
    - wallclock: `735.800758s`
    - conclusion: moving from 6 layers -> 7 layers at the same width and step budget beat simply pushing the 6-layer model harder; this became the best completed result in the journaled phase

#### Interrupted / unscored next-step exploration
14. `mlx_l8_d256_i600`
    - log existed and showed partial progress
    - observed partial training progress at one checkpoint: at least `step 150/600`
    - this run did **not** finish successfully in the journaled phase and should be treated as interrupted / unscored
    - the worker later went stale/dead and was restarted by the watchdog before Hanson asked to stop the project loop

### Approach details and what the data suggests so far
- Cheap local iteration on MLX became useful only after fixing validation accumulation.
- The first profitable path was:
  1. stabilize the local lane
  2. use a small, byte-safe configuration (`6x256`) to get comparable canonical runs quickly
  3. sweep iteration count upward while watching exact roundtrip `val_bpb`
  4. once gains from raw extra iterations diminished, switch to another cheap axis (depth)
- The first clear second-axis win was depth:
  - `l6 d256 i600` -> `2.09778821`
  - `l7 d256 i600` -> `2.07206045`
- This suggests the search should not stay on “more steps only”; parameter allocation / architecture axes likely have better marginal return now.

### Time elapsed observations
- Total run time was dominated less by pure training and more by final evaluation / roundtrip validation.
- Even when training remained relatively short, total wallclock stayed in the ~8.5 to 12+ minute range locally because the full validation path was expensive.
- This is one of the main reasons Hanson later explicitly approved RunPod / DGX Spark for faster training and broader search.

### Operator guidance captured during this phase
- Hanson may send directional guidance directly in the Telegram DM while the worker is running; those directions should be treated as durable project steering.
- Hanson explicitly approved using **RunPod and/or DGX Spark** for faster training instead of staying local-MLX-only.
- Hanson requested that `journal.md` exist at the repo root and become the durable append-only project journal.
- Hanson also requested that every new project update append attempts, edits, results, hardware used, elapsed time, code, and approach details to this file.

### Worker / watchdog state at the end of this journaled phase
- A detached continuous worker and repo-scoped watchdog were used to keep experimentation running without manual babysitting.
- The worker was restarted multiple times by the watchdog when it went stale/dead.
- Hanson later said there was no need to continue, so the worker was explicitly stopped and the cron watchdog was disabled.
- Final stopped worker pid in that stop action: `2761`

### Best completed result at the end of this entry
- Best completed exact final `val_bpb`: `2.07206045`
- Run: `20260319T055436Z_mlx_l7_d256_i600`
- Bytes total: `4,145,729`
- Branch: `research/continuous-mar18`

### Immediate implication for the next phase
- Do not resume by blindly adding more local iterations only.
- The next serious winning plan should likely:
  - move onto faster hardware (RunPod / DGX Spark)
  - preserve the validated harness + canonical metric discipline
  - search more aggressively over architecture / parameter allocation / tokenizer / train-time efficiency axes
  - keep every material result and decision appended to this journal

## 2026-03-19 00:30 PDT — Continuous automation shifted to remote-first 24/7 append-only mode

### Why this entry exists
- Hanson requested that the continuous research loop resume in a 24/7 remote-first mode on branch `research/continuous-mar18`.
- Hanson also made `journal.md` the durable append-only project log for all material automation and research updates.
- This entry records the standing operating rules added to the repo-local worker/watchdog docs and launcher metadata.

### Hardware and runtime used for this update
- Hardware used for this repo update: local operator terminal only; no training job was launched
- Remote hardware used in this update: none
- Intended preferred training hardware after this update: DGX Spark first when accessible, RunPod as the other preferred remote lane
- Secondary sanity-check lane after this update: local MLX only

### Repo / automation edits completed in this update
- `automation/continuous_worker_prompt.md`
  - added `journal.md` to required startup reading
  - made the worker explicitly remote-first, architecture-first, and append-only-journal-aware
  - instructed the worker to append a journal update for every material attempt, edit, result, hardware change, or directional decision
  - clarified that the worker should keep running until manually interrupted and should leave restart/stop control to automation unless Hanson says otherwise
- `automation/cron_watchdog_spec.md`
  - documented that the watchdog is protecting a 24/7 remote-first worker
  - documented `journal.md` as the durable journal the worker must preserve append-only
- `scripts/start_continuous_worker.sh`
  - added `journalFile` to the state payload
  - added runtime metadata fields for `operatingMode`, preferred/secondary compute lanes, `researchStrategy`, and `journalPolicy`
- `scripts/README.md`
  - documented the new continuous-worker stance in one short section

### Standing rules now captured in automation
- Preferred execution lane: remote CUDA training on DGX Spark / RunPod when accessible
- Search bias: architecture-first and parameter-allocation-first before spending more time on blind longer local runs
- Local MLX role: short sanity checks, harness validation, and unblockers only
- Journal policy: append-only, never rewrite prior entries, and append every material update with attempts, edits, results, hardware used, elapsed time, code/docs touched, and approach details
- Worker lifecycle: continue 24/7 until manually stopped

### Attempts, results, and non-results for this update
- Training attempts run: none
- Worker restart attempted by me: none
- Worker stop attempted by me: none
- Experimental results generated: none
- Operational result: repo-local automation instructions now match the remote-first 24/7 journaling strategy Hanson requested

### Lightweight validation run after edits
- `bash -n scripts/start_continuous_worker.sh`
- `python3 -m py_compile scripts/check_continuous_worker.py scripts/watchdog_tick.py`
- Additional behavior constraint respected: no watchdog tick was executed and no worker process was restarted during this update

### Time elapsed and approach notes
- Approximate elapsed time for this update: about 10 minutes of repo inspection, targeted doc/script edits, and lightweight validation planning
- Approach used: keep the change surface small, update the worker prompt as the authoritative behavior source, mirror that strategy into the watchdog spec, and add just enough launcher metadata so the runtime state advertises the intended mode
