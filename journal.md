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

## 2026-03-19 00:31 PDT — Commit/push attempt blocked by sandboxed `.git` write restrictions

### Attempt and result
- Attempted to stage and commit the remote-first automation update on branch `research/continuous-mar18`
- Command path attempted: `git add ...` followed by `git commit -m "Update continuous worker for remote-first journaling"`
- Result: blocked by environment-level permission failure before commit creation
- Observed failure text: `fatal: Unable to create '.git/index.lock': Operation not permitted`

### Hardware and runtime used for this attempt
- Hardware used: local operator terminal only
- Remote hardware used: none
- Worker restart attempted by me: none
- Worker stop attempted by me: none

### Repo state after the failed git write
- Edited files remain only:
  - `automation/continuous_worker_prompt.md`
  - `automation/cron_watchdog_spec.md`
  - `scripts/start_continuous_worker.sh`
  - `scripts/README.md`
  - `journal.md`
- Validation status remains unchanged from the previous entry: shell syntax and Python bytecode compilation passed

### Approach note
- No destructive workaround was attempted because the restriction is on writing repo metadata under `.git`, not on the working tree files themselves

## 2026-03-19 00:32 PDT — Remote-first automation committed, pushed, and relaunched under watchdog

### Attempt and result
- After the earlier sandboxed `.git/index.lock` failure, the same repo changes were committed successfully from the main operator session.
- Commit created on `research/continuous-mar18`: `0c08114` — `Shift continuous worker to remote-first 24/7 mode`
- Push result: `origin/research/continuous-mar18` advanced from `0440190` to `0c08114`

### Hardware and runtime used for this update
- Hardware used: local operator terminal only
- Remote hardware used: none yet
- Training runs launched in this step: none

### Automation state changes completed
- Detached continuous worker restarted successfully via `./scripts/start_continuous_worker.sh`
- New worker pid: `12143`
- Watchdog cron job `0200ab09-9051-4a73-a227-cf7a8f068780` was re-enabled
- Watchdog delivery remains configured to announce into the Telegram DM every run

### Repo state and operating mode after relaunch
- Branch: `research/continuous-mar18`
- Operating mode: `remote-first-24-7`
- Preferred compute: `dgx-spark`, `runpod`
- Secondary compute: `local-mlx`
- Research strategy: `architecture-first`
- Journal policy: `append-only`

### Approach note
- The repo-local worker is now live again under the updated prompt/spec/launcher metadata and can continue building from this remote-first stance until Hanson manually stops it.

## 2026-03-19 01:01 PDT — DGX Spark remote CUDA lane repaired; first real remote baseline and depth win logged

### Why this entry exists
- The remote-first loop needed an actually usable CUDA lane before architecture search could continue.
- DGX Spark was reachable, but the initial software stack was not usable for `train_gpt.py`.
- This entry records the remote repair work, the failure modes encountered, the minimal trainer fallback added to keep the repo usable, and the first completed DGX Spark comparison runs.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote repo path created for this work: `~/parameter-golf`
- Remote dataset/tokenizer state used for all scored runs in this entry:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Approximate elapsed time for this update: about 30 minutes end to end including remote setup, repair, smoke validation, and two scored architecture runs

### Remote setup and infra findings
- Confirmed SSH access to `dgx-spark` from the local machine.
- Cloned `Hilo-Hilo/parameter-golf` onto DGX Spark and checked out branch `research/continuous-mar18`.
- Downloaded the cheap comparable dataset subset with `python3 data/cached_challenge_fineweb.py --variant sp1024 --train-shards 1`.
- Found the DGX system Python environment had `torch 2.10.0+cpu`, so the first CUDA trainer launch failed immediately with `RuntimeError: CUDA is required`.
- Created a clean remote venv `~/parameter-golf/.venv-cuda` and installed:
  - `numpy`
  - `sentencepiece`
  - `torch==2.9.0+cu128`
  - `torchvision==0.24.0`
  - `torchaudio==2.9.0`
- Verified the repaired venv saw the GPU:
  - `torch.cuda.is_available() == True`
  - device count `1`
  - device name `NVIDIA GB10`
- The next trainer launch then failed inside Triton / Inductor because the host lacked `Python.h`; `/usr/include/python3.12` existed but only contained Pillow imaging headers, not Python development headers, and passwordless `sudo` was not available.

### Repo edit completed in this update
- `train_gpt.py`
  - added `DISABLE_COMPILE` env handling
  - guarded both `torch.compile(zeropower_via_newtonschulz5)` and `torch.compile(base_model, ...)`
  - logged `torch_compile:enabled|disabled` in the run log
- Purpose of the edit:
  - preserve the default compiled fast path for normal CUDA hosts
  - provide a minimal remote fallback for GB10 / ARM hosts where Triton's native build path is blocked by missing system headers
- Validation for the repo edit:
  - `python3 -m py_compile train_gpt.py` passed locally
  - copied the updated `train_gpt.py` to `~/parameter-golf/train_gpt.py` on DGX Spark for immediate testing

### Attempts and results
1. `20260319T073629Z_dgx_l7_d256_i600_cal1`
   - status: `crash`
   - hardware: DGX Spark GB10
   - wallclock: `3.337413s`
   - result: failed immediately because the remote default Torch build was CPU-only
   - conclusion: DGX connectivity was fine; runtime stack was not

2. `20260319T074326Z_dgx_cuda_smoke_l7_d256_i10`
   - status: `crash`
   - hardware: DGX Spark GB10 with repaired CUDA venv
   - wallclock: `10.687298s`
   - result: reached CUDA but failed in Triton / Inductor native helper compilation because `Python.h` was unavailable
   - conclusion: a trainer-side compile fallback was the cleanest unblocker

3. `20260319T074539Z_dgx_cuda_nocompile_smoke_l7_d256_i10`
   - status: `discard`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `4.05009256`
   - pre-quant `val_bpb`: `4.0449`
   - final val loss: `6.83841164`
   - bytes total: `3,132,014`
   - wallclock: `224.752517s`
   - conclusion: the no-compile fallback produced the first valid canonical DGX Spark row and fully unblocked the remote lane

4. `20260319T075011Z_dgx_cuda_nocompile_l7_d256_i600`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.07993040`
   - pre-quant `val_bpb`: `2.0791`
   - final val loss: `3.51187535`
   - bytes total: `4,054,116`
   - wallclock: `294.237825s`
   - conclusion: this established the first meaningful remote baseline; it was much faster than the comparable local MLX lane while remaining far under the artifact cap

5. `20260319T075551Z_dgx_cuda_nocompile_l8_d256_i600`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.07359205`
   - pre-quant `val_bpb`: `2.0726`
   - final val loss: `3.50117332`
   - bytes total: `4,595,170`
   - wallclock: `332.748109s`
   - conclusion: the first real remote architecture move worked; adding one layer improved exact final `val_bpb` by `0.00633835` versus the remote `7x256` baseline while preserving ample byte headroom

### Milestone reporting completed
- Ran:
  - `openclaw system event --text "Parameter Golf milestone: DGX Spark remote CUDA lane unblocked with DISABLE_COMPILE fallback; first canonical remote smoke row completed" --mode now`

### What the data suggests now
- The DGX Spark remote lane is now materially more useful than the local MLX lane for ongoing search:
  - `7x256 i600` on DGX Spark completed in `294.237825s`
  - the comparable best local MLX `7x256 i600` run took `735.800758s`
- The depth trend from local MLX survives on the remote PyTorch lane:
  - remote `7x256 i600`: `2.07993040`
  - remote `8x256 i600`: `2.07359205`
- The remote `8x256` result did not beat the earlier local MLX `7x256 i600` exact score of `2.07206045`, but it came very close while giving a much faster iteration loop and a cleaner path for continued architecture search.

### Immediate next direction
- Keep the DGX Spark lane as the primary search path for now, using `DISABLE_COMPILE=1` on this host.
- Stay architecture-first.
- The next cheap decisive remote branch should likely test one of:
  - `9x256` at the same step budget to see whether depth continues paying
  - a modest width reallocation around the new best remote depth while watching byte growth

## 2026-03-19 01:40 PDT — DGX depth trend reverses at 9 layers; keep 8x256 as the remote pivot

### Why this entry exists
- The prior journal entry left two immediate remote branches: continue the depth ladder to `9x256`, or shift into a modest width reallocation around `8x256`.
- This entry records the first of those two branches so the next step can be chosen from data rather than assumption.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Total wrapped wallclock for the scored run: `370.209483s`

### Remote repo / infra note
- The DGX checkout itself was still at commit `ead46ea` and had a local tracked modification on `train_gpt.py` plus an untracked `.venv-cuda/` directory, so I did not force a remote git sync.
- Instead, I verified by SHA-256 that the remote `train_gpt.py` file matched the current local `HEAD` trainer exactly, which was sufficient for a comparable scored run without disturbing the remote working tree.

### Attempt and result
1. `20260319T083321Z_dgx_cuda_nocompile_l9_d256_i600`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.07644708`
   - pre-quant `val_bpb`: `2.0755`
   - final val loss: `3.50599392`
   - bytes total: `5,134,420`
   - bytes model: `5,086,546`
   - wallclock: `370.209483s`
   - command shape: `9` layers, `256` model dim, `4` heads, `2` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: the depth trend did not continue past `8` layers on this budget; `9x256` regressed by `0.00285503` exact `val_bpb` versus the best remote `8x256` run while costing `539,250` more total bytes and about `37.46s` more wallclock

### What changed in the search picture
- Remote depth progression on the same cheap budget is now:
  - `7x256 i600`: `2.07993040`
  - `8x256 i600`: `2.07359205`
  - `9x256 i600`: `2.07644708`
- This is the first clean sign that the remote depth ladder has a local optimum at `8` layers for the current width, batch, and step budget.
- `9x256` remains valid and comfortably under the artifact cap, so the result is still useful as a boundary marker even though it is not the new best remote score.

### Immediate next direction
- Keep `8x256 i600` as the remote pivot configuration.
- Shift the next cheap architecture probe from additional depth to a modest width reallocation around `8x256`, watching exact roundtrip `val_bpb`, byte growth, and total wallclock together.

## 2026-03-19 01:48 PDT — Width reallocation at the 8-layer pivot produces a new best score

### Why this entry exists
- After `9x256` regressed relative to `8x256`, the next single-axis remote branch was a modest width increase at the `8`-layer pivot.
- This entry records that width result because it produced the new best exact final `val_bpb` in the repo so far.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Total wrapped wallclock for the scored run: `378.508121s`

### Attempt and result
1. `20260319T084141Z_dgx_cuda_nocompile_l8_d288_i600`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.06558493`
   - pre-quant `val_bpb`: `2.0643`
   - final val loss: `3.48765362`
   - bytes total: `4,146,280`
   - bytes model: `4,098,406`
   - wallclock: `378.508121s`
   - command shape: `8` layers, `288` model dim, `4` heads, `2` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: reallocating budget from extra depth into extra width at the `8`-layer pivot was clearly the better move; this run beat remote `8x256` by `0.00800712` exact `val_bpb`, beat remote `9x256` by `0.01086215`, and beat the prior repo best local MLX `7x256 i600` score by `0.00647552`

### Notable artifact behavior
- Despite having a larger uncompressed serialized model (`19,241,293` bytes) than remote `8x256`, the quantized + compressed model artifact was **smaller**:
  - remote `8x256` bytes model: `4,547,296`
  - remote `8x288` bytes model: `4,098,406`
- Total artifact size dropped by `448,890` bytes while score improved, which makes this result especially attractive for further width-side exploration.

### Milestone reporting completed
- Ran:
  - `openclaw system event --text "Parameter Golf milestone: DGX 8x288 i600 reached new best exact val_bpb 2.06558493 under 4.15MB total artifact" --mode now`

### What changed in the search picture
- The current remote architecture picture is now:
  - `7x256 i600`: `2.07993040`
  - `8x256 i600`: `2.07359205`
  - `9x256 i600`: `2.07644708`
  - `8x288 i600`: `2.06558493`
- For this cheap DGX budget, the best marginal direction is now clearly width at `8` layers rather than more depth at `256` width.

### Immediate next direction
- Keep `8x288 i600` as the new remote pivot.
- Continue width exploration one hypothesis at a time from this pivot, with the next cheap branch likely another modest width increase at `8` layers while watching whether the surprising compression gain persists.

## 2026-03-19 01:57 PDT — Width keeps paying at 8 layers; 8x320 sets a new repo best

### Why this entry exists
- `8x288` was strong enough that the next clean branch was another modest width increase at the same `8`-layer depth.
- This entry records that follow-up run because it improved the exact final roundtrip metric by a large margin again.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Total wrapped wallclock for the scored run: `415.404068s`

### Attempt and result
1. `20260319T084932Z_dgx_cuda_nocompile_l8_d320_i600`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.04731446`
   - pre-quant `val_bpb`: `2.0462`
   - final val loss: `3.45680471`
   - bytes total: `5,018,127`
   - bytes model: `4,970,253`
   - wallclock: `415.404068s`
   - command shape: `8` layers, `320` model dim, `4` heads, `2` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: the width branch continues to dominate the depth branch on this DGX budget; `8x320` beat `8x288` by `0.01827047` exact `val_bpb`, beat the previous remote depth pivot `8x256` by `0.02627759`, and beat the prior repo-best local MLX `7x256 i600` score by `0.02474599`

### Artifact and scaling notes
- Compared with `8x288`, the compressed artifact grew by `871,847` bytes and wallclock grew by about `36.90s`, but both costs were small relative to the score gain.
- Even at `8x320`, total artifact bytes are still only `5,018,127`, leaving enormous headroom under the `16,000,000` byte cap.
- The raw serialized model grew to `23,669,581` bytes, but int8 + zlib still compressed it effectively enough to stay far below the cap.

### What changed in the search picture
- The current best remote width ladder at `8` layers is now:
  - `8x256 i600`: `2.07359205`
  - `8x288 i600`: `2.06558493`
  - `8x320 i600`: `2.04731446`
- On the current one-shard DGX search budget, width growth at fixed depth is now the clearest profitable direction tested so far.

### Immediate next direction
- Keep `8x320 i600` as the new remote pivot.
- Continue the width ladder one hypothesis at a time at `8` layers, with the next cheap probe likely another modest increase such as `8x352` while monitoring whether the gain curve starts to flatten or the compressed artifact trend turns unfavorable.

## 2026-03-19 02:31 PDT — DGX width ladder continues upward; 8x352 sets another new repo best

### Why this entry exists
- `8x320 i600` was strong enough that the next single-axis remote move remained another modest width increase at the same `8`-layer depth.
- This entry records that follow-up because it produced another clear exact roundtrip improvement and preserved large byte headroom.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote repo state checked before the run:
  - branch: `research/continuous-mar18`
  - remote `train_gpt.py` SHA-256 matched local `HEAD`: `11d75807f9db69f9c000c0d196afb565e5cb011ef6ed414a6f444fa6c7a43b18`
  - remote checkout still showed `HEAD` at `ead46ea` with a tracked `train_gpt.py` modification and untracked `.venv-cuda/`, so I again reused the existing remote checkout without forcing a git sync
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Total wrapped wallclock for the scored run: `476.058172s`

### Attempt and result
1. `20260319T092234Z_dgx_cuda_nocompile_l8_d352_i600`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.04202636`
   - pre-quant `val_bpb`: `2.0408`
   - final val loss: `3.44787597`
   - bytes total: `5,979,040`
   - bytes model: `5,931,166`
   - wallclock: `476.058172s`
   - command shape: `8` layers, `352` model dim, `4` heads, `2` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: the width ladder is still paying cleanly at `8` layers; `8x352` beat `8x320` by `0.00528810` exact `val_bpb`, beat `8x288` by `0.02355857`, and beat the prior best local MLX `7x256 i600` score by `0.03003409`

### Artifact and scaling notes
- Compared with `8x320`, the compressed artifact grew by `960,913` bytes and total wallclock grew by about `60.65s`.
- The exact gain from `8x320 -> 8x352` was smaller than the gain from `8x288 -> 8x320`, which is the first sign that the width curve may be starting to flatten.
- Even so, the total artifact is still only `5,979,040` bytes, leaving more than `10MB` of headroom under the `16,000,000` byte cap.

### Milestone reporting completed
- Ran:
  - `openclaw system event --text "Parameter Golf milestone: DGX 8x352 i600 reached new best exact val_bpb under 6.0MB total artifact" --mode now`

### What changed in the search picture
- The current best remote width ladder at `8` layers is now:
  - `8x256 i600`: `2.07359205`
  - `8x288 i600`: `2.06558493`
  - `8x320 i600`: `2.04731446`
  - `8x352 i600`: `2.04202636`
- Width at fixed depth is still the best branch tested so far on the cheap one-shard DGX budget, but the marginal gain is now compressing.

### Immediate next direction
- Keep `8x352 i600` as the new remote pivot.
- Continue the width ladder one hypothesis at a time, with the next cheap probe likely `8x384` to determine whether the width gains persist past the first sign of flattening.

## 2026-03-19 02:41 PDT — 8x384 beats 8x352 and shrinks the compressed artifact

### Why this entry exists
- `8x352` looked like the first hint that the width ladder might be flattening, so the next single-axis check was `8x384` at the same depth and training budget.
- This entry records that follow-up because it invalidated the flattening concern on this budget and produced another new repo best.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Total wrapped wallclock for the scored run: `510.171901s`

### Attempt and result
1. `20260319T093220Z_dgx_cuda_nocompile_l8_d384_i600`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.03403242`
   - pre-quant `val_bpb`: `2.0324`
   - final val loss: `3.43437854`
   - bytes total: `5,596,614`
   - bytes model: `5,548,740`
   - wallclock: `510.171901s`
   - command shape: `8` layers, `384` model dim, `4` heads, `2` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: the width ladder is still clearly profitable; `8x384` beat `8x352` by `0.00799394` exact `val_bpb`, beat `8x320` by `0.01328204`, and beat the prior best local MLX `7x256 i600` score by `0.03802803`

### Artifact and scaling notes
- This run reversed the prior compression concern:
  - `8x352` bytes total: `5,979,040`
  - `8x384` bytes total: `5,596,614`
- Despite the larger raw serialized model (`33,902,413` bytes), the compressed int8 artifact was `382,426` bytes smaller than `8x352`.
- Wallclock rose by about `34.11s` versus `8x352`, which is a modest cost relative to the score gain.

### Milestone reporting completed
- Ran:
  - `openclaw system event --text "Parameter Golf milestone: DGX 8x384 i600 reached new best exact val_bpb under 5.6MB total artifact" --mode now`

### What changed in the search picture
- The current best remote width ladder at `8` layers is now:
  - `8x256 i600`: `2.07359205`
  - `8x288 i600`: `2.06558493`
  - `8x320 i600`: `2.04731446`
  - `8x352 i600`: `2.04202636`
  - `8x384 i600`: `2.03403242`
- On the current one-shard DGX budget, width remains the dominant architecture branch tested so far, and the surprising compression behavior is still favorable.

### Immediate next direction
- Keep `8x384 i600` as the new remote pivot.
- Continue the width ladder one hypothesis at a time, with the next cheap probe likely `8x416` to determine how long this favorable score-plus-compression trend persists.

## 2026-03-19 03:15 PDT — 8x416 sets another DGX repo best, with expected byte growth

### Why this entry exists
- `8x384 i600` kept the width ladder alive, so the next single-axis remote probe was the planned `8x416 i600` follow-up.
- This entry records that run because it produced another exact roundtrip improvement and established the next remote pivot.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote repo state checked before the run:
  - remote `train_gpt.py` SHA-256 still matched local `HEAD`: `11d75807f9db69f9c000c0d196afb565e5cb011ef6ed414a6f444fa6c7a43b18`
  - remote checkout still showed `HEAD` at `ead46ea` with a tracked `train_gpt.py` modification and untracked `.venv-cuda/`, so I again reused the existing remote checkout without forcing a git sync
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Total wrapped wallclock for the scored run: `574.026824s`

### Attempt and result
1. `20260319T100517Z_dgx_cuda_nocompile_l8_d416_i600`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.03058793`
   - pre-quant `val_bpb`: `2.0293`
   - final val loss: `3.42856266`
   - bytes total: `6,448,782`
   - bytes model: `6,400,908`
   - wallclock: `574.026824s`
   - command shape: `8` layers, `416` model dim, `4` heads, `2` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: the width ladder is still improving at `8` layers; `8x416` beat `8x384` by `0.00344449` exact `val_bpb`, beat `8x352` by `0.01143843`, and beat the prior best local MLX `7x256 i600` score by `0.04147252`

### Artifact and scaling notes
- Compared with `8x384`, the compressed artifact grew by `852,168` bytes and wallclock grew by about `63.85s`.
- Unlike the `8x352 -> 8x384` step, compression no longer improved with extra width:
  - `8x384` bytes total: `5,596,614`
  - `8x416` bytes total: `6,448,782`
- Even so, total artifact size remains far below the `16,000,000` byte cap, leaving about `9.55MB` of headroom.
- The exact score gain was smaller than the `8x352 -> 8x384` jump, which suggests the width branch is still live but now in a more marginal regime that needs another boundary check.

### Milestone reporting completed
- Ran:
  - `openclaw system event --text "Parameter Golf milestone: DGX 8x416 i600 reached new best exact val_bpb 2.03058793 under 6.45MB total artifact" --mode now`

### What changed in the search picture
- The current best remote width ladder at `8` layers is now:
  - `8x320 i600`: `2.04731446`
  - `8x352 i600`: `2.04202636`
  - `8x384 i600`: `2.03403242`
  - `8x416 i600`: `2.03058793`
- Width remains the best architecture branch tested so far on the current one-shard DGX budget, but the score gain per added width step is now clearly smaller than it was around the `288 -> 384` range.

### Immediate next direction
- Keep `8x416 i600` as the new remote pivot.
- Continue one more width step, likely `8x448 i600`, to determine whether the branch is still genuinely profitable or has reached a practical turning point on this cheap DGX budget.

## 2026-03-19 03:27 PDT — 8x448 beats 8x416; width is still alive past 7MB artifacts

### Why this entry exists
- `8x416 i600` improved again but with smaller marginal return, so the next boundary check was the planned `8x448 i600` follow-up.
- This entry records that run because it answered the turning-point question cleanly: width is still improving on this budget.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Total wrapped wallclock for the scored run: `621.201717s`

### Attempt and result
1. `20260319T101633Z_dgx_cuda_nocompile_l8_d448_i600`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.02677234`
   - pre-quant `val_bpb`: `2.0251`
   - final val loss: `3.42212020`
   - bytes total: `7,326,991`
   - bytes model: `7,279,117`
   - wallclock: `621.201717s`
   - command shape: `8` layers, `448` model dim, `4` heads, `2` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: the width ladder is still profitable beyond `8x416`; `8x448` beat `8x416` by `0.00381559` exact `val_bpb`, beat `8x384` by `0.00726008`, and set another repo-best exact score

### Artifact and scaling notes
- Compared with `8x416`, the compressed artifact grew by `878,209` bytes and wallclock grew by about `47.17s`.
- The compressed artifact now sits above `7MB`, but the run still leaves about `8.67MB` of headroom under the `16,000,000` byte cap.
- The exact gain is still materially positive and slightly larger than the `8x384 -> 8x416` gain, so the width branch has not yet turned over on this budget.

### Milestone reporting completed
- Ran:
  - `openclaw system event --text "Parameter Golf milestone: DGX 8x448 i600 reached new best exact val_bpb 2.02677234 under 7.33MB total artifact" --mode now`

### What changed in the search picture
- The current best remote width ladder at `8` layers is now:
  - `8x352 i600`: `2.04202636`
  - `8x384 i600`: `2.03403242`
  - `8x416 i600`: `2.03058793`
  - `8x448 i600`: `2.02677234`
- Width remains the dominant architecture branch tested so far on the current one-shard DGX budget, and the turning point still has not appeared.

### Immediate next direction
- Keep `8x448 i600` as the new remote pivot.
- Continue one more single-axis width step, likely `8x480 i600`, to see whether the branch remains profitable as compressed artifact size approaches the middle of the byte budget.

## 2026-03-19 04:07 PDT — 8x480 delivers the biggest gain since 8x320 and resets the width-ladder outlook

### Why this entry exists
- `8x448 i600` was still improving, so the next single-axis remote boundary check remained the planned `8x480 i600` follow-up.
- This entry records that run because it produced another clear repo-best exact roundtrip score and showed the width branch is not flattening yet on the current DGX budget.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote repo state checked before the run:
  - branch: `research/continuous-mar18`
  - remote `HEAD`: `ead46ea2d608efb987c28a149dea1d9275b72f46`
  - remote `train_gpt.py` SHA-256 matched local `HEAD`: `11d75807f9db69f9c000c0d196afb565e5cb011ef6ed414a6f444fa6c7a43b18`
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Total wrapped wallclock for the scored run: `671.039377s`

### Attempt and result
1. `20260319T105526Z_dgx_cuda_nocompile_l8_d480_i600`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.01612407`
   - pre-quant `val_bpb`: `2.0145`
   - final val loss: `3.40414105`
   - bytes total: `8,279,424`
   - bytes model: `8,231,550`
   - wallclock: `671.039377s`
   - command shape: `8` layers, `480` model dim, `4` heads, `2` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: `8x480` was strongly worth taking; it beat `8x448` by `0.01064827` exact `val_bpb`, beat `8x416` by `0.01446386`, and set another repo-best exact score

### Artifact and scaling notes
- Compared with `8x448`, the compressed artifact grew by `952,433` bytes and wallclock grew by about `49.84s`.
- Despite that byte growth, the total artifact is still only `8,279,424` bytes, leaving `7,720,576` bytes of headroom under the `16,000,000` byte cap.
- The exact score gain from `8x448 -> 8x480` was materially larger than the prior `8x416 -> 8x448` gain, so the width ladder is still improving rather than clearly saturating on this one-shard DGX budget.

### Milestone reporting completed
- Ran:
  - `openclaw system event --text "Parameter Golf milestone: DGX 8x480 i600 reached new best exact val_bpb 2.01612407 under 8.28MB total artifact" --mode now`

### What changed in the search picture
- The current best remote width ladder at `8` layers is now:
  - `8x384 i600`: `2.03403242`
  - `8x416 i600`: `2.03058793`
  - `8x448 i600`: `2.02677234`
  - `8x480 i600`: `2.01612407`
- Width remains the dominant branch tested so far on DGX Spark, and the latest step improved enough that the practical turning point still has not appeared.

### Immediate next direction
- Keep `8x480 i600` as the new remote pivot.
- Continue one more single-axis width step, likely `8x512 i600`, to test whether the gain persists as the artifact approaches but still remains comfortably below the byte cap.

## 2026-03-19 04:21 PDT — 8x512 still improves, but only slightly; width may finally be entering a marginal regime

### Why this entry exists
- `8x480 i600` was strong enough that the cleanest next single-axis follow-up was still another width step, this time to `8x512 i600`.
- This entry records that run because it did produce a new exact roundtrip best, but by a much smaller margin than the prior step, which materially changes how the next branch should be framed.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Total wrapped wallclock for the scored run: `710.369248s`

### Attempt and result
1. `20260319T110827Z_dgx_cuda_nocompile_l8_d512_i600`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.01472144`
   - pre-quant `val_bpb`: `2.0130`
   - final val loss: `3.40177275`
   - bytes total: `9,301,730`
   - bytes model: `9,253,856`
   - wallclock: `710.369248s`
   - command shape: `8` layers, `512` model dim, `4` heads, `2` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: width still improved at `8` layers, but only narrowly; `8x512` beat `8x480` by `0.00140263` exact `val_bpb` and set another repo-best exact score

### Artifact and scaling notes
- Compared with `8x480`, the compressed artifact grew by `1,022,306` bytes and wallclock grew by about `39.33s`.
- Total artifact size is still only `9,301,730` bytes, leaving `6,698,270` bytes of headroom under the `16,000,000` byte cap.
- The gain from `8x480 -> 8x512` was much smaller than the `8x448 -> 8x480` jump, which is the clearest sign so far that the width branch may finally be approaching its practical turning point on this cheap one-shard budget.

### Milestone reporting completed
- Ran:
  - `openclaw system event --text "Parameter Golf milestone: DGX 8x512 i600 reached new best exact val_bpb 2.01472144 under 9.31MB total artifact" --mode now`

### What changed in the search picture
- The current best remote width ladder at `8` layers is now:
  - `8x416 i600`: `2.03058793`
  - `8x448 i600`: `2.02677234`
  - `8x480 i600`: `2.01612407`
  - `8x512 i600`: `2.01472144`
- Width is still the best branch tested so far, but the latest marginal gain is small enough that the next step should explicitly test whether the branch is saturating rather than assume it is still broadly open-ended.

### Immediate next direction
- Keep `8x512 i600` as the new remote pivot.
- Use one more cheap single-axis boundary check, likely `8x544 i600`, to determine whether width is still worth pushing or whether the next search budget should shift to a different parameter-allocation branch.

## 2026-03-19 04:59 PDT — 8x544 breaks below 2.01 and reopens the width ladder

### Why this entry exists
- `8x512 i600` improved only narrowly over `8x480`, so the next single-axis remote boundary check was the planned `8x544 i600` follow-up.
- This entry records that run because it answered the saturation question cleanly: width was still materially profitable on the current one-shard DGX budget.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote repo state checked before the run:
  - branch: `research/continuous-mar18`
  - remote `train_gpt.py` SHA-256 still matched local `HEAD`: `11d75807f9db69f9c000c0d196afb565e5cb011ef6ed414a6f444fa6c7a43b18`
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Total wrapped wallclock for the scored run: `793.511867s`

### Attempt and result
1. `20260319T114527Z_dgx_cuda_nocompile_l8_d544_i600`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.00436903`
   - pre-quant `val_bpb`: `2.0023`
   - final val loss: `3.38429314`
   - bytes total: `10,313,039`
   - bytes model: `10,265,165`
   - wallclock: `793.511867s`
   - command shape: `8` layers, `544` model dim, `4` heads, `2` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: `8x544` was clearly worth taking; it beat `8x512` by `0.01035241` exact `val_bpb`, beat `8x480` by `0.01175504`, and set another repo-best exact score

### Artifact and scaling notes
- Compared with `8x512`, the compressed artifact grew by `1,011,309` bytes and wallclock grew by about `83.14s`.
- Total artifact size is now `10,313,039` bytes, still leaving `5,686,961` bytes of headroom under the `16,000,000` byte cap.
- The exact score gain from `8x512 -> 8x544` was much larger than the prior `8x480 -> 8x512` gain, which means the width branch did not saturate where the previous run suggested it might.

### Milestone reporting completed
- Ran:
  - `openclaw system event --text "Parameter Golf milestone: DGX 8x544 i600 reached new best exact val_bpb 2.00436903 under 10.31MB total artifact" --mode now`

### What changed in the search picture
- The current best remote width ladder at `8` layers is now:
  - `8x448 i600`: `2.02677234`
  - `8x480 i600`: `2.01612407`
  - `8x512 i600`: `2.01472144`
  - `8x544 i600`: `2.00436903`
- Width remains the strongest architecture branch tested so far on DGX Spark, and the branch is still far from the artifact cap.

### Immediate next direction
- Keep `8x544 i600` as the new remote pivot.
- Continue one more single-axis width step, likely `8x576 i600`, to determine whether the strong `8x544` gain generalizes again before shifting budget to a different parameter-allocation axis.

## 2026-03-19 05:14 PDT — 8x576 regresses slightly; keep 8x544 as the width pivot

### Why this entry exists
- `8x544 i600` reopened the width ladder decisively, so the cleanest next single-axis follow-up was the planned `8x576 i600` check.
- This entry records that run because it marked the first slight regression after the late width rebound and therefore changes the next branch choice.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Total wrapped wallclock for the scored run: `843.691688s`

### Attempt and result
1. `20260319T120007Z_dgx_cuda_nocompile_l8_d576_i600`
   - status: `discard`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.00516912`
   - pre-quant `val_bpb`: `2.0035`
   - final val loss: `3.38564406`
   - bytes total: `11,390,950`
   - bytes model: `11,343,076`
   - wallclock: `843.691688s`
   - command shape: `8` layers, `576` model dim, `4` heads, `2` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: this width step was a clean negative result; `8x576` missed `8x544` by `0.00080009` exact `val_bpb` while costing more bytes and more wallclock

### Artifact and scaling notes
- Compared with `8x544`, the compressed artifact grew by `1,077,911` bytes and wallclock grew by about `50.18s`.
- Total artifact size remains submittable at `11,390,950` bytes, leaving `4,609,050` bytes of headroom under the `16,000,000` byte cap.
- Because both pre-quant and exact roundtrip metrics regressed slightly, this looks more like a real local turning point than a roundtrip-only compression artifact.

### What changed in the search picture
- The best current remote width frontier is now:
  - `8x512 i600`: `2.01472144`
  - `8x544 i600`: `2.00436903`
  - `8x576 i600`: `2.00516912`
- The `8`-layer width ladder appears to have reached its first local peak around `544` on this one-shard DGX budget.

### Immediate next direction
- Keep `8x544 i600` as the active remote pivot.
- Shift the next budget to a nearby parameter-allocation branch instead of more width, with the leading cheap probe now a deeper reallocation near the same scale, likely `9x512 i600`.

## 2026-03-19 05:59 PDT — 9x512 rerun completes cleanly and loses to the 8x544 pivot

### Why this entry exists
- After `8x576` became the first width-side regression, the next planned nearby reallocation branch was a deeper model at similar byte scale: `9x512 i600`.
- An initial local wrapper artifact for that branch existed, but it was incomplete and did not produce a canonical score, so a clean rerun was required before the branch could be judged.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote dataset/tokenizer state for the scored rerun:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`

### Attempts and results
1. `20260319T121534Z_dgx_cuda_nocompile_l9_d512_i600`
   - result shape: partial local wrapper artifact only
   - observed progress: reached `step 50/600`
   - canonical metric status: missing
   - conclusion: not trustworthy enough to score; I treated it as an incomplete orphaned attempt and reran the same hypothesis cleanly rather than infer from the partial log

2. `20260319T124705Z_dgx_cuda_nocompile_l9_d512_i600_rerun`
   - status: `discard`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.01603587`
   - pre-quant `val_bpb`: `2.0144`
   - final val loss: `3.40399213`
   - bytes total: `10,390,126`
   - bytes model: `10,342,252`
   - wallclock: `792.674983s`
   - command shape: `9` layers, `512` model dim, `4` heads, `2` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: reallocating budget from `8x544` into extra depth at `9x512` was a clean negative result; it missed `8x544` by `0.01166684` exact `val_bpb` while using `77,087` more total bytes and essentially the same wallclock

### Artifact and scaling notes
- The rerun remained comfortably under the artifact cap:
  - `bytes_total`: `10,390,126`
  - remaining headroom: `5,609,874`
- The pre-quant metric also regressed meaningfully relative to `8x544`:
  - `8x544 i600` pre-quant `val_bpb`: `2.0023`
  - `9x512 i600` pre-quant `val_bpb`: `2.0144`
- Because both pre-quant and exact roundtrip metrics worsened, this looks like a real architectural loss for this nearby depth reallocation rather than a compression-side artifact.

### What changed in the search picture
- The nearby `8x544` neighborhood now has two clean boundary checks against the current pivot:
  - more width: `8x576 i600` -> `2.00516912`
  - more depth with similar bytes: `9x512 i600` -> `2.01603587`
- Both branches lost to `8x544 i600` -> `2.00436903`.
- That makes `8x544 i600` the clear local winner among the immediate width-up and depth-up reallocations tested so far.

### Immediate next direction
- Keep `8x544 i600` as the active remote pivot.
- Shift the next cheap probe to a different nearby architecture axis at the same pivot rather than further width or depth, with the leading candidate now a KV-allocation check such as `8x544 i600` with `NUM_KV_HEADS=4`.

## 2026-03-19 06:16 PDT — Full KV heads at the 8x544 pivot set a new repo best

### Why this entry exists
- After both nearby reallocations around `8x544` lost cleanly (`8x576` for more width and `9x512` for more depth), the next untouched local architecture axis was attention KV allocation at the same pivot.
- This entry records that probe because it produced the best exact roundtrip score in the repo so far.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Total wrapped wallclock for the scored run: `872.776429s`

### Attempt and result
1. `20260319T130254Z_dgx_cuda_nocompile_l8_d544_kv4_i600`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `1.98897819`
   - pre-quant `val_bpb`: `1.9871`
   - final val loss: `3.35830636`
   - bytes total: `11,687,478`
   - bytes model: `11,639,604`
   - wallclock: `872.776429s`
   - command shape: `8` layers, `544` model dim, `4` heads, `4` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: restoring full KV heads at the `8x544` pivot was decisively worth it; this run beat the prior best `8x544` GQA pivot by `0.01539084` exact `val_bpb` while staying under the artifact cap by a wide margin

### Artifact and scaling notes
- Compared with the prior best `8x544 i600` GQA run (`NUM_KV_HEADS=2`):
  - exact `val_bpb`: `2.00436903 -> 1.98897819`
  - pre-quant `val_bpb`: `2.0023 -> 1.9871`
  - bytes total: `10,313,039 -> 11,687,478`
  - wallclock: `793.511867s -> 872.776429s`
- The compressed artifact remains safely submittable:
  - `bytes_total`: `11,687,478`
  - remaining headroom: `4,312,522`
- Because both pre-quant and exact roundtrip metrics improved materially, this is a real model-quality gain rather than a compression-side artifact.

### Milestone reporting completed
- Ran:
  - `openclaw system event --text "Parameter Golf milestone: DGX 8x544 KV4 i600 reached new best exact val_bpb 1.98897819 under 11.69MB total artifact" --mode now`

### What changed in the search picture
- The current best nearby remote frontier is now:
  - `8x544 i600` with `NUM_KV_HEADS=2`: `2.00436903`
  - `8x576 i600` with `NUM_KV_HEADS=2`: `2.00516912`
  - `9x512 i600` with `NUM_KV_HEADS=2`: `2.01603587`
  - `8x544 i600` with `NUM_KV_HEADS=4`: `1.98897819`
- Around the best width/depth pivot found so far, attention allocation just proved to be a much higher-leverage branch than the immediate nearby width-up or depth-up reallocations.

### Immediate next direction
- Keep `8x544 i600` with `NUM_KV_HEADS=4` as the new active remote pivot.
- Continue on nearby attention architecture at the same pivot, with the next clean single-axis probe now likely a head-count check such as `NUM_HEADS=8` while keeping `NUM_KV_HEADS=4`.

## 2026-03-19 06:03 PDT — More attention heads regress at the KV4 pivot; keep 4 heads

### Why this entry exists
- After `8x544 i600` with `NUM_KV_HEADS=4` set the new repo best, the next clean single-axis attention probe was the planned head-count check at the same width, depth, and training budget.
- This entry records that run because it cleanly separated the value of full KV allocation from the value of finer attention partitioning, and the answer was negative.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote repo state at launch:
  - branch: `research/continuous-mar18`
  - remote `train_gpt.py` SHA-256 still matched the local working copy: `11d75807f9db69f9c000c0d196afb565e5cb011ef6ed414a6f444fa6c7a43b18`
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Total wrapped wallclock for the scored run: `820.302265s`

### Attempt and result
1. `20260319T134524Z_dgx_cuda_nocompile_l8_d544_h8_kv4_i600`
   - status: `discard`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.01746457`
   - pre-quant `val_bpb`: `2.0157`
   - final val loss: `3.40640442`
   - bytes total: `10,292,655`
   - bytes model: `10,244,781`
   - wallclock: `820.302265s`
   - command shape: `8` layers, `544` model dim, `8` heads, `4` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: increasing head count from `4 -> 8` at the `8x544 KV4` pivot was a decisive regression; it lost to the current pivot by `0.02848638` exact `val_bpb` and also regressed pre-quant, so the better result came from keeping larger per-head dimensions rather than splitting attention more finely

### Artifact and scaling notes
- Compared with the current best `8x544 i600` KV4 pivot with `4` heads:
  - exact `val_bpb`: `1.98897819 -> 2.01746457`
  - pre-quant `val_bpb`: `1.9871 -> 2.0157`
  - bytes total: `11,687,478 -> 10,292,655`
  - wallclock: `872.776429s -> 820.302265s`
- The run stayed comfortably under the artifact cap:
  - `bytes_total`: `10,292,655`
  - remaining headroom: `5,707,345`
- Because both pre-quant and exact roundtrip metrics worsened materially, this is a real modeling loss rather than a compression-only trade.

### What changed in the search picture
- Around the best current remote pivot, the nearby attention-axis picture is now:
  - `8x544 i600`, `NUM_HEADS=4`, `NUM_KV_HEADS=2`: `2.00436903`
  - `8x544 i600`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`: `1.98897819`
  - `8x544 i600`, `NUM_HEADS=8`, `NUM_KV_HEADS=4`: `2.01746457`
- That means the profitable change was restoring full KV heads, not increasing the total number of attention heads.

### Immediate next direction
- Keep `8x544 i600` with `NUM_HEADS=4`, `NUM_KV_HEADS=4` as the active remote pivot.
- Shift the next cheap probe away from head-count and back to parameter allocation around the winning attention setup, with the leading candidate now `8x576 i600` while keeping `NUM_HEADS=4` and `NUM_KV_HEADS=4`.

## 2026-03-19 06:20 PDT — Width at 576 stays close on KV4 but still loses to 8x544

### Why this entry exists
- After the head-count probe showed that the `8x544 KV4` gain did not come from using more attention heads, the next highest-signal nearby architecture check was width again on top of the stronger KV allocation.
- This entry records that run because it answers whether the earlier `8x576` width regression was specific to the leaner `NUM_KV_HEADS=2` branch or whether `544` is still the local optimum once full KV heads are restored.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Total wrapped wallclock for the scored run: `925.533893s`

### Attempt and result
1. `20260319T140000Z_dgx_cuda_nocompile_l8_d576_kv4_i600`
   - status: `discard`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `1.99156207`
   - pre-quant `val_bpb`: `1.9897`
   - final val loss: `3.36266913`
   - bytes total: `12,893,076`
   - bytes model: `12,845,202`
   - wallclock: `925.533893s`
   - command shape: `8` layers, `576` model dim, `4` heads, `4` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: width on the stronger KV4 branch stayed competitive, but `8x576` still missed the `8x544 KV4` pivot by `0.00258388` exact `val_bpb`; this is a narrow negative result, not a collapse

### Artifact and scaling notes
- Compared with the current best `8x544 i600` KV4 pivot:
  - exact `val_bpb`: `1.98897819 -> 1.99156207`
  - pre-quant `val_bpb`: `1.9871 -> 1.9897`
  - bytes total: `11,687,478 -> 12,893,076`
  - wallclock: `872.776429s -> 925.533893s`
- The artifact remains submittable with room left under the cap:
  - `bytes_total`: `12,893,076`
  - remaining headroom: `3,106,924`
- Because both pre-quant and exact roundtrip metrics were slightly worse, the miss appears to be a real small-model-quality loss rather than a compression artifact.

### What changed in the search picture
- The width picture around the best KV4 attention allocation is now:
  - `8x544 i600`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`: `1.98897819`
  - `8x576 i600`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`: `1.99156207`
- That means the local optimum on the tested width ladder still appears to sit around `544`, but only narrowly once full KV heads are enabled.
- Combined with the `NUM_HEADS=8` regression, the current best neighborhood is now tightly constrained around the original `8x544`, `4`-head, `4`-KV configuration.

### Immediate next direction
- Keep `8x544 i600` with `NUM_HEADS=4`, `NUM_KV_HEADS=4` as the active remote pivot.
- Move the next cheap probe to a different nearby parameter-allocation branch rather than more width or more attention heads, with the leading candidate now a depth check such as `9x544 i600` if bytes fit cleanly under the cap.
