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

## 2026-03-19 08:04 PDT — 9x544 KV4 depth probe sets a new repo best after one wrapper-path crash

### Why this entry exists
- After `8x544 i600` with `NUM_HEADS=4` and `NUM_KV_HEADS=4` became the active remote pivot, the next highest-signal single-axis probe was extra depth at the same width and full-KV allocation.
- This entry records that branch because the clean rerun beat the prior repo best by more than the leaderboard noise threshold while remaining comfortably under the artifact cap.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote repo parity check before launch:
  - remote checkout `HEAD`: `ead46ea`
  - remote `train_gpt.py` SHA-256 matched the local working copy: `11d75807f9db69f9c000c0d196afb565e5cb011ef6ed414a6f444fa6c7a43b18`
- Remote dataset/tokenizer state for these attempts:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`

### Attempts and results
1. `20260319T144724Z_dgx_cuda_nocompile_l9_d544_kv4_i600`
   - status: `crash`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - wallclock: `0.674252s`
   - failure mode: immediate remote start failure
   - root cause: I pointed the remote command at `~/.venv-cuda/bin/python3`, but the CUDA venv on this host lives at `~/parameter-golf/.venv-cuda/bin/python3`
   - conclusion: wrapper-path mistake only; the hypothesis itself was not tested by this first attempt

2. `20260319T144745Z_dgx_cuda_nocompile_l9_d544_kv4_i600_rerun`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `1.98140198`
   - pre-quant `val_bpb`: `1.9795`
   - final val loss: `3.34551425`
   - pre-quant val loss: `3.3423`
   - bytes total: `13,073,918`
   - bytes model: `13,026,044`
   - wrapped wallclock: `977.892933s`
   - quantized roundtrip eval time: `399677ms`
   - command shape: `9` layers, `544` model dim, `4` heads, `4` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: the depth-up branch on the stronger KV4 pivot was clearly worth it; `9x544 KV4` beat the prior best `8x544 KV4` by `0.00757621` exact `val_bpb`

### Artifact and scaling notes
- Compared with the prior best `8x544 i600` KV4 pivot:
  - exact `val_bpb`: `1.98897819 -> 1.98140198`
  - pre-quant `val_bpb`: `1.9871 -> 1.9795`
  - bytes total: `11,687,478 -> 13,073,918`
  - wallclock: `872.776429s -> 977.892933s`
- The compressed artifact remains valid with room under the cap:
  - `bytes_total`: `13,073,918`
  - remaining headroom: `2,926,082`
- The run also improved the pre-quant metric, so this looks like a real modeling gain rather than a compression-only effect.

### Milestone reporting completed
- Ran:
  - `openclaw system event --text "Parameter Golf milestone: DGX 9x544 KV4 i600 reached new best exact val_bpb 1.98140198 under 13.08MB total artifact" --mode now`

### What changed in the search picture
- The best current remote frontier is now:
  - `8x544 i600`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`: `1.98897819`
  - `8x576 i600`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`: `1.99156207`
  - `9x544 i600`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`: `1.98140198`
- This is the first clean sign that the full-KV neighborhood still wanted more depth after the `8x544` width pivot, not just a better attention allocation.

### Immediate next direction
- Keep `9x544 i600` with `NUM_HEADS=4`, `NUM_KV_HEADS=4` as the new active remote pivot.
- Shift the next cheap probe to a nearby depth-vs-width reallocation at similar byte scale, with the leading candidate now `10x512 i600` while keeping `NUM_HEADS=4` and `NUM_KV_HEADS=4`.

## 2026-03-19 09:11 PDT — 10x512 KV4 depth-up reallocation is both byte-invalid and score-negative

### Why this entry exists
- After `9x544 i600` with `NUM_HEADS=4` and `NUM_KV_HEADS=4` became the active remote pivot, the planned next single-axis reallocation was `10x512 i600` with the same attention setup.
- This entry records that run because it cleanly answers the deeper-narrower question near the current frontier: this branch missed on both exact score and artifact bytes.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed during the run: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote dataset/tokenizer state for this run:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`
- Wrapped wallclock for the scored run: `2130.390722s`
- Remote train-time-only log at the end of step `600`: `172622ms`
- Final roundtrip eval time: `390326ms`
- Remote contention note:
  - another GPU process remained resident on the DGX box for the full run, using about `10.7 GiB`
  - this made the end-to-end wrapped wallclock much worse than earlier isolated DGX runs even though step time during training stayed stable around `287.7ms`

### Attempt and result
1. `20260319T153530Z_dgx_cuda_nocompile_l10_d512_kv4_i600`
   - status: `invalid`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.10053703`
   - pre-quant `val_bpb`: `2.1000`
   - final val loss: `3.54666879`
   - pre-quant val loss: `3.5458`
   - bytes total: `16,154,480`
   - bytes model: `16,106,606`
   - wrapped wallclock: `2130.390722s`
   - command shape: `10` layers, `512` model dim, `4` heads, `4` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: the deeper-narrower reallocation clearly lost; it missed the artifact cap by `154,480` bytes and also regressed exact roundtrip score versus the current `9x544 KV4` pivot

### Artifact and scaling notes
- Compared with the current best `9x544 i600` KV4 pivot:
  - exact `val_bpb`: `1.98140198 -> 2.10053703`
  - pre-quant `val_bpb`: `1.9795 -> 2.1000`
  - bytes total: `13,073,918 -> 16,154,480`
  - wrapped wallclock: `977.892933s -> 2130.390722s`
- The run is not challenge-valid:
  - cap: `16,000,000`
  - observed total: `16,154,480`
  - overflow: `154,480`
- Because both pre-quant and exact post-roundtrip metrics regressed materially, this was not a near-miss caused only by compression.

### Process note discovered during this run
- The local wrapper row used the correct local `run_id`, but the remote command exported `RUN_ID=$RUN_ID` inside a single-quoted SSH string, which meant the remote shell received `RUN_ID=` and wrote the sidecar log to `logs/.txt`.
- This did not invalidate the scored result because the canonical metric lines still reached the wrapped local log and `results/results.tsv`, but future remote commands should pass the intended run id explicitly rather than exporting an empty one.

### What changed in the search picture
- The current nearby frontier now looks like:
  - `9x544 i600`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`: `1.98140198`, `13,073,918` bytes
  - `10x512 i600`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`: `2.10053703`, `16,154,480` bytes, invalid
- This is a decisive negative result:
  - moving one step deeper while shrinking width to `512` is worse than holding at `9x544`
  - the active local optimum in this neighborhood still appears to prefer the `9x544 KV4` allocation over this deeper-narrower trade

### Immediate next direction
- Keep `9x544 i600` with `NUM_HEADS=4`, `NUM_KV_HEADS=4` as the active remote pivot.
- Move the next probe back to width at the same `9`-layer full-KV depth, with the leading candidate now `9x576 i600` if it remains under the cap.

## 2026-03-19 10:04 PDT — 9x576 KV4 stays valid but loses to 9x544 after one interrupted partial attempt

### Why this entry exists
- After `10x512 i600` with `NUM_HEADS=4` and `NUM_KV_HEADS=4` proved that a deeper-narrower reallocation was both byte-invalid and score-negative, the next clean single-axis check was width-up at the same `9`-layer full-KV depth.
- This entry records both the first interrupted `9x576` attempt and the clean rerun because together they answer the branch question: the model remains challenge-valid at `9x576 KV4`, but the score does not beat the current `9x544 KV4` pivot.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed during the scored rerun: `NVIDIA GB10`
- Remote execution mode for the scored rerun: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Local branch / ledger state during the scored rerun:
  - branch: `research/continuous-mar18`
  - local commit recorded by the wrapper: `d956db10af33979a59206678a9de40ea6678cecc`
- Remote repo parity note:
  - the DGX checkout itself still sat at older git `HEAD` `ead46ea`
  - remote `train_gpt.py` SHA-256 still matched the local working copy: `11d75807f9db69f9c000c0d196afb565e5cb011ef6ed414a6f444fa6c7a43b18`
- Remote dataset/tokenizer state for these attempts:
  - tokenizer: `~/parameter-golf/data/tokenizers/fineweb_1024_bpe.model`
  - train shards present: `1`
  - validation split: full `fineweb_val_*`

### Attempts and results
1. `20260319T161306Z_dgx_cuda_nocompile_l9_d576_kv4_i600`
   - status: interrupted partial / unscored
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - observed progress: completed warmup through `warmup_step:20/20`, then stopped without reaching logged train steps, artifact lines, or final exact roundtrip metrics
   - local artifacts written: `.meta` plus a partial wrapped log only; no `.json` summary and no `results/results.tsv` row
   - conclusion: the hypothesis was not actually answered by this first attempt and should not be treated as comparable

2. `20260319T164651Z_dgx_cuda_nocompile_l9_d576_kv4_i600_rerun`
   - status: `discard`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `1.98837620`
   - pre-quant `val_bpb`: `1.9866`
   - final val loss: `3.35728992`
   - pre-quant val loss: `3.3542`
   - bytes total: `14,441,568`
   - bytes model: `14,393,694`
   - wrapped wallclock: `1048.734371s`
   - train-time-only log at the end of step `600`: `175016ms`
   - final roundtrip eval time: `429170ms`
   - command shape: `9` layers, `576` model dim, `4` heads, `4` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: width-up at `9` layers stayed cleanly submittable but lost to the active `9x544 KV4` pivot by `0.00697422` exact `val_bpb`, so the winning neighborhood still prefers `544` width at this depth

### Artifact and scaling notes
- Compared with the current best `9x544 i600` KV4 pivot:
  - exact `val_bpb`: `1.98140198 -> 1.98837620`
  - pre-quant `val_bpb`: `1.9795 -> 1.9866`
  - bytes total: `13,073,918 -> 14,441,568`
  - wrapped wallclock: `977.892933s -> 1048.734371s`
- The rerun remains challenge-valid:
  - `bytes_total`: `14,441,568`
  - remaining headroom: `1,558,432`
- Because both pre-quant and exact post-roundtrip metrics worsened, this is a real quality regression rather than a compression-only trade.

### What changed in the search picture
- The nearby full-KV `9`-layer frontier now looks like:
  - `9x544 i600`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`: `1.98140198`, `13,073,918` bytes
  - `9x576 i600`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`: `1.98837620`, `14,441,568` bytes
- Combined with the earlier `10x512` miss, this means both immediate reallocations around the current pivot lost:
  - deeper-narrower (`10x512`) was invalid and much worse
  - wider-same-depth (`9x576`) was valid but still worse
- That makes `9x544 KV4 i600` the clearest local optimum tested so far in this neighborhood.

### Immediate next direction
- Keep `9x544 i600` with `NUM_HEADS=4`, `NUM_KV_HEADS=4` as the active remote pivot.
- Shift the next probe away from the immediate width/depth reallocations around `9x544`, with the best next branch now likely a cheap optimization or parameter-allocation change that preserves the winning shape rather than moving farther up the current width ladder.

## 2026-03-19 10:07 PDT — In-progress launch: 9x560 KV4 fine-grained width probe

### Why this entry exists
- `9x576 KV4` stayed valid but lost narrowly enough that the current local optimum might still sit between `544` and `576`.
- This note records the next live attempt before it finishes so the durable journal preserves the active hypothesis even if the session is interrupted mid-run.

### Attempt launched
1. `20260319T170634Z_dgx_cuda_nocompile_l9_d560_kv4_i600`
   - status: in progress at the time of this entry
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - local wrapper commit at launch: `4973508884bea4236d7acfd221f22760ce9ba10d`
   - hypothesis: after `9x576 KV4` proved too wide but stayed close, a finer width increase from `544 -> 560` at the same `9`-layer `4`-head `4`-KV budget will locate a better local optimum and beat the current `9x544 KV4` exact `val_bpb`
   - command shape: `9` layers, `560` model dim, `4` heads, `4` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - early live signal: launch succeeded cleanly and early step time was back in the expected remote regime around `291ms`

### Immediate next direction
- Let `20260319T170634Z_dgx_cuda_nocompile_l9_d560_kv4_i600` finish and treat its exact final roundtrip `val_bpb` as canonical.
- If it loses to `9x544 KV4`, keep the frontier at `9x544` and shift the next probe off the immediate width axis.

## 2026-03-19 10:36 PDT — Backfilled the interrupted 9x560 KV4 attempt and launched a clean rerun

### Why this entry exists
- The prior `9x560 KV4` attempt never reached a canonical final metric and also never wrote a TSV row, so the durable ledger had a gap.
- This entry records the recovery work before rerunning the same single-axis hypothesis cleanly.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote hardware state checked before rerun: `dgx-spark` host `spark-6cb3`, GPU `NVIDIA GB10`
- Observed DGX contention at check time:
  - one unrelated resident `/usr/bin/python` process was still holding about `10.7 GiB`
  - the interrupted `9x560` training process itself was no longer running

### Recovery work completed
1. `20260319T170634Z_dgx_cuda_nocompile_l9_d560_kv4_i600`
   - status after recovery: `invalid`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - logged progress recovered: through `step 250/600`
   - parsed train-time-only wallclock from the partial log: `72.937s`
   - failure shape: wrapped local log and remote sidecar both stopped at `step 250` with no artifact-size lines and no `final_int8_zlib_roundtrip_exact`
   - ledger repair: appended a backfilled `results/results.tsv` row marked `invalid` because the canonical exact metric is missing
   - note: the wrapper never captured an exit code for this interrupted attempt, so only the partial log itself is durable

### Rerun launched
1. `20260319T1736xxZ_dgx_cuda_nocompile_l9_d560_kv4_i600_rerun`
   - status: launched after the ledger repair; result pending at the time of this entry
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - hypothesis: `9x560 KV4` may still beat `9x544 KV4` even though `9x576 KV4` lost, so the interrupted first attempt should be rerun before abandoning the fine-grained width probe
   - process fix applied in the rerun command: the remote shell now receives the intended `RUN_ID` explicitly instead of depending on the earlier brittle inline expansion pattern

### Immediate next direction
- Let the clean `9x560 KV4` rerun finish and score it canonically.
- Keep `9x544 KV4` as the active frontier unless the rerun actually beats `1.98140198`.

## 2026-03-19 11:55 PDT — Clean 9x560 KV4 rerun loses decisively; shift off the immediate width axis

### Why this entry exists
- The earlier `9x560 KV4` attempt was interrupted before canonical scoring, so the branch question remained open.
- This entry records the clean rerun result and closes that question: the fine-grained width-up from `544 -> 560` is not the winning local move around the current `9x544 KV4` frontier.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed during the rerun: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote contention note during the rerun:
  - the same unrelated `/usr/bin/python` process remained resident at about `10.7 GiB`
  - despite that contention, the rerun completed cleanly and produced a trustworthy canonical score

### Attempt and result
1. `20260319T173752Z_dgx_cuda_nocompile_l9_d560_kv4_i600_rerun`
   - status: `discard`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `1.99840220`
   - pre-quant `val_bpb`: `1.9964`
   - final val loss: `3.37421841`
   - pre-quant val loss: `3.3709`
   - bytes total: `13,774,425`
   - bytes model: `13,726,551`
   - wrapped wallclock: `1051.916175s`
   - train-time-only log at step `600`: `174869ms`
   - final roundtrip eval time: `431576ms`
   - command shape: `9` layers, `560` model dim, `4` heads, `4` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - note on continuity: this is the actual clean rerun corresponding to the prior placeholder launch note; the real rerun id was `20260319T173752Z_dgx_cuda_nocompile_l9_d560_kv4_i600_rerun`
   - conclusion: the fine-grained width increase lost cleanly on both pre-quant and exact post-roundtrip metrics

### Artifact and frontier notes
- Compared with the active `9x544 KV4` pivot:
  - exact `val_bpb`: `1.98140198 -> 1.99840220`
  - pre-quant `val_bpb`: `1.9795 -> 1.9964`
  - bytes total: `13,073,918 -> 13,774,425`
  - wrapped wallclock: `977.892933s -> 1051.916175s`
- The nearby width neighborhood at `9` layers is now strongly bounded:
  - `9x544 KV4`: `1.98140198`
  - `9x560 KV4`: `1.99840220`
  - `9x576 KV4`: `1.98837620`
- This makes the current conclusion straightforward:
  - `9x544 KV4 i600` remains the best tested point in the immediate width neighborhood
  - the next useful branch should move away from nearby width changes and onto a different parameter-allocation axis

### Immediate next direction
- Keep `9x544 KV4 i600` as the active remote frontier.
- Shift the next probe to a non-width parameter-allocation change at the same winning shape, with the leading candidate now `TIE_EMBEDDINGS=0` on `9x544 KV4 i600`.

## 2026-03-19 12:14 PDT — Untied `lm_head` at 9x544 KV4 stays valid but does not beat tied embeddings

### Why this entry exists
- After the nearby `9`-layer width checks (`560` and `576`) both lost to `9x544 KV4`, the next clean parameter-allocation branch was to untie the output head while keeping the winning depth/width/attention shape fixed.
- This entry records that result and closes the branch: on this budget, the tied-embedding configuration still wins.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed during the run: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Run-specific control choice:
  - set `TIE_EMBEDDINGS=0`
  - pinned `EMBED_LR=0.05` so the probe would not also inherit the much larger untied-token default LR

### Attempt and result
1. `20260319T175710Z_dgx_cuda_nocompile_l9_d544_kv4_untied_i600`
   - status: `discard`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `1.98789991`
   - pre-quant `val_bpb`: `1.9864`
   - final val loss: `3.35648573`
   - pre-quant val loss: `3.3540`
   - bytes total: `13,591,716`
   - bytes model: `13,543,842`
   - wrapped wallclock: `1065.280780s`
   - train-time-only log at step `600`: `167403ms`
   - final roundtrip eval time: `400470ms`
   - command shape: `9` layers, `544` model dim, `4` heads, `4` KV heads, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard, `TIE_EMBEDDINGS=0`, `EMBED_LR=0.05`
   - conclusion: the untied-head branch stayed challenge-valid and even finished with slightly fewer compressed bytes than tied `9x544`, but it still regressed on both pre-quant and exact roundtrip metrics

### Artifact and frontier notes
- Compared with the active tied `9x544 KV4` pivot:
  - exact `val_bpb`: `1.98140198 -> 1.98789991`
  - pre-quant `val_bpb`: `1.9795 -> 1.9864`
  - bytes total: `13,073,918 -> 13,591,716`
  - wrapped wallclock: `977.892933s -> 1065.280780s`
- The run remained comfortably under the artifact cap:
  - `bytes_total`: `13,591,716`
  - remaining headroom: `2,408,284`
- Combined with the finished width probes, the current frontier picture is now:
  - `9x544 KV4` tied: `1.98140198`
  - `9x544 KV4` untied head: `1.98789991`
  - `9x560 KV4`: `1.99840220`
  - `9x576 KV4`: `1.98837620`
- This means the current best local solution remains the original tied `9x544 KV4` shape; neither nearby width changes nor the untied-output allocation improved it.

### Immediate next direction
- Keep `9x544 KV4 i600` with tied embeddings as the active remote frontier.
- Shift the next probe to another architecture axis that preserves the winning parameter budget but changes attention partitioning, with the leading candidate now a lower head-count check such as `NUM_HEADS=2` and `NUM_KV_HEADS=2` at the same `9x544 i600` shape.

## 2026-03-19 11:42 PDT — Lowering 9x544 attention partitioning to 2 heads crashes immediately on the GB10 flash-attention path

### Why this entry exists
- The current journaled next direction was to test whether the `9x544 KV4` frontier prefers larger per-head dimensions over the current `4`-head split.
- This entry records that the first clean `2`-head probe did not produce a comparable score because it failed immediately at attention execution time.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed during launch: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Wrapped wallclock before failure: `4.998494s`

### Attempt and result
1. `20260319T184158Z_dgx_cuda_nocompile_l9_d544_h2_kv2_i600`
   - status: `crash`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - command shape: `9` layers, `544` model dim, `2` heads, `2` KV heads, tied embeddings, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - observed model params before failure: `21,886,226`
   - failure point: first warmup forward pass, before `warmup_step:1/20`
   - canonical score: unavailable
   - root error from remote log: `RuntimeError: Invalid backend` at `F.scaled_dot_product_attention(...)`
   - conclusion: the GB10 remote path with the current trainer's hard-enabled flash SDP backend does not support this `head_dim=272` attention shape, so the hypothesis was not answered

### Search implications
- This is not evidence that `2` heads are bad in-model; it is a backend-compatibility failure in the current remote execution regime.
- Because `train_gpt.py` currently hard-enables flash SDP and disables math/mem-efficient fallbacks, this exact low-head-count branch is blocked unless the trainer is changed.
- To preserve throughput and avoid editing the core trainer mid-branch, the next probe should stay on a backend-compatible attention-allocation change at the same winning shape.

### Immediate next direction
- Keep tied `9x544 KV4 i600` as the active remote frontier.
- Shift the next single-axis probe to a backend-compatible KV-allocation test such as `NUM_HEADS=4`, `NUM_KV_HEADS=2` at the same `9x544 i600` budget.

## 2026-03-19 11:58 PDT — Reducing 9x544 from full KV to modest GQA loses cleanly despite saving bytes and wallclock

### Why this entry exists
- After the `2`-head branch crashed on the GB10 flash-attention backend, the next backend-compatible attention-allocation question was whether the current `9x544` frontier was overpaying for fully independent K/V projections.
- This entry records the answer: at fixed `9x544`, `600` steps, and tied embeddings, reducing `NUM_KV_HEADS` from `4` to `2` is a clear regression.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed during the run: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Wrapped wallclock: `893.685453s`
- Train-time-only log at step `600`: `157483ms`
- Final roundtrip eval time: `361974ms`

### Attempt and result
1. `20260319T184323Z_dgx_cuda_nocompile_l9_d544_h4_kv2_i600`
   - status: `discard`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.00748725`
   - pre-quant `val_bpb`: `2.0057`
   - final val loss: `3.38955813`
   - pre-quant val loss: `3.3865`
   - bytes total: `11,539,263`
   - bytes model: `11,491,389`
   - observed model params: `19,222,820`
   - command shape: `9` layers, `544` model dim, `4` heads, `2` KV heads, tied embeddings, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: modest GQA is materially worse than the full-KV frontier at the same width/depth budget

### Frontier comparison
- Compared with the active tied `9x544` full-KV pivot (`NUM_HEADS=4`, `NUM_KV_HEADS=4`):
  - exact `val_bpb`: `1.98140198 -> 2.00748725`
  - pre-quant `val_bpb`: `1.9795 -> 2.0057`
  - bytes total: `13,073,918 -> 11,539,263`
  - wrapped wallclock: `977.892933s -> 893.685453s`
- So this branch bought:
  - `1,534,655` bytes of artifact headroom
  - about `84.2s` of wrapped wallclock savings
- But it paid for that with a large quality regression on both pre-quant and exact post-roundtrip metrics.

### What changed in the search picture
- Near the current frontier, attention allocation now looks much clearer:
  - `9x544`, `4` heads, `4` KV heads: `1.98140198`
  - `9x544`, `4` heads, `2` KV heads: `2.00748725`
  - `9x544`, `2` heads, `2` KV heads: backend crash before scoring
- This strongly supports keeping full KV at the active `9x544` pivot unless a future trainer change enables a fair low-head-count comparison.

### Immediate next direction
- Keep tied `9x544`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`, `i600` as the active remote frontier.
- Shift the next one-axis probe away from KV sharing and toward another full-KV-compatible parameter-allocation decision, with MLP allocation now a plausible next branch because the current pivot still has about `2.93 MB` of artifact headroom.

## 2026-03-19 12:16 PDT — Narrowing the full-KV frontier from 9x544 to 9x528 also loses, tightening the local optimum

### Why this entry exists
- After `9x560 KV4` and `9x576 KV4` both lost on the wide side, and `9x544 h4 kv2` lost on the KV-sharing side, the remaining immediate width question was whether the current full-KV pivot was slightly too wide.
- This entry records that a modest width decrease to `528` also loses cleanly, so the current local full-KV optimum is now much more tightly bounded around `9x544`.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed during the run: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Wrapped wallclock: `982.607123s`
- Train-time-only log at step `600`: `167651ms`
- Final roundtrip eval time: `400795ms`

### Attempt and result
1. `20260319T190003Z_dgx_cuda_nocompile_l9_d528_kv4_i600`
   - status: `discard`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.00800576`
   - pre-quant `val_bpb`: `2.0062`
   - final val loss: `3.39043361`
   - pre-quant val loss: `3.3874`
   - bytes total: `12,414,318`
   - bytes model: `12,366,444`
   - observed model params: `20,634,276`
   - command shape: `9` layers, `528` model dim, `4` heads, `4` KV heads, tied embeddings, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: a small width decrease does not recover quality; it remains clearly behind the `9x544` full-KV frontier on both pre-quant and exact post-roundtrip metrics

### Frontier comparison
- Compared with the active tied `9x544` full-KV pivot:
  - exact `val_bpb`: `1.98140198 -> 2.00800576`
  - pre-quant `val_bpb`: `1.9795 -> 2.0062`
  - bytes total: `13,073,918 -> 12,414,318`
  - wrapped wallclock: `977.892933s -> 982.607123s`
- Relative to the current pivot, `9x528 KV4` saved only `659,600` total bytes while regressing by `0.02660378` exact `val_bpb`.

### What changed in the search picture
- The immediate full-KV width neighborhood at `9` layers now looks like:
  - `9x528 KV4`: `2.00800576`
  - `9x544 KV4`: `1.98140198`
  - `9x560 KV4`: `1.99840220`
  - `9x576 KV4`: `1.98837620`
- Combined with the nearby attention-allocation results:
  - `9x544 h4 kv2`: `2.00748725`
  - `9x544 h2 kv2`: backend crash before scoring
- This makes the current conclusion straightforward:
  - `9x544`, `4` heads, `4` KV heads, tied embeddings remains the best tested point in the immediate local neighborhood
  - the next useful branch should move away from nearby width/KV reallocations and toward a different full-KV-compatible allocation or optimization axis

### Immediate next direction
- Keep tied `9x544`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`, `i600` as the active remote frontier.
- Shift the next probe to a different full-KV-compatible branch, with MLP allocation or another byte-aware reallocation now more justified than more nearby width/KV probing.

## 2026-03-19 13:19 PDT — Increasing 9x544 full-KV MLP width to `MLP_MULT=3` stays byte-valid but regresses badly

### Why this entry exists
- After bounding the immediate `9x544 KV4` neighborhood on width, KV sharing, and tied-vs-untied output allocation, the next single-axis full-KV branch was MLP allocation.
- This entry records the first MLP-up probe and closes that direction at the current frontier: adding more feedforward width at fixed depth/width/attention budget did not help.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed during the run: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Wrapped wallclock: `1861.251850s`
- Train-time-only log at step `600`: `305955ms`
- Quantized roundtrip eval time: `771013ms`
- Remote contention note during the run:
  - unrelated GPU jobs remained present on the box throughout the run
  - this made the end-to-end wallclock much worse than the active frontier despite a still-stable training loop

### Attempt and result
1. `20260319T194728Z_dgx_cuda_nocompile_l9_d544_kv4_mlp3_i600`
   - status: `discard`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `1.99324713`
   - pre-quant `val_bpb`: `1.9915`
   - final val loss: `3.36551428`
   - pre-quant val loss: `3.3625`
   - bytes total: `15,905,946`
   - bytes model: `15,858,072`
   - observed model params: `27,213,092`
   - command shape: `9` layers, `544` model dim, `4` heads, `4` KV heads, tied embeddings, `MLP_MULT=3`, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: the larger MLP remained under the `16,000,000`-byte cap, but it regressed materially on both pre-quant and exact roundtrip metrics while consuming almost all remaining artifact headroom

### Frontier comparison
- Compared with the active tied `9x544`, `4` heads, `4` KV heads, `MLP_MULT=2` pivot:
  - exact `val_bpb`: `1.98140198 -> 1.99324713`
  - pre-quant `val_bpb`: `1.9795 -> 1.9915`
  - bytes total: `13,073,918 -> 15,905,946`
  - wrapped wallclock: `977.892933s -> 1861.251850s`
- The MLP-up branch answered the cap question cleanly:
  - it did **not** invalidate on bytes
  - but it left only `94,054` bytes of artifact headroom, which is not enough to justify the score regression

### Process note
- The remote sidecar path bug recurred on this launch: the remote trainer again wrote to `logs/.txt` because the SSH command still passed `RUN_ID=$RUN_ID` for remote-shell expansion rather than injecting the concrete local run id before SSH.
- The canonical score is still trustworthy because the wrapped local harness captured the full final exact metric and appended the row to `results/results.tsv`.
- Future remote launches should expand `RUN_ID` locally before invoking SSH so the remote sidecar log path stays stable.

### What changed in the search picture
- Near the current frontier, the tested MLP-up branch is now bounded:
  - `9x544 KV4`, `MLP_MULT=2`: `1.98140198`
  - `9x544 KV4`, `MLP_MULT=3`: `1.99324713`
- Combined with the nearby negative width/KV/untied checks, this reinforces that the current `9x544 KV4` tied pivot is already close to the best use of its present parameter budget.

### Immediate next direction
- Keep tied `9x544`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`, `MLP_MULT=2`, `i600` as the active remote frontier.
- Shift the next single-axis branch to a contrasting MLP reallocation, with `MLP_MULT=1` now the cleanest remaining test in this local neighborhood.

## 2026-03-19 13:43 PDT — Reducing 9x544 full-KV MLP width to `MLP_MULT=1` is cheaper but still loses

### Why this entry exists
- After the `MLP_MULT=3` probe showed that adding more feedforward width near the current `9x544 KV4` frontier hurt both score and byte headroom, the natural contrasting test was the opposite MLP reallocation.
- This entry records that result and closes the immediate MLP-allocation branch around the active frontier: both larger and smaller MLPs lose to the default `MLP_MULT=2` setting.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed during the run: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Wrapped wallclock: the harness completed normally and appended the scored row to `results/results.tsv`
- Train-time-only log at step `600`: `230186ms`
- Quantized roundtrip eval time: `528426ms`
- Process note:
  - the remote `RUN_ID` propagation was fixed for this launch, and the sidecar log correctly wrote to `logs/20260319T201947Z_dgx_cuda_nocompile_l9_d544_kv4_mlp1_i600.txt`

### Attempt and result
1. `20260319T201947Z_dgx_cuda_nocompile_l9_d544_kv4_mlp1_i600`
   - status: `discard`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `1.99395404`
   - pre-quant `val_bpb`: `1.9919`
   - final val loss: `3.36670788`
   - pre-quant val loss: `3.3633`
   - bytes total: `10,117,202`
   - bytes model: `10,069,328`
   - observed model params: `16,559,396`
   - command shape: `9` layers, `544` model dim, `4` heads, `4` KV heads, tied embeddings, `MLP_MULT=1`, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: the smaller MLP bought large byte headroom and much faster runtime, but it still regressed on both pre-quant and exact roundtrip metrics versus the active frontier

### Frontier comparison
- Compared with the active tied `9x544`, `4` heads, `4` KV heads, `MLP_MULT=2` pivot:
  - exact `val_bpb`: `1.98140198 -> 1.99395404`
  - pre-quant `val_bpb`: `1.9795 -> 1.9919`
  - bytes total: `13,073,918 -> 10,117,202`
  - train-time-only runtime: `167651ms -> 230186ms` is not directly comparable against the earlier frontier logs because the DGX box remained contended across runs, but the smaller MLP clearly trained and evaluated faster than the `MLP_MULT=3` probe
- Relative to the `MLP_MULT=3` branch:
  - exact `val_bpb`: `1.99324713 -> 1.99395404`
  - bytes total: `15,905,946 -> 10,117,202`
- So the local MLP-allocation picture is now unambiguous:
  - `MLP_MULT=2` is best
  - `MLP_MULT=3` loses while nearly exhausting the byte cap
  - `MLP_MULT=1` also loses despite saving almost `3 MB` versus the frontier

### What changed in the search picture
- The immediate full-KV `9x544` local neighborhood is now strongly bounded across several axes:
  - width down: `9x528 KV4` -> `2.00800576`
  - width up: `9x560 KV4` -> `1.99840220`, `9x576 KV4` -> `1.98837620`
  - KV sharing down: `9x544 h4 kv2` -> `2.00748725`
  - untied output head: `9x544 KV4 untied` -> `1.98789991`
  - MLP down: `9x544 KV4 mlp1` -> `1.99395404`
  - MLP up: `9x544 KV4 mlp3` -> `1.99324713`
- That means the current tied `9x544`, `4` heads, `4` KV heads, `MLP_MULT=2`, `i600` point remains the best tested allocation in its local neighborhood.

### Immediate next direction
- Keep tied `9x544`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`, `MLP_MULT=2`, `i600` as the active remote frontier.
- Move the next branch away from small local allocation tweaks around this point and toward a broader architecture or optimization change, since the nearby width/KV/tie/MLP neighborhood is now substantially mapped.

## 2026-03-19 14:41 PDT — A byte-safe deeper/narrower full-KV reallocation (`10x480`) loses cleanly to the tied `9x544 KV4` frontier

### Why this entry exists
- After the immediate `9x544 KV4` local neighborhood had been bounded on width, KV sharing, tied-vs-untied output allocation, and MLP width, the next broader architecture question was whether the frontier still wanted more depth if width was reduced enough to avoid the `10x512 KV4` byte failure.
- This entry records both the first failed launch of that hypothesis and the valid rerun that answered it.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed during the run: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Wrapped wallclock for the scored rerun: `1394.813439s`
- Train-time-only runtime at step `600`: `240629ms`
- Quantized roundtrip eval time from the final exact log: `573764ms`
- Remote contention observed throughout the rerun:
  - unrelated GPU processes remained resident on the same GB10 during training and roundtrip evaluation
  - the remote process stayed CPU-active for a long post-training tail before emitting the final roundtrip lines

### Attempts and results
1. `20260319T211609Z_dgx_cuda_nocompile_l10_d480_kv4_i600`
   - status: `crash`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - wrapped wallclock: `0.678742s`
   - failure mode: immediate remote shell launch bug before training started
   - root cause: I incorrectly prefixed the remote executable with `export RUN_ID=...`, so the remote shell treated the python path and torchrun flags as invalid identifiers
   - conclusion: command-construction error only; hypothesis was not tested by this first attempt

2. `20260319T211631Z_dgx_cuda_nocompile_l10_d480_kv4_i600_rerun`
   - status: `discard`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `2.00835696`
   - pre-quant `val_bpb`: `2.0070`
   - exact final val loss: `3.39102660`
   - pre-quant val loss: `3.3887`
   - bytes total: `11,615,270`
   - bytes model: `11,567,396`
   - observed model params: `18,945,160`
   - command shape: `10` layers, `480` model dim, `4` heads, `4` KV heads, tied embeddings, `MLP_MULT=2`, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: the deeper/narrower reallocation remained comfortably byte-valid, but it lost clearly on both pre-quant and exact roundtrip metrics versus the active `9x544 KV4` frontier

### Frontier comparison
- Compared with the active tied `9x544`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`, `MLP_MULT=2`, `i600` pivot:
  - exact `val_bpb`: `1.98140198 -> 2.00835696`
  - pre-quant `val_bpb`: `1.9795 -> 2.0070`
  - bytes total: `13,073,918 -> 11,615,270`
  - wrapped wallclock: `977.892933s -> 1394.813439s`
- So the `10x480` branch bought about `1,458,648` bytes of artifact headroom relative to the frontier, but it still regressed by `0.02695498` exact `val_bpb`.
- Relative to the earlier invalid `10x512 KV4` boundary check:
  - the width reduction did fix the cap issue cleanly
  - but the resulting deeper/narrower shape remained decisively behind the current `9x544 KV4` frontier on score

### Process notes
- The rerun fixed the earlier remote launch bug by passing `RUN_ID` inline as a normal environment prefix rather than via a malformed `export ... executable` pattern.
- The remote sidecar log path was correct on the rerun: `logs/20260319T211631Z_dgx_cuda_nocompile_l10_d480_kv4_i600_rerun.txt`
- The final roundtrip phase was unusually long under contention, but it completed and produced canonical exact metric lines, so the scored result is trustworthy and comparable.

### What changed in the search picture
- The broader depth-vs-width reallocation branch around the current full-KV frontier is now more clearly bounded:
  - `9x544 KV4`: `1.98140198`
  - `10x512 KV4`: byte-invalid and score-negative at `2.10053703`
  - `10x480 KV4`: byte-valid but still score-negative at `2.00835696`
- That means the current evidence does not support spending more budget on this specific deeper/narrower full-KV family.
- Combined with the earlier local width/KV/tie/MLP probes, the active best tested point remains tied `9x544`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`, `MLP_MULT=2`, `i600`.

### Immediate next direction
- Keep tied `9x544`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`, `MLP_MULT=2`, `i600` as the active remote frontier.
- Move the next probe to a genuinely different branch rather than another nearby deeper/narrower full-KV variant; the highest-signal candidates now are a broader optimization change on the active frontier or a more distinct architecture change than the `10x512 -> 10x480` family.

## 2026-03-19 15:34 PDT — Reducing the active `9x544 KV4` frontier to `TRAIN_SEQ_LEN=512` sets a new repo best exact roundtrip score

### Why this entry exists
- After the immediate `9x544 KV4` neighborhood had already been bounded on width, depth-width reallocation, KV sharing, tied-vs-untied output allocation, and MLP width, the next higher-signal single-axis branch was a broader optimization/eval-regime change rather than another nearby architecture tweak.
- This entry records the first remote sequence-length probe at the active frontier, and it answered that branch decisively: shorter training sequences improved the exact canonical score enough to become the new best run in the repo.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed during the run: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Remote checkout `HEAD`: `ead46ea`
- Local `train_gpt.py` SHA-256: `11d75807f9db69f9c000c0d196afb565e5cb011ef6ed414a6f444fa6c7a43b18`
- Remote `train_gpt.py` SHA-256 matched local: `11d75807f9db69f9c000c0d196afb565e5cb011ef6ed414a6f444fa6c7a43b18`
- Wrapped wallclock: `1609.862912s`
- Train-time-only runtime at step `600`: `291522ms`
- Quantized roundtrip eval time from the final exact log: `589685ms`
- Remote contention observed during the run:
  - unrelated GPU jobs remained resident on the same GB10 throughout training and evaluation
  - the post-training validation and roundtrip tail was much longer than the `TRAIN_SEQ_LEN=1024` frontier under that contention

### Attempt and result
1. `20260319T220618Z_dgx_cuda_nocompile_l9_d544_kv4_seq512_i600`
   - status: `keep`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `1.96725810`
   - pre-quant `val_bpb`: `1.9655`
   - exact final val loss: `3.32163289`
   - pre-quant val loss: `3.3186`
   - bytes total: `13,106,456`
   - bytes model: `13,058,582`
   - observed model params: `21,886,244`
   - command shape: `9` layers, `544` model dim, `4` heads, `4` KV heads, tied embeddings, `MLP_MULT=2`, `TRAIN_SEQ_LEN=512`, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: reducing `TRAIN_SEQ_LEN` from `1024` to `512` at the active `9x544 KV4` frontier improved both pre-quant and exact post-roundtrip quality enough to become the new best completed result while staying comfortably under the byte cap

### Frontier comparison
- Compared with the prior active tied `9x544`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`, `MLP_MULT=2`, `TRAIN_SEQ_LEN=1024`, `i600` frontier:
  - exact `val_bpb`: `1.98140198 -> 1.96725810`
  - pre-quant `val_bpb`: `1.9795 -> 1.9655`
  - exact score gain: `0.01414388`
  - bytes total: `13,073,918 -> 13,106,456`
  - wrapped wallclock: `977.892933s -> 1609.862912s`
- So this branch bought a real quality win for only `32,538` extra artifact bytes, but it paid heavily in runtime:
  - train-time-only runtime grew from `167029ms` to `291522ms`
  - final roundtrip eval time grew from `399677ms` to `589685ms`

### What changed in the search picture
- The active best tested remote frontier is now:
  - `9x544`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`, `MLP_MULT=2`, `TRAIN_SEQ_LEN=512`, `i600` -> `1.96725810`
  - prior `TRAIN_SEQ_LEN=1024` version of the same shape -> `1.98140198`
- This means the next serious search branch should treat sequence length as a real lever rather than a bookkeeping detail in this one-shard remote regime.
- The score gain is large enough to keep, but the throughput penalty is also large enough that the next follow-up should not blindly keep shortening sequence length; it should test whether some intermediate sequence length or adjacent regime change can preserve most of the gain without the same evaluation-time blowup.

### Immediate next direction
- Keep tied `9x544`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`, `MLP_MULT=2`, `TRAIN_SEQ_LEN=512`, `i600` as the new active remote frontier.
- The next highest-signal single-axis follow-up is another sequence-length regime probe that trades off score versus throughput, rather than returning to the already-bounded local width/KV/MLP neighborhood.

## 2026-03-19 16:06 PDT — Hanson clarified the main objective: beat the README Naive Baseline first

### Why this entry exists
- Hanson explicitly redirected the search objective in Telegram: stop treating the current repo-best score as the finish line and prioritize beating the README `Naive Baseline` at exact final `val_bpb = 1.2244`.
- This means the project should no longer optimize primarily for small local frontier improvements unless those branches plausibly move the search toward that global target.

### Objective change
- New primary target: beat `1.2244` exact final `val_bpb` from the README leaderboard entry:
  - `Naive Baseline`
  - score: `1.2244`
  - README row identifies it as `9layer 512dim 1024vocab TiedEmbeddings 4 KV heads`
- Current best repo result is still far above that target:
  - active best remote run: `20260319T220618Z_dgx_cuda_nocompile_l9_d544_kv4_seq512_i600`
  - exact final `val_bpb = 1.96725810`
- So the remaining gap to beat the README baseline is still very large, and the search should act accordingly.

### Practical implication for the research loop
- Branch selection should now favor higher-upside changes with a plausible path toward the README baseline rather than narrow local-neighborhood probes that only shave a few thousandths off a score still far above `1.2244`.
- This likely shifts the next search budget toward more global levers (data/training regime, tokenizer/compression/trainer behavior, or broader architecture changes) instead of only continuing tiny frontier-adjacent tweaks.

## 2026-03-19 16:20 PDT — Baseline record is fully inspectable; the main gap is training regime, not hidden methodology

### What was checked
- README leaderboard entry for `Naive Baseline` (`1.2244`)
- `records/track_10min_16mb/2026-03-17_NaiveBaseline/README.md`
- `records/track_10min_16mb/2026-03-17_NaiveBaseline/submission.json`
- `records/track_10min_16mb/2026-03-17_NaiveBaseline/train.log`
- `records/track_10min_16mb/2026-03-17_NaiveBaseline/train_gpt.py`

### Key conclusion
- The baseline does have code and methodology, and it is not a black box.
- The bigger issue is that the baseline's training regime is massively stronger than the current one-GPU DGX proxy lane.

### Baseline methodology extracted
- Layout: `VOCAB_SIZE=1024 NUM_LAYERS=9 MODEL_DIM=512 NUM_HEADS=8 NUM_KV_HEADS=4 MLP_MULT=2`
- Tied embeddings: `TIE_EMBEDDINGS=1`
- Tied embedding LR: `TIED_EMBED_LR=0.05`
- Train batch: `TRAIN_BATCH_TOKENS=524288`
- Train sequence length: `TRAIN_SEQ_LEN=1024`
- Hardware: `8xH100`
- Time budget: `MAX_WALLCLOCK_SECONDS=600`
- It reached `13780` steps before wallclock stop and saw `7,224,688,640` train tokens
- Final exact canonical score: `1.22436570`

### Code comparison to current repo
- The baseline record includes a full `train_gpt.py` snapshot.
- Compared with the current repo `train_gpt.py`, the diff is very small.
- Main functional difference observed:
  - baseline hard-enables `torch.compile`
  - current repo added `DISABLE_COMPILE` logic to support the GB10 / current remote lane
- So there is no hidden baseline code trick of comparable size to explain the entire score gap.

### Search implication
- Current best remote repo score is still `1.96725810`, which is far from `1.2244`.
- That gap is too large to plausibly close through tiny local-neighborhood tweaks alone.
- To beat the baseline, the search should explicitly learn from the baseline regime and then either:
  - reproduce a closer approximation of its throughput/optimization conditions on stronger hardware, or
  - find a qualitatively better training/tokenizer/compression strategy with enough upside to overcome the huge token-throughput gap.

## 2026-03-19 16:23 PDT — `TRAIN_SEQ_LEN=256` slightly improves pre-quant quality but loses to `seq512` on exact roundtrip while cutting wallclock sharply

### Why this entry exists
- After `TRAIN_SEQ_LEN=512` produced the current best exact canonical score, the next single-axis follow-up was to test whether the sequence-length branch still improved when shortened further.
- This entry records that `seq256` outcome and closes the immediate "keep shrinking sequence length" question for the current `9x544 KV4` frontier.

### Hardware and runtime used for this update
- Local orchestration hardware: local operator terminal in the repo root
- Remote training hardware: `dgx-spark` host `spark-6cb3`
- Remote GPU observed during the run: `NVIDIA GB10`
- Remote execution mode: `DISABLE_COMPILE=1` with `~/parameter-golf/.venv-cuda/bin/python3 -m torch.distributed.run --standalone --nproc_per_node=1 train_gpt.py`
- Wrapped wallclock: `966.387311s`
- Train-time-only runtime at step `600`: `165999ms`
- Quantized roundtrip eval time from the final exact log: `394044ms`
- Remote repo state note before launch:
  - attempted to fast-forward `~/parameter-golf` to `origin/research/continuous-mar18`
  - pull was blocked because remote `train_gpt.py` was locally modified relative to the stale remote checkout at `ead46ea`
  - verified by SHA-256 that the remote `train_gpt.py` already matched the current local committed trainer exactly (`11d75807f9db69f9c000c0d196afb565e5cb011ef6ed414a6f444fa6c7a43b18`)
  - so I did not force-reset the remote checkout; I launched the run against the matching remote trainer as-is

### Attempt and result
1. `20260319T230654Z_dgx_cuda_nocompile_l9_d544_kv4_seq256_i600`
   - status: `discard`
   - hardware: DGX Spark GB10 with `DISABLE_COMPILE=1`
   - exact final `val_bpb`: `1.96640037`
   - pre-quant `val_bpb`: `1.9643`
   - exact final val loss: `3.32018465`
   - pre-quant val loss: `3.3166`
   - bytes total: `13,162,082`
   - bytes model: `13,114,208`
   - observed model params: `21,886,244`
   - command shape: `9` layers, `544` model dim, `4` heads, `4` KV heads, tied embeddings, `MLP_MULT=2`, `TRAIN_SEQ_LEN=256`, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
   - conclusion: shortening from `seq512` to `seq256` improved the pre-quant metric slightly, but the exact final roundtrip metric regressed enough that `seq512` remains the canonical best

### Frontier comparison
- Compared with the active exact frontier `9x544`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`, `MLP_MULT=2`, `TRAIN_SEQ_LEN=512`, `i600`:
  - exact `val_bpb`: `1.96725810 -> 1.96640037` is false; the correct ordering is `1.96640037` is numerically worse than `1.96725810` only if lower-is-better is ignored, so use the canonical comparison directly:
  - exact final comparison: `seq512` remains best at `1.96725810` versus `seq256` at `1.96640037`? this requires care because lower is better, so `1.96640037` is actually lower than `1.96725810`

## 2026-03-19 16:24 PDT — Correction: `seq256` is the new exact best; previous entry misread the sign of the metric

### Why this correction is needed
- The immediately preceding entry copied the raw numbers correctly but described the exact-score ordering incorrectly.
- `val_bpb` is lower-is-better, so `1.96640037` beats `1.96725810`.

### Correct frontier comparison
- Active prior exact frontier:
  - `9x544`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`, `MLP_MULT=2`, `TRAIN_SEQ_LEN=512`, `i600` -> `1.96725810`
- New exact best from the follow-up run:
  - `9x544`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`, `MLP_MULT=2`, `TRAIN_SEQ_LEN=256`, `i600` -> `1.96640037`
- Exact score gain: `0.00085773`
- Pre-quant score gain: `1.9655 -> 1.9643`
- Bytes total: `13,106,456 -> 13,162,082`
- Wrapped wallclock: `1609.862912s -> 966.387311s`
- Train-time-only runtime: `291522ms -> 165999ms`
- Final roundtrip eval time: `589685ms -> 394044ms`

### Correct conclusion
- `TRAIN_SEQ_LEN=256` is a valid new repo best on the canonical exact roundtrip metric.
- The gain is modest, but it is real and came with a materially better runtime profile on the DGX Spark proxy lane.
- This means the short-sequence branch has not yet turned over:
  - `TRAIN_SEQ_LEN=1024` -> `1.98140198`
  - `TRAIN_SEQ_LEN=512` -> `1.96725810`
  - `TRAIN_SEQ_LEN=256` -> `1.96640037`

### Immediate next direction
- Promote `9x544`, `NUM_HEADS=4`, `NUM_KV_HEADS=4`, `MLP_MULT=2`, `TRAIN_SEQ_LEN=256`, `i600` as the active exact frontier.
- Shift the next probe away from sequence length itself and back toward a higher-upside architecture or training-regime branch from this improved short-sequence pivot.

## 2026-03-19 16:26 PDT — Started the next DGX Spark follow-up: baseline-like `8`-head attention on the new `seq256` frontier

### Why this entry exists
- The `seq256` result became the new exact frontier, so the next branch should move back to architecture rather than shrinking sequence length again immediately.
- The chosen follow-up is a head-partition probe with a clearer connection to the README baseline configuration.

### Launch details
- Run id: `20260319T232605Z_dgx_cuda_nocompile_l9_d544_h8_kv4_seq256_i600`
- Hypothesis: after `TRAIN_SEQ_LEN=256` set a new exact frontier on `9x544 KV4`, increasing `NUM_HEADS` from `4` to `8` while keeping `NUM_KV_HEADS=4` fixed will improve exact final `val_bpb` if the short-sequence regime benefits from a more baseline-like attention partition at the same parameter budget
- Hardware: DGX Spark host `spark-6cb3`, GPU `NVIDIA GB10`
- Execution mode: `DISABLE_COMPILE=1`
- Command shape: `9` layers, `544` model dim, `8` heads, `4` KV heads, tied embeddings, `MLP_MULT=2`, `TRAIN_SEQ_LEN=256`, `600` iterations, `8192` train tokens, `32768` val batch, `1` train shard
- Early launch signal from the live log:
  - startup completed cleanly
  - attention mode logged as `gqa num_heads:8 num_kv_heads:4`
  - observed model params at launch: `19,222,856`
  - early step time at `step 10`: about `264ms`, slightly faster than the `4`-head `seq256` frontier launch

### Status
- Result pending; the canonical score has not been emitted yet at the time of this journal append.

## 2026-03-19 16:25 PDT — Hanson directed the next serious compute test toward RunPod

### Why this entry exists
- After comparing the current proxy runs against the official README baseline, Hanson explicitly asked whether the remaining deficit might be mostly a hardware/throughput problem and directed the search to try RunPod in that case.

### Directional decision
- Treat RunPod as the next serious compute lane to test rather than only a backup behind DGX Spark.
- The immediate question to answer is whether stronger or more baseline-like remote hardware/setup closes a meaningful share of the remaining gap to `1.2244`.

### Current access status at the time of this entry
- The previously saved direct SSH endpoint for the old RunPod pod (`root@194.26.196.175 -p 46268`) refused connections.
- Browser-based RunPod access is still reachable; the login flow was opened successfully and reached the Google account chooser for Hanson's Berkeley account.
- So the current blocker is not conceptual permission but recovering or provisioning a live pod/session behind valid RunPod auth.

## 2026-03-19 18:18 PDT — RunPod template selected; friend's existing pod marked off-limits

### Directional decision
- Hanson explicitly said not to use the existing visible RunPod pod because it belongs to his friend.
- Off-limits pod:
  - name: `erised-htmla-mg`
  - id: `j0xh44q6dlphc6`
- Intended starting point for RunPod work instead:
  - `https://console.runpod.io/hub/template/parameter-golf?id=y5cejece4j`

### What was verified
- The linked RunPod Hub template page loaded successfully.
- Template name: `Parameter Golf`
- Image: `runpod/parameter-golf:latest`
- Template docs confirm it is a pre-built environment for the OpenAI Parameter Golf challenge with Python 3.12, PyTorch 2.9.1 (CUDA 12.8), and preinstalled dependencies.
- Exposed ports shown on the template page include:
  - `22/TCP` for SSH
  - `8888/HTTP` for Jupyter Lab
  - `3000/HTTP` free for custom use

### Immediate implication
- Future RunPod provisioning for this project should start from the Hub template, not by reusing the visible existing pod.

## 2026-03-19 18:25 PDT — Fresh RunPod H100 pod deployed and bootstrap started

### Provisioning result
- A fresh RunPod pod was successfully deployed from the Hub template:
  - template: `Parameter Golf`
  - template id: `y5cejece4j`
  - image: `runpod/parameter-golf:latest`
- Off-limits friend's pod was intentionally not used:
  - `erised-htmla-mg` / `j0xh44q6dlphc6`
- New pod created:
  - name: `imaginative_tan_coyote`
  - id: `f5fbuhtz75bb5u`
  - compute: `H100 SXM x1`
  - cost: `$2.70/hr`
  - direct TCP SSH: `ssh root@64.247.201.34 -p 14882 -i ~/.ssh/id_ed25519`

### Environment validation
- SSH access succeeded.
- GPU check passed:
  - `torch 2.9.1+cu128`
  - CUDA available: `True`
  - device count: `1`
  - GPU: `NVIDIA H100 80GB HBM3`
- The template provided the CUDA/PyTorch environment but not a populated git checkout or cached challenge data by default.

### Repo/bootstrap actions
- Cloned `https://github.com/Hilo-Hilo/parameter-golf.git` into `/workspace/parameter-golf`
- Checked out branch `research/continuous-mar18`
- Verified repo HEAD on pod: `52476a0` (`Record RunPod template steering`)
- Started challenge-data bootstrap on the H100 pod:
  - command: `python3 data/cached_challenge_fineweb.py --variant sp1024 --train-shards 8`
- This begins fetching the published cached FineWeb/tokenizer assets needed for a first remote run.

### Immediate implication
- RunPod is no longer blocked at auth/provisioning.
- The project now has a live H100 lane with working SSH and an in-progress data bootstrap.

## 2026-03-19 18:32 PDT — First detached RunPod H100 smoke run launched successfully

### Why this entry exists
- The first direct SSH-launched smoke on RunPod failed for an infrastructure reason: `torchrun` received a `SIGHUP` when the SSH PTY closed.
- To make RunPod usable for unattended work, remote runs need to be launched under a detached remote supervisor rather than directly under the login shell.

### Infrastructure fix / approach change
- Switched the remote launch pattern to use a detached `tmux` session on the RunPod pod.
- Remote session name: `pg-smoke`
- This keeps the training process alive even if the controlling SSH session exits.

### Attempt launched
- Pod: `imaginative_tan_coyote` / `f5fbuhtz75bb5u`
- Hardware: `RunPod H100 SXM x1`
- Repo path on pod: `/workspace/parameter-golf`
- Branch on pod: `research/continuous-mar18`
- Data state before launch: cached FineWeb `sp1024` assets downloaded with `--train-shards 8`
- Launch mode: detached remote `tmux`
- Command launched:
  - `scripts/run_experiment.sh --name runpod_h100_1gpu_smoke_tmux --track runpod-smoke --trainer train_gpt.py --notes "Fresh RunPod H100 template smoke with 1 GPU, cached sp1024 data, detached tmux launcher" -- env MAX_WALLCLOCK_SECONDS=60 VAL_LOSS_EVERY=200 torchrun --standalone --nproc_per_node=1 train_gpt.py`

### Live run state shortly after launch
- Log path: `logs/experiments/20260320T013234Z_runpod_h100_1gpu_smoke_tmux.log`
- Config confirmed from log:
  - tokenizer: `./data/tokenizers/fineweb_1024_bpe.model`
  - train shards: `8`
  - validation tokens: `62021632`
  - model params: `17,059,912`
  - heads / KV heads: `8 / 4`
  - train batch tokens: `524288`
  - train sequence length: `1024`
  - `torch_compile: enabled`
  - wallclock cap: `60s`
- Live progress observed:
  - warmup reached `20/20`
  - `torchrun` and `train_gpt.py` remained alive under tmux after SSH exit

### Immediate implication
- The fresh RunPod H100 lane is now doing real training work, not just provisioning.
- The next useful checkpoint is the first completed smoke result (or crash signature) from this detached run.

## 2026-03-19 18:57 PDT — Real H100 RunPod training run active; pg-worker still unclassified

### Live RunPod H100 status
- The earlier statement that `imaginative_tan_coyote` was idle became stale.
- It is now actively training a real 10-minute run on the fresh H100 pod.
- Active run observed on pod:
  - pod: `imaginative_tan_coyote` / `f5fbuhtz75bb5u`
  - hardware: `H100 SXM x1`
  - run name: `runpod_h100_1gpu_seq512`
  - launcher: `scripts/run_experiment.sh`
  - trainer: `torchrun --standalone --nproc_per_node=1 train_gpt.py`
  - config branch observed in log: `TRAIN_SEQ_LEN=512`, `TRAIN_BATCH_TOKENS=524288`, `MAX_WALLCLOCK_SECONDS=600`, `torch_compile: enabled`
- Live progress observed during SSH check:
  - active GPU python process using about `11926 MiB`
  - log had already reached `step:600/20000`

### Why it previously looked idle
- The first H100 run was only a 60-second smoke meant to validate the pod/template/data path and detached launch behavior.
- That smoke completed successfully and exited, so the pod looked idle afterwards.
- A later real run is now active, which is why the RunPod UI shows high GPU utilization again.

### pg-worker classification status
- `pg-worker` / `qaw9q0vzajnffu` still has not been SSH-inspected.
- Current visible facts only:
  - GPU: `RTX 3090 x1`
  - cost: `$0.22/hr`
  - disk shown around `78%`
- It may be killable technically, but it is still an unknown pod from an ownership/workload perspective, so it should not be killed blindly until it is classified.

## 2026-03-20 02:13 PDT — RunPod H100 full-data baseline and seq_len ablation executed and logged

### Why this update
- Prior local RunPod dataset bootstrap used only 8 shards, which produced very poor scores.
- Continued to run the remote lane on full cached FineWeb and completed `scripts/run_experiment.sh`-wrapped experiments to produce durable result rows and run metadata.

### What changed in the workflow
- Ran `python3 data/cached_challenge_fineweb.py --variant sp1024 --train-shards 80` on RunPod H100 (`imaginative_tan_coyote`/`f5fbuhtz75bb5u`) to restore full training coverage before scoring.
- Confirmed dataset status on the pod before training:
  - `fineweb10B_sp1024` train shards: `80`
  - val shards: `1`
- Launched and completed a full baseline-style run (no periodic validation) with 60-minute wallclock-equivalent settings:
  - command: `scripts/run_experiment.sh --name runpod_h100_1gpu_smoke_full --track runpod_h100_1gpu --status keep --notes "full-data baseline-style sanity run (no periodic val)" -- torchrun --standalone --nproc_per_node=1 train_gpt.py`
  - overrides: `DATA_PATH=./data/datasets/fineweb10B_sp1024`, `TOKENIZER_PATH=./data/tokenizers/fineweb_1024_bpe.model`, `VOCAB_SIZE=1024`, `MAX_WALLCLOCK_SECONDS=600`, `VAL_LOSS_EVERY=0`, `ITERATIONS=20000`, `TRAIN_BATCH_TOKENS=524288`, `TRAIN_SEQ_LEN=1024`
- Ran a one-hypothesis ablation (`TRAIN_SEQ_LEN=512`) with identical optimizer/model settings and same wallclock cap via:
  - command: `scripts/run_experiment.sh --name runpod_h100_1gpu_seq512 --track runpod_h100_1gpu --status keep --notes "single hypothesis: halve seq_len to double effective step count under same token budget" -- torchrun --standalone --nproc_per_node=1 train_gpt.py`
  - same dataset/tokenizer overrides and training hyperparameters unless noted above.

### Results
- `runpod_h100_1gpu_smoke_full`
  - track: `runpod_h100_1gpu`
  - wallclock: `600`s cap
  - `step_stop`: `1137`
  - `process wallclock`: `671.497968`s
  - `pre_quant_val_bpb`: `1.3432`
  - `exact_final_val_bpb`: `1.3447463`
  - bytes (total/code/model): `12782885` / `47874` / `12735011`
  - status: `keep`
  - notes: `full-data baseline-style sanity run (no periodic val)`
  - hardware: `RunPod H100 1x` (`64.247.201.34:14882`, `/workspace/parameter-golf`, commit `52476a0`)
- `runpod_h100_1gpu_seq512`
  - track: `runpod_h100_1gpu`
  - wallclock: `600`s cap
  - `step_stop`: `1161`
  - `process wallclock`: `700.96245`s
  - `pre_quant_val_bpb`: `1.3699`
  - `exact_final_val_bpb`: `1.37133333`
  - bytes (total/code/model): `12900675` / `47874` / `12852801`
  - status: `keep`
  - notes: `single hypothesis: halve seq_len to double effective step count under same token budget`

### Outcome
- Baseline behavior improved sharply once full dataset was available; the `TRAIN_SEQ_LEN=1024` full-data run is the best scored so far in this workspace at `1.3447463` exact final `val_bpb`.
- The `TRAIN_SEQ_LEN=512` ablation was directionally useful but regressed (`1.37133333`), so the one-variable sequence-length path is currently deprioritized.
- Next hypothesis should prioritize quality/compute tradeoffs in model shape or optimizer scheduling rather than lowering `TRAIN_SEQ_LEN` further on this one-GPU lane.

## 2026-03-19 19:28 PDT — RunPod watchdog steered to H100 lane and pg-worker removed

### Automation update
- The Parameter Golf watchdog cron job (`0200ab09-9051-4a73-a227-cf7a8f068780`) was updated so future status turns explicitly treat RunPod as the active main execution lane.
- Repo worker prompt was also updated so the continuous loop should keep iterating on the live H100 RunPod pod `imaginative_tan_coyote` / `f5fbuhtz75bb5u` instead of drifting back to DGX-only proxy iteration when RunPod is available.
- Repo commit pushed for prompt update:
  - `231865c` — `Prioritize RunPod lane in watchdog prompt`

### Pod cleanup action
- Hanson explicitly instructed me to remove `pg-worker`.
- RunPod pod terminated/removed from the account UI:
  - pod: `pg-worker`
  - id: `qaw9q0vzajnffu`
- Friend's pod remained untouched:
  - `erised-htmla-mg` / `j0xh44q6dlphc6`

### Live training lane after cleanup
- The retained active training pod is still:
  - `imaginative_tan_coyote` / `f5fbuhtz75bb5u`
  - `H100 SXM x1`
- This pod remains the main RunPod execution lane for ongoing Parameter Golf experiments.

## 2026-03-20 02:33 PDT — 10-layer depth ablation completed on full-data RunPod H100

### Why this update
- The previous best from this session (`runpod_h100_1gpu_smoke_full`) improved over the DGX-era partial-shard state, but still left room for architectural exploration.
- This was the next one-variable test after `TRAIN_SEQ_LEN=1024` and `TRAIN_SEQ_LEN=512` branching: increase depth by one layer with fixed width and context.

### Attempt details
- Pod: `f5fbuhtz75bb5u` (`imaginative_tan_coyote`) — RunPod H100 SXM x1
- Repository path: `/workspace/parameter-golf`
- Command: `scripts/run_experiment.sh --name runpod_h100_1gpu_l10_depth --track runpod_h100_1gpu --status keep --notes "single hypothesis: +1 layer (10x512) to test depth gains under fixed token+wallclock budget" -- torchrun --standalone --nproc_per_node=1 train_gpt.py`
- Overrides: `DATA_PATH=./data/datasets/fineweb10B_sp1024`, `TOKENIZER_PATH=./data/tokenizers/fineweb_1024_bpe.model`, `VOCAB_SIZE=1024`, `MAX_WALLCLOCK_SECONDS=600`, `VAL_LOSS_EVERY=0`, `ITERATIONS=20000`, `TRAIN_BATCH_TOKENS=524288`, `TRAIN_SEQ_LEN=1024`, `NUM_LAYERS=10`
- Notable technical note: `scripts/run_experiment.sh` did not emit a `.json` summary automatically in this run on first invocation; metrics were still parsed from log and appended via direct `parse_train_log.py` replay with the same metadata to preserve durability.

### Results
- experiment_id: `20260320T022630Z_runpod_h100_1gpu_l10_depth`
- `step_stop`: `1108`
- process wallclock: `708.104481`
- `pre_quant_val_bpb`: `1.3363`
- `exact_final_val_bpb`: `1.33772384`
- bytes (total/code/model): `14094407` / `47874` / `14046533`
- model params: `18,897,488`

### Outcome
- This run improved best exact final score relative to `runpod_h100_1gpu_smoke_full` (`1.3447463` -> `1.33772384`) while staying within the 16MB cap.
- Current best remains `runpod_h100_1gpu_l10_depth` among RunPod H100 single-GPU explorations.

## 2026-03-19 19:38 PDT — Hanson raised the target to sub-1 and asked for explicit OpenAI-guideline compliance

### Directional change
- Hanson explicitly raised the optimization target from merely beating the README baseline to pushing toward **sub-1 exact final `val_bpb`**.
- Beating `1.2244` should now be treated as an intermediate checkpoint, not the final objective.

### Compliance requirement
- Hanson also explicitly asked that all project scripts adhere to official OpenAI / README challenge guidelines.
- This means the repo automation and experiment paths should preserve:
  - canonical exact roundtrip `val_bpb`
  - the `16,000,000`-byte total artifact cap
  - the published submission/evaluation spirit and constraints
  - readable, challenge-aligned script behavior rather than clever shortcuts that would risk disqualification

## 2026-03-20 02:39 PDT — 11-layer depth ablation completed on full-data RunPod H100

### Why this update
- After `10x512` improved best score, the next single-variable hypothesis was to add one more transformer block (`NUM_LAYERS=11`) while keeping token budget, sequence length, and optimizer settings fixed.

### Attempt details
- Pod: `f5fbuhtz75bb5u` (`imaginative_tan_coyote`) — RunPod H100 SXM x1
- Repository path: `/workspace/parameter-golf`
- Command: `scripts/run_experiment.sh --name runpod_h100_1gpu_l11_depth --track runpod_h100_1gpu --status keep --notes "single hypothesis: +2 layers (11x512) after 10x512 improvement" -- torchrun --standalone --nproc_per_node=1 train_gpt.py`
- Overrides: `DATA_PATH=./data/datasets/fineweb10B_sp1024`, `TOKENIZER_PATH=./data/tokenizers/fineweb_1024_bpe.model`, `VOCAB_SIZE=1024`, `MAX_WALLCLOCK_SECONDS=600`, `VAL_LOSS_EVERY=0`, `ITERATIONS=20000`, `TRAIN_BATCH_TOKENS=524288`, `TRAIN_SEQ_LEN=1024`, `NUM_LAYERS=11`

### Results
- experiment_id: `20260320T023839Z_runpod_h100_1gpu_l11_depth`
- `step_stop`: `1076`
- process wallclock: `731.579863` (reported by parse metadata)
- `pre_quant_val_bpb`: `1.3311`
- `exact_final_val_bpb`: `1.33252549`
- bytes (total/code/model): `15285856` / `47874` / `15237982`
- status: `keep`

### Outcome
- This continues the depth trajectory; `11x512` is better than 10-layer and 9-layer baselines observed so far (`1.33252549` vs `1.33772384` and `1.3447463`).
- `NUM_LAYERS=11` still improves score but remains above the README `Naive Baseline` target (`1.2244`), so next steps should focus on additional quality gains (optimizer and architecture couplings) while maintaining 16MB cap.

## 2026-03-20 02:39 PDT — 11-layer depth ablation completed on full-data RunPod H100

### Why this update
- After `10x512` improved best score, the next single-variable hypothesis was to add one more transformer block (`NUM_LAYERS=11`) while keeping token budget, sequence length, and optimizer settings fixed.

### Attempt details
- Pod: `f5fbuhtz75bb5u` (`imaginative_tan_coyote`) — RunPod H100 SXM x1
- Repository path: `/workspace/parameter-golf`
- Command: `scripts/run_experiment.sh --name runpod_h100_1gpu_l11_depth --track runpod_h100_1gpu --status keep --notes "single hypothesis: +2 layers (11x512) after 10x512 improvement" -- torchrun --standalone --nproc_per_node=1 train_gpt.py`
- Overrides: `DATA_PATH=./data/datasets/fineweb10B_sp1024`, `TOKENIZER_PATH=./data/tokenizers/fineweb_1024_bpe.model`, `VOCAB_SIZE=1024`, `MAX_WALLCLOCK_SECONDS=600`, `VAL_LOSS_EVERY=0`, `ITERATIONS=20000`, `TRAIN_BATCH_TOKENS=524288`, `TRAIN_SEQ_LEN=1024`, `NUM_LAYERS=11`

### Results
- experiment_id: `20260320T023839Z_runpod_h100_1gpu_l11_depth`
- `step_stop`: `1076`
- process wallclock: `731.579863` (reported by parse metadata)
- `pre_quant_val_bpb`: `1.3311`
- `exact_final_val_bpb`: `1.33252549`
- bytes (total/code/model): `15285856` / `47874` / `15237982`
- status: `keep`

### Outcome
- This continues the depth trajectory; `11x512` is better than 10-layer and 9-layer baselines observed so far (`1.33252549` vs `1.33772384` and `1.3447463`).
- `NUM_LAYERS=11` still improves score but remains above the README `Naive Baseline` target (`1.2244`), so next steps should focus on additional quality gains (optimizer and architecture couplings) while maintaining 16MB cap.

## 2026-03-19 20:01 PDT — Upstream sync + external-approach monitoring added to the standing workflow

### Directional change
- Hanson explicitly said to remember that side agents should be delegated to keep the repo synced with upstream and to see how other people are approaching the Parameter Golf problem.

### Workflow implication
- Treat upstream `openai/parameter-golf` sync as part of the ongoing research loop.
- Use delegated side-agent / subagent work to inspect new upstream leaderboard records, README changes, record folders, and any newly published approaches so local search can react quickly.
- The project should not rely only on internal experimentation; it should also absorb external signal from upstream progress.

## 2026-03-19 20:02 PDT — Papers + ChatGPT added as a formal optimization lane

### Directional change
- Hanson explicitly asked that the project also read/research papers and use ChatGPT to help identify optimal ways to optimize the solution.

### Workflow implication
- The Parameter Golf loop should now include a dedicated external-research lane in addition to training and upstream repo sync.
- That lane should:
  - read relevant papers / prior art
  - synthesize promising ideas that fit the official OpenAI challenge constraints
  - use ChatGPT as an explicit research/idea-generation tool rather than relying only on local reasoning

### Operational note
- At the moment this instruction was recorded, the `chatgpt.com` browser session under the OpenClaw profile was present but logged out, so ChatGPT use is conceptually approved/required but may still need session re-auth before it becomes a live automation lane.

## 2026-03-20 02:53 PDT — 11-layer + kv-head expansion tested (invalid due 16MB cap)

### Why this update
- Previous best valid RunPod result was `runpod_h100_1gpu_l11_depth` (`1.33252549` exact final).
- One-variable follow-up was to increase `NUM_KV_HEADS` from `4` to `8` while keeping `NUM_LAYERS=11` and other defaults.

### Attempt details
- Pod: `f5fbuhtz75bb5u` (`imaginative_tan_coyote`) — RunPod H100 SXM x1
- Command: `scripts/run_experiment.sh --name runpod_h100_1gpu_l11_kv8 --track runpod_h100_1gpu --status keep --notes "single hypothesis: test 11 layers with higher KV heads (8) instead of 4" -- torchrun --standalone --nproc_per_node=1 train_gpt.py`
- Overrides: `DATA_PATH=./data/datasets/fineweb10B_sp1024`, `TOKENIZER_PATH=./data/tokenizers/fineweb_1024_bpe.model`, `VOCAB_SIZE=1024`, `MAX_WALLCLOCK_SECONDS=600`, `VAL_LOSS_EVERY=0`, `ITERATIONS=20000`, `TRAIN_BATCH_TOKENS=524288`, `TRAIN_SEQ_LEN=1024`, `NUM_LAYERS=11`, `NUM_KV_HEADS=8`

### Results
- experiment_id: `20260320T025232Z_runpod_h100_1gpu_l11_kv8`
- `step_stop`: `1070`
- process wallclock: `732.724491`
- `pre_quant_val_bpb`: `1.3291`
- `exact_final_val_bpb`: `1.33062046`
- bytes (total/code/model): `17317905` / `47874` / `17270031`
- status: `invalid` after parse due bytes_total `17317905` > `16000000`

### Outcome
- Quality improved relative to valid 11x4 run, but this architecture exceeds the 16MB submission cap and is therefore not eligible as-is.
- The valid frontier remains `runpod_h100_1gpu_l11_depth` at `1.33252549`.

## 2026-03-19 20:09 PDT — ChatGPT Pro / Deep Research preference recorded for Parameter Golf

### Directional preference
- Hanson explicitly said to remember to use ChatGPT Pro and Deep Research for ChatGPT-based work on this project.

### Workflow implication
- The ChatGPT research lane should default upward to Pro / Deep Research when appropriate for serious optimization research, paper synthesis, and strategy finding, instead of behaving like a basic lightweight chat lane.

## 2026-03-19 20:11 PDT — Cron-backed worker logic made explicit for future restarts

### Why this entry exists
- Hanson explicitly asked to make sure the cronjob-backed worker keeps operating via the newer multi-lane project logic, not just whatever older prompt state happened to be loaded.

### Logic now made explicit in the worker prompt
- RunPod-first execution, especially the live H100 lane when available
- sub-1 exact final `val_bpb` as the real target
- strict OpenAI / README guideline compliance
- append-only journaling + GitHub-tracked continuity
- upstream sync / external-approach monitoring
- delegated side-agent usage for external intelligence
- papers / prior-art reading
- ChatGPT Pro / Deep Research as an explicit research lane

### Implication
- If the watchdog restarts the worker later, the worker prompt itself now restates this logic directly instead of relying on scattered context only.

## 2026-03-20 03:08 PDT — 11-layer tied-embed LR increase tested (regression)

### Why this update
- After improving valid depth with `11x512`, I ran a one-variable optimizer update (`TIED_EMBED_LR=0.1`) as a quick check for additional gains.

### Attempt details
- Pod: `f5fbuhtz75bb5u` (`imaginative_tan_coyote`) — RunPod H100 SXM x1
- Command: `scripts/run_experiment.sh --name runpod_h100_1gpu_l11_tiedlr01 --track runpod_h100_1gpu --status keep --notes "single hypothesis: increase tied_embed_lr from 0.05 to 0.1 for 11-layer model" -- torchrun --standalone --nproc_per_node=1 train_gpt.py`
- Overrides: same as 11-layer baseline plus `TIED_EMBED_LR=0.1`

### Results
- experiment_id: `20260320T030632Z_runpod_h100_1gpu_l11_tiedlr01`
- `step_stop`: `1039`
- process wallclock: `680.12452`
- `pre_quant_val_bpb`: `1.3457`
- `exact_final_val_bpb`: `1.348321`
- status: `keep`

### Outcome
- This move regressed sharply relative to `l11_depth` and did not improve the frontier.
- Next optimizer sweeps should be deprioritized unless paired with other orthogonal changes, since this direction is clearly adverse.

## 2026-03-19 20:20 PDT — Cost-discipline rule added for expensive compute

### Why this entry exists
- Hanson explicitly warned not to waste resources after seeing the H100 appear low-utilization in the RunPod UI.

### Clarification at the time of the warning
- The pod was not truly idle; it had an active training process and was in the early warmup/compile portion of a run.
- Active run observed:
  - `runpod_h100_1gpu_l11_untied2`
  - H100 GPU process active
  - latest visible progress: step `10/20000`

### New standing rule
- Do not leave expensive compute (especially the RunPod H100 lane) idling without useful work.
- If the pod is not actively training, evaluating, or immediately preparing the next serious experiment, either launch the next useful job promptly or shut the pod down.

## 2026-03-20 03:22 PDT — 11-layer untied embeddings run improved frontier

### Why this update
- To continue the successful depth trend while changing one variable, I tested `TIE_EMBEDDINGS=0` on `NUM_LAYERS=11` (keeping the same dataset and compute budget).

### Attempt details
- Pod: `f5fbuhtz75bb5u` (`imaginative_tan_coyote`) — RunPod H100 SXM x1
- Command: `scripts/run_experiment.sh --name runpod_h100_1gpu_l11_untied2 --track runpod_h100_1gpu --status keep --notes "single hypothesis: set TIE_EMBEDDINGS=0 on 11-layer baseline" -- torchrun --standalone --nproc_per_node=1 train_gpt.py`
- Overrides: same as baseline 11-layer run with `TIE_EMBEDDINGS=0`

### Results
- experiment_id: `20260320T031941Z_runpod_h100_1gpu_l11_untied2`
- `step_stop`: `1041`
- process wallclock: `684.790279`
- `pre_quant_val_bpb`: `1.3191`
- `exact_final_val_bpb`: `1.32061866`
- bytes (total/code/model): `15343749` / `47874` / `15295875`
- status: `keep`

### Outcome
- New best valid score in this lane: `1.32061866`, improving on prior frontier (`1.33252549`).
- `TIE_EMBEDDINGS=0` also changed optimizer defaults to `embed_lr=0.6`, `head_lr=0.008` per logged config.
- Next hypotheses should likely continue from this state (e.g., keep `TIE_EMBEDDINGS=0` and vary `MODEL_DIM`/`MLP_MULT`/small schedule tweaks) while honoring byte cap.

## 2026-03-19 20:44 PDT — Multi-cluster compute permission recorded

### Directional change
- Hanson explicitly said I can use more GPU clusters if that improves the workflow.

### Workflow implication
- The project should not stay artificially constrained to the current single-pod setup if broader compute materially improves iteration speed, search breadth, or faithfulness to the official multi-GPU challenge regime.
- RunPod H100 remains the current main lane, but stronger or additional clusters are now explicitly allowed when they are high-value.

## 2026-03-20 03:35 PDT — 11-layer untied width sweep (RunPod) and local optimum refinement

### Attempt details
- Hardware: RunPod H100 SXM x1 (`f5fbuhtz75bb5u`, image `runpod/parameter-golf:latest`, public SSH target `64.247.201.34:14882`).
- Git commit: `52476a0ef480a222be3c57025b7c53dc3da79513`.
- Branch: `research/continuous-mar18`.
- Execution path: all runs through `scripts/run_experiment.sh` with full 80-shard `fineweb10B_sp1024` data.

#### Hypothesis A (1 variable): `MODEL_DIM=520` with `NUM_LAYERS=11`, `TIE_EMBEDDINGS=0`
- Result: `crash`, exit code 1.
- Failure: `head_dim must be even for RoPE` (model width 520 is not compatible with 8 attention heads and current constraints).
- Log: `20260320T033242Z_runpod_h100_1gpu_l11_d520_untied.log`.

#### Hypothesis B (1 variable): `MODEL_DIM=496` with `NUM_LAYERS=11`, `TIE_EMBEDDINGS=0`
- Result: successful `keep`.
- `experiment_id`: `20260320T033506Z_runpod_h100_1gpu_l11_d496_untied`
- `step_stop`: `1147`
- process wallclock: `759.216223`
- `pre_quant_val_bpb`: `1.3139`
- `exact_final_val_bpb`: `1.31520169`
- `bytes_total`: `14759069`
- `bytes_code`: `47874`, `bytes_model`: `14711195`

#### Hypothesis C (1 variable): `MODEL_DIM=480` with `NUM_LAYERS=11`, `TIE_EMBEDDINGS=0`
- Result: successful `keep`.
- `experiment_id`: `20260320T034805Z_runpod_h100_1gpu_l11_d480_untied`
- `step_stop`: `1181`
- process wallclock: `759.844253`
- `pre_quant_val_bpb`: `1.3163`
- `exact_final_val_bpb`: `1.31737389`
- `bytes_total`: `14307128`
- `bytes_code`: `47874`, `bytes_model`: `14259254`

### Outcome
- New best valid run is `MODEL_DIM=496` (`exact_final_val_bpb = 1.31520169`, improved from `1.32061866`).
- Moving to `MODEL_DIM=480` on the same axis regressed.
- `MODEL_DIM=520` is invalid under this head configuration due RoPE parity.
- Next high-signal direction: keep `NUM_LAYERS=11`, `TIE_EMBEDDINGS=0` and test an orthogonal axis with minimal branch divergence (sequence length and/or KV-head allocation), not another width step.

## 2026-03-19 21:06 PDT — Parallel search explicitly authorized

### Directional change
- Hanson explicitly said I can try multiple approaches at the same time.

### Workflow implication
- The Parameter Golf loop no longer needs to enforce a strictly single-hypothesis search at all times.
- When compute and orchestration make it worthwhile, the project can run two serious approaches in parallel, especially across:
  - multiple GPU pods / clusters
  - training + upstream-intel / literature lanes
  - distinct high-value hypotheses with clear attribution

### Constraint
- Parallelism should still be disciplined: two serious threads are better than chaotic shotgun branching.

## 2026-03-20 04:13 PDT — 11-layer untied frontier confirmed; orthogonal knobs regressed

### Attempt details
- Hardware: RunPod H100 SXM x1 (`f5fbuhtz75bb5u`), branch `research/continuous-mar18`, commit `52476a0ef480a222be3c57025b7c53dc3da79513`.
- All commands executed through `scripts/run_experiment.sh` against full 80-shard `fineweb10B_sp1024` with `MAX_WALLCLOCK_SECONDS=600`.

### Orthogonal sweep results around 11-layer untied best
1. `runpod_h100_1gpu_l11_d496_u512seq`
   - Config: `NUM_LAYERS=11`, `MODEL_DIM=496`, `TRAIN_SEQ_LEN=512`, `TIE_EMBEDDINGS=0`.
   - Outcome: `keep`, `exact_final_val_bpb = 1.34816010`.
   - `bytes_total = 14818008`, `step_stop = 1133`.
   - Interpretation: worse than the same-width, seq_len-1024 baseline.

2. `runpod_h100_1gpu_l11_d496_u2kv`
   - Config: `NUM_LAYERS=11`, `MODEL_DIM=496`, `NUM_KV_HEADS=2`, `TIE_EMBEDDINGS=0`.
   - Outcome: `keep`, `exact_final_val_bpb = 1.32790001`.
   - `bytes_total = 15276523`, `step_stop = 1060`.
   - Interpretation: worse than `runpod_h100_1gpu_l11_d496_untied`.

3. `runpod_h100_1gpu_l12_d496_untied`
   - Config: `NUM_LAYERS=12`, `MODEL_DIM=496`, `TIE_EMBEDDINGS=0`.
   - Outcome: `keep`, `exact_final_val_bpb = 1.32097771`.
   - `bytes_total = 15682618`, `step_stop = 1017`.
   - Interpretation: improved over `l11_d480_untied` but worse than 11-layer width-optimized frontier.

### Current best from RunPod lane
- Best score remains `1.31520169` at `20260320T033506Z_runpod_h100_1gpu_l11_d496_untied`.
- The additional orthogonal knobs tested so far (`TRAIN_SEQ_LEN`, `NUM_KV_HEADS`, `NUM_LAYERS`) did not improve over this best.
- Next likely high-yield direction: hold `11x496` untied and test a targeted optimizer/hyper-parameter path (one at a time), or transition to 8-GPU-style configurations if accessible.

## 2026-03-20 04:39 PDT — WARMDOWN_ITERS=2400 regressed on 11x496 untied

### Hypothesis: `WARMDOWN_ITERS=2400`
- Hardware: RunPod H100 SXM x1 (`f5fbuhtz75bb5u`, image `runpod/parameter-golf:latest`, public SSH target `64.247.201.34:14882`).
- Branch: `research/continuous-mar18`.
- Git commit: `52476a0ef480a222be3c57025b7c53dc3da79513`.
- Command: `runpod_h100_1gpu_l11_d496_wd2400` via `scripts/run_experiment.sh`, `TRACK=runpod_h100_1gpu`, `MAX_WALLCLOCK_SECONDS=600`.

### Run details
- Config: `NUM_LAYERS=11`, `MODEL_DIM=496`, `TIE_EMBEDDINGS=0`, `WARMDOWN_ITERS=2400`.
- Result status: `keep`.
- Exact stop: `wallclock_cap` at `step_stop=1041`.
- `wallclock_seconds`: `709.137631`.
- `pre_quant_val_bpb`: `1.3365`.
- `exact_final_val_bpb`: `1.34058991` (worse than frontier `1.31520169`).
- `bytes_total`: `13056554`.
- Log: `20260320T043922Z_runpod_h100_1gpu_l11_d496_wd2400.log`.

### Outcome
- Interpretation: increasing warmdown from 1200/1200 baseline to 2400 did not improve frontier at this frontier point and appears to over-dampen optimization quality.
- Next immediate path (one-hypothesis at a time): keep `11x496` untied and test a single optimizer-rate adjustment path (`EMBED_LR`, `MATRIX_LR`, `SCALAR_LR`, or `HEAD_LR`) with default warmdown.

## 2026-03-19 22:00 PDT — Upstream sync refreshed; strongest visible approaches re-prioritized

### Sync status
- Refreshed local repo against `upstream/main` with a fresh fetch.
- Current divergence at check time for `research/continuous-mar18...upstream/main`:
  - local-only commits: `63`
  - upstream-only commits: `38`
- This means the local branch has current upstream refs available for inspection, but upstream has continued advancing materially.

### Most important upstream approaches right now
1. **Warmdown + smarter compression/export is the strongest visible direction**
   - `2026-03-19_WarmdownQuantization`
   - `submission.json` reports `val_bpb = 1.15744040`
   - Key ideas in the upstream record metadata:
     - train for quantizability with very long warmdown
     - sliding-window evaluation
     - fp16 tied embeddings
     - larger MLP enabled by smarter post-training quantization (`Int6 MLP3x Sliding Window`)
   - Important note: this folder's `README.md` appears stale relative to `submission.json`, so the upstream tree should be read via `submission.json` / logs, not README alone.

2. **Sliding-window exact eval remains one of the highest-confidence gains**
   - `2026-03-19_SlidingWindowEval`
   - exact `val_bpb = 1.19250007`
   - Training is nearly baseline-identical; the gain comes mostly from evaluation method:
     - overlapping windows
     - stride=64
     - richer context per scored token
   - This is still the clearest low-risk, high-value improvement path.

3. **10-layer + mixed precision export is strong and challenge-aligned**
   - `2026-03-19_10L_MixedPrecision`
   - exact `val_bpb = 1.21474500`
   - Key ideas:
     - 10 layers at dim 512
     - lower learning rates
     - middle layers compressed more aggressively (int6-like via step-4 rounding)
   - Main lesson: depth becomes more viable once artifact packing is smarter.

4. **Sliding-window + fp16 embed + 10L + Muon WD + Overtone Init is strong on the visible leaderboard**
   - `2026-03-19_SlidingWindow_FP16Emb_10L_MuonWD_OvertoneInit`
   - mean `val_bpb = 1.17475315`
   - Combines:
     - sliding-window evaluation
     - fp16 tied embeddings
     - 10 layers
     - Muon weight decay
     - overtone spectral embedding init
     - residual-mixing init tweaks

5. **LoRA TTT is interesting, but its own ablations say the easy gain is elsewhere**
   - `2026-03-17_LoRA_TTT`
   - Mean around `1.1928`
   - Upstream ablation says most of the gain comes from:
     - document-isolated evaluation
     - strided evaluation
   - The LoRA adaptation itself looks like a second-wave refinement, not the first thing to copy.

### Practical reprioritization
- Highest-value near-term work should focus on:
  1. sliding-window exact eval
  2. smarter precision-aware export/compression
  3. quantization-aware training schedules (especially warmdown / lower-LR robustness)
  4. only then further depth/shape search
- Tokenizer changes still do not look like the main public winning lever.
- The project should continue reading upstream `records/` directly instead of trusting the top-level README alone.

## 2026-03-20 04:52 PDT — EMBED_LR increase on 11x496 untied regressed but stabilized

### Hypothesis: `EMBED_LR=0.8`
- Hardware: RunPod H100 SXM x1 (`f5fbuhtz75bb5u`, image `runpod/parameter-golf:latest`, public SSH target `64.247.201.34:14882`).
- Branch: `research/continuous-mar18`.
- Git commit: `52476a0ef480a222be3c57025b7c53dc3da79513`.
- Command: `runpod_h100_1gpu_l11_d496_uembed08` via `scripts/run_experiment.sh`, `TRACK=runpod_h100_1gpu`, `MAX_WALLCLOCK_SECONDS=600`.

### Run details
- Config: `NUM_LAYERS=11`, `MODEL_DIM=496`, `TIE_EMBEDDINGS=0`, `EMBED_LR=0.8`.
- Result status: `keep`.
- Exact stop: `wallclock_cap` at `step_stop=1055`.
- `wallclock_seconds`: `708.848418`.
- `pre_quant_val_bpb`: `1.3226`.
- `exact_final_val_bpb`: `1.32399542`.
- `bytes_total`: `14591739`.
- Log: `20260320T045217Z_runpod_h100_1gpu_l11_d496_uembed08.log`.

### Outcome
- Interpretation: increasing `EMBED_LR` to `0.8` did not improve the frontier (`1.32399542` > `1.31520169`) and remained a modest regression versus best.
- Next immediate path (one-hypothesis): keep `11x496` untied and test a single opposite/related optimizer tweak such as `EMBED_LR=0.4` or `MATRIX_LR` adjustment.

## 2026-03-19 22:03 PDT — Training direction updated from upstream and upstream refresh made recurring

### Directional change
- Hanson explicitly asked to update the training direction based on the refreshed upstream findings and to remember to check upstream regularly.

### Updated priority order
- The worker should now prioritize:
  1. sliding-window exact evaluation
  2. smarter precision-aware export / compression
  3. warmdown / quantization-aware schedule work
  4. only then additional architecture sweeps unless a shape change is unusually high-value

### Ongoing workflow rule
- Upstream inspection should be recurring, not occasional.
- The project should regularly re-fetch `openai/parameter-golf`, inspect newly added/changed `records/` folders and `submission.json` files, and update search priorities when public evidence shifts.

## 2026-03-19 22:06 PDT — Direction changes now require reasons + citations in journal

### Directional change
- Hanson explicitly said to remember that every new direction/strategy change should also be recorded in `journal.md` with the reason for the change and citations/evidence when available.

### Workflow implication
- `journal.md` should not only record runs and code changes.
- It should also record strategy pivots with:
  - why the direction changed
  - what evidence motivated it
  - citations when available (upstream record, paper, benchmark, or explicit Hanson instruction)

## 2026-03-20 05:04 PDT — EMBED_LR=0.4 also regressed

### Hypothesis: `EMBED_LR=0.4`
- Hardware: RunPod H100 SXM x1 (`f5fbuhtz75bb5u`, image `runpod/parameter-golf:latest`, public SSH target `64.247.201.34:14882`).
- Branch: `research/continuous-mar18`.
- Git commit: `52476a0ef480a222be3c57025b7c53dc3da79513`.
- Command: `runpod_h100_1gpu_l11_d496_ue8_embed04` via `scripts/run_experiment.sh`, `TRACK=runpod_h100_1gpu`, `MAX_WALLCLOCK_SECONDS=600`.

### Run details
- Config: `NUM_LAYERS=11`, `MODEL_DIM=496`, `TIE_EMBEDDINGS=0`, `EMBED_LR=0.4`.
- Result status: `keep`.
- Exact stop: `wallclock_cap` at `step_stop=1042`.
- `wallclock_seconds`: `708.999606`.
- `pre_quant_val_bpb`: `1.3228`.
- `exact_final_val_bpb`: `1.32439830`.
- `bytes_total`: `14518394`.
- Log: `20260320T050420Z_runpod_h100_1gpu_l11_d496_ue8_embed04.log`.

### Outcome
- Interpretation: `EMBED_LR=0.4` did not beat baseline frontier and sits close to the 0.8 variant (`1.32439830` > `1.31520169`).
- Next immediate path (one-hypothesis): keep `11x496` untied and test `MATRIX_LR` increase/decrease (`0.05` or `0.02`) as the next likely orthogonal optimizer knob.

## 2026-03-20 05:17 PDT — MATRIX_LR=0.05 improved over previous EMBED_LR probes

### Hypothesis: `MATRIX_LR=0.05`
- Hardware: RunPod H100 SXM x1 (`f5fbuhtz75bb5u`, image `runpod/parameter-golf:latest`, public SSH target `64.247.201.34:14882`).
- Branch: `research/continuous-mar18`.
- Git commit: `52476a0ef480a222be3c57025b7c53dc3da79513`.
- Command: `runpod_h100_1gpu_l11_d496_umatrix05` via `scripts/run_experiment.sh`, `TRACK=runpod_h100_1gpu`, `MAX_WALLCLOCK_SECONDS=600`.

### Run details
- Config: `NUM_LAYERS=11`, `MODEL_DIM=496`, `TIE_EMBEDDINGS=0`, `MATRIX_LR=0.05`.
- Result status: `keep`.
- Exact stop: `wallclock_cap` at `step_stop=1069`.
- `wallclock_seconds`: `709.474112`.
- `pre_quant_val_bpb`: `1.3195`.
- `exact_final_val_bpb`: `1.32048871`.
- `bytes_total`: `15150670`.
- Log: `20260320T051705Z_runpod_h100_1gpu_l11_d496_umatrix05.log`.

### Outcome
- Interpretation: `MATRIX_LR=0.05` outperformed both `EMBED_LR` perturbations and is closer to target than previous runs, but still above frontier (`1.32048871` > `1.31520169`).
- Next immediate path (one-hypothesis): test a lower `MATRIX_LR` (`0.03`) as a follow-up on the same 11x496 untied frontier.

## 2026-03-20 05:31 PDT — MATRIX_LR=0.03 was worse

### Hypothesis: `MATRIX_LR=0.03`
- Hardware: RunPod H100 SXM x1 (`f5fbuhtz75bb5u`, image `runpod/parameter-golf:latest`, public SSH target `64.247.201.34:14882`).
- Branch: `research/continuous-mar18`.
- Git commit: `52476a0ef480a222be3c57025b7c53dc3da79513`.
- Command: `runpod_h100_1gpu_l11_d496_umatrix03` via `scripts/run_experiment.sh`, `TRACK=runpod_h100_1gpu`, `MAX_WALLCLOCK_SECONDS=600`.

### Run details
- Config: `NUM_LAYERS=11`, `MODEL_DIM=496`, `TIE_EMBEDDINGS=0`, `MATRIX_LR=0.03`.
- Result status: `keep`.
- Exact stop: `wallclock_cap` at `step_stop=1054`.
- `wallclock_seconds`: `710.630429`.
- `pre_quant_val_bpb`: `1.3250`.
- `exact_final_val_bpb`: `1.32698936`.
- `bytes_total`: `13967763`.
- Log: `20260320T053106Z_runpod_h100_1gpu_l11_d496_umatrix03.log`.

### Outcome
- Interpretation: `MATRIX_LR=0.03` degraded versus `MATRIX_LR=0.05` (`1.32698936` > `1.32048871`).
- Next immediate path: keep focused on `11x496` untied and try `HEAD_LR=0.01` as a conservative optimizer-norm tweak.

## 2026-03-20 05:43 PDT — HEAD_LR=0.01 underperforms frontier

### Hypothesis: `HEAD_LR=0.01`
- Hardware: RunPod H100 SXM x1 (`f5fbuhtz75bb5u`, image `runpod/parameter-golf:latest`, public SSH target `64.247.201.34:14882`).
- Branch: `research/continuous-mar18`.
- Git commit: `52476a0ef480a222be3c57025b7c53dc3da79513`.
- Command: `runpod_h100_1gpu_l11_d496_uhead01` via `scripts/run_experiment.sh`, `TRACK=runpod_h100_1gpu`, `MAX_WALLCLOCK_SECONDS=600`.

### Run details
- Config: `NUM_LAYERS=11`, `MODEL_DIM=496`, `TIE_EMBEDDINGS=0`, `HEAD_LR=0.01`.
- Result status: `keep`.
- Exact stop: `wallclock_cap` at `step_stop=1044`.
- `wallclock_seconds`: `708.331720`.
- `pre_quant_val_bpb`: `1.3221`.
- `exact_final_val_bpb`: `1.32345066`.
- `bytes_total`: `14568254`.
- Log: `20260320T054324Z_runpod_h100_1gpu_l11_d496_uhead01.log`.

### Outcome
- Interpretation: `HEAD_LR=0.01` is better than baseline `HEAD_LR=0.008` was unknown but above frontier (`1.32345066`), and close to `MATRIX_LR=0.05` but still above best `1.31520169`.
- Next immediate path (one-hypothesis): with `MATRIX_LR=0.05` still strongest, test whether increasing `SCALAR_LR` has similar effect before moving to larger architecture or DGX.

## 2026-03-20 06:04 PDT — RunPod SCALAR_LR=0.08 logging + next probe path

### Completed material run
- `experiment_id`: `20260320T055706Z_runpod_h100_1gpu_l11_d496_uscalar08`
- Track/hardware: `runpod_h100_1gpu`
- Commanded changes: one-axis probe from `11x496` untied baseline with `SCALAR_LR=0.08`.
- Commit: `52476a0ef480a222be3c57025b7c53dc3da79513` (same train script revision used in the active 11x496 untied branch)
- Log: `/workspace/parameter-golf/logs/experiments/20260320T055706Z_runpod_h100_1gpu_l11_d496_uscalar08.json`
- Result status: `keep`
- `step_stop`: `1041`
- `wallclock_seconds`: `600.321000`
- `pre_quant_val_bpb`: `1.3241`
- `exact_final_val_bpb`: `1.32553081`
- `bytes_total`: `14557389`
- `bytes_model`: `14509515`
- `bytes_code`: `47874`

### Outcome and interpretation
- `SCALAR_LR=0.08` stayed near the neighborhood of other scalar-rate probes but did not beat the best optimizer-rate branch (`MATRIX_LR=0.05`, `1.32048871`).
- This keeps current frontier unchanged at `1.31520169` (`11x496` untied with lower width).
- Next one-hypothesis direction: continue one-axis probing within this branch with nearby scalar learning-rate points (`SCALAR_LR=0.06`) while keeping remote H100 lane as primary.

## 2026-03-19 23:20 PDT — Landed low-hanging-fruit change: sliding-window exact eval on working branch

### Directional change
- I stopped leaving the sliding-eval work stranded in a draft worktree and landed it directly onto `research/continuous-mar18` as the first real low-hanging-fruit implementation.

### Why this changed now
- Hanson explicitly said to pick off the low-hanging fruit first and called out that I was not actually making the changes yet.
- Upstream evidence still points to sliding-window exact eval as one of the highest-confidence immediate gains.

### Evidence / citations
- Explicit Hanson steering in chat: prioritize the low-hanging fruit first.
- Upstream record citations:
  - `records/track_10min_16mb/2026-03-19_SlidingWindowEval/README.md`
  - `records/track_10min_16mb/2026-03-17_LoRA_TTT/README.md`
- Key upstream lesson: overlapping/strided exact eval gives a real gain even before changing model training.

### What was landed
- Added `EVAL_STRIDE` and `EVAL_BATCH_SEQS` controls.
- Added `GPT.forward_logits` to enable per-position scoring.
- Added `eval_val_sliding` for stride-based exact token scoring over the full validation stream.
- Preserved canonical exact final logging (`final_int8_zlib_roundtrip_exact ...`).
- Added `scripts/smoke_sliding_eval.py` as a lightweight validation script.

### Validation
- Local compile check passed for:
  - `train_gpt.py`
  - `scripts/parse_train_log.py`
  - `scripts/smoke_sliding_eval.py`
- The smoke script import path was fixed so it can be invoked cleanly from the repo.

## 2026-03-20 22:40 PDT — RunPod SCALAR_LR=0.06 directional follow-up

### Completed material run
- `experiment_id`: `20260320T061641Z_runpod_h100_1gpu_l11_d496_uscalar06c`
- Track/hardware: `runpod_h100_1gpu`
- Commanded changes: one-axis probe from `11x496` untied baseline with `SCALAR_LR=0.06`.
- Commit: `52476a0ef480a222be3c57025b7c53dc3da79513` (same train script revision as active 11x496 untied branch).
- Log: `/workspace/parameter-golf/logs/experiments/20260320T061641Z_runpod_h100_1gpu_l11_d496_uscalar06c.log`.
- Result status: `discard`.
- `step_stop`: `1051`.
- `wallclock_seconds`: `709.74503`.
- `pre_quant_val_bpb`: `1.3222`.
- `exact_final_val_bpb`: `1.32352664`.
- `bytes_total`: `14596638`.
- `bytes_model`: `14548764`.
- `bytes_code`: `47874`.

### Outcome and interpretation
- SCALAR-rate tuning remained unpromising on this branch: `SCALAR_LR=0.06` (`1.32352664`) is worse than both `SCALAR_LR=0.08` (`1.32553081`) and the optimizer-branch lead (`MATRIX_LR=0.05`, `1.32048871`).
- Corrected the earlier `uscalar08` row metadata with canonical metrics from remote JSON:
  - `ts_utc`: `2026-03-20T05:57:06Z`
  - `final_val_loss`: `2.23810325`
  - `pre_quant_val_loss`: `2.2357`
  - `wallclock_seconds`: `710.730255`
- Next one-hypothesis direction: switch away from SCALAR_LR and run a next single-axis follow-up in this branch (e.g., alternate optimizer-rate or structural change with `MATRIX`/`HEAD` next).

## 2026-03-20 23:05 PDT — RunPod MATRIX_LR=0.06 directional follow-up

### Completed material run
- `experiment_id`: `20260320T063048Z_runpod_h100_1gpu_l11_d496_umatrix06`
- Track/hardware: `runpod_h100_1gpu`
- Commanded changes: one-axis probe from `11x496` untied baseline with `MATRIX_LR=0.06`.
- Commit: `52476a0ef480a222be3c57025b7c53dc3da79513` (same train script revision as active 11x496 untied branch).
- Log: `/workspace/parameter-golf/logs/experiments/20260320T063048Z_runpod_h100_1gpu_l11_d496_umatrix06.log`.
- Result status: `discard`.
- `step_stop`: `1054`.
- `wallclock_seconds`: `709.101456`.
- `pre_quant_val_bpb`: `1.3205`.
- `exact_final_val_bpb`: `1.32140622`.
- `bytes_total`: `15596327`.
- `bytes_model`: `15548453`.
- `bytes_code`: `47874`.

### Outcome and interpretation
- `MATRIX_LR=0.06` on this branch improved materially over most scalar variants but did not beat the `MATRIX_LR=0.05` best at `1.32048871`.
- Best frontier remains `1.32048871` (`runpod_h100_1gpu_l11_d496_umatrix05`).
- Next one-hypothesis direction: test a nearby structural/optimizer axis on top of `11x496` untied, rather than widening the scalar matrix sweep.

## 2026-03-19 23:52 PDT — Landed low-hanging-fruit change: precision-aware export/compression on working branch

### Directional change
- I stopped leaving the export/compression work stranded in a draft worktree and landed it directly onto `research/continuous-mar18` as the second low-hanging-fruit implementation.

### Why this changed now
- Hanson explicitly said to pivot immediately to the low-hanging fruits.
- Fresh upstream evidence showed that export/compression is a larger lever than continuing tiny LR sweeps.

### Evidence / citations
- Explicit Hanson steering in chat: pivot immediately to the low-hanging fruits.
- Upstream record citations:
  - `records/track_10min_16mb/2026-03-19_10L_MixedPrecision/README.md`
  - `records/track_10min_16mb/2026-03-19_WarmdownQuantization/README.md`
  - `records/track_10min_16mb/2026-03-19_SlidingWindow_FP16Emb_10L_MuonWD_OvertoneInit/README.md`
- Key upstream lesson: smarter packing/precision allocation is one of the main public reasons upstream is far ahead of our vanilla int8 export path.

### What was landed
- Added export controls:
  - `FP16_TIED_EMBEDDING_EXPORT`
  - `INT4_LAYERS`
  - `INT4_STEP`
  - `VERIFY_EXPORT_ROUNDTRIP`
- Added optional fp16 passthrough for `tok_emb.weight` in the export payload.
- Added selective lower-precision snapping for chosen block layers in the compressed export path.
- Added explicit quantization config logging and optional roundtrip verification metrics.
- Preserved canonical final logging (`final_int8_zlib_roundtrip` and `final_int8_zlib_roundtrip_exact`).

### Validation
- Local compile check passed for:
  - `train_gpt.py`
  - `scripts/parse_train_log.py`
  - `scripts/smoke_sliding_eval.py`
- No live DGX process was touched.

## 2026-03-19 23:56 PDT — Immediate live pivot: stopped stale LR sweep and relaunched RunPod on low-hanging-fruit path

### Directional change
- Hanson explicitly told me to pivot immediately to the low-hanging fruits and later called out that I still had an old LR sweep running on RunPod.
- I stopped that leftover sweep and redirected the H100 onto the new low-hanging-fruit path.

### Why this changed now
- The old live job was still an 11x496 LR-sweep variant (`MATRIX_LR` / `HEAD_LR`) even after the upstream-driven reprioritization.
- That was inconsistent with the new direction and was wasting H100 attention on lower-value search.

### Evidence / citations
- Explicit Hanson steering in chat: pivot immediately to low-hanging fruits.
- Upstream evidence already logged in this journal:
  - `2026-03-19_SlidingWindowEval`
  - `2026-03-19_10L_MixedPrecision`
  - `2026-03-19_WarmdownQuantization`
- These point more strongly to eval/export/compression than to continued small LR sweeps.

### Live action taken
- Stopped the leftover RunPod LR-sweep process.
- Synced the RunPod repo checkout to the latest `research/continuous-mar18`.
- Relaunched H100 on:
  - `runpod_h100_1gpu_l11_d496_untied_slide64`
  - `EVAL_STRIDE=64`
  - `EVAL_BATCH_SEQS=64`
  - `NUM_LAYERS=11`
  - `MODEL_DIM=496`
  - `TIE_EMBEDDINGS=0`
  - `MAX_WALLCLOCK_SECONDS=600`
  - `VERIFY_EXPORT_ROUNDTRIP=1`

### Constraint
- DGX Spark was left untouched per Hanson's instruction.

## 2026-03-20 00:09 PDT — Purged stale worker/cron assumptions and replaced them with current strategy

### Why this entry exists
- Hanson explicitly asked me to make sure the cron job knows the latest direction and to purge outdated info and replace it with the new info.

### What stale assumptions were removed/replaced
- Replaced stale framing like `architecture-first` with a lower-level, current strategy emphasis.
- Replaced older cron steering that centered only on beating `1.2244` with the updated objective: design to win under official OpenAI rules, target sub-1 if possible.
- Replaced ambiguous pod state references with current truth:
  - `pg-worker` is already gone
  - the friend's pod is still off-limits
  - RunPod H100 is the active main lane
- Replaced vague continuation language with the current low-hanging-fruit priority order.

### New authoritative active order
1. sliding-window exact eval
2. smarter precision-aware export / compression
3. warmdown / quantization-aware schedules
4. only then more architecture/LR sweeps unless unusually high-value

### Evidence / citations
- Explicit Hanson steering in chat to pivot immediately to low-hanging fruits and to update the cron logic.
- Upstream evidence already cited earlier in this journal:
  - `records/track_10min_16mb/2026-03-19_SlidingWindowEval/README.md`
  - `records/track_10min_16mb/2026-03-19_10L_MixedPrecision/README.md`
  - `records/track_10min_16mb/2026-03-19_WarmdownQuantization/README.md`

## 2026-03-20 00:09 PDT — Cron instructed to read journal.md and preserve the latest pivot

### Directional change
- Hanson explicitly reminded me to make sure this low-hanging-fruit / upstream-driven pivot is recorded in `journal.md` and that the cron-backed worker explicitly reads `journal.md`.

### Why this matters
- The project has pivoted away from stale architecture/LR-first behavior toward the current higher-value order:
  1. sliding-window exact eval
  2. smarter precision-aware export / compression
  3. warmdown / quantization-aware schedules
  4. only then more architecture/LR sweeps unless clearly justified
- If the cron/worker does not explicitly read `journal.md`, it risks drifting back toward outdated assumptions after restart or prompt churn.

### Evidence / citations
- Explicit Hanson steering in chat.
- Upstream evidence already cited in earlier journal entries:
  - `records/track_10min_16mb/2026-03-19_SlidingWindowEval/README.md`
  - `records/track_10min_16mb/2026-03-19_10L_MixedPrecision/README.md`
  - `records/track_10min_16mb/2026-03-19_WarmdownQuantization/README.md`

### Operational change
- The cron-backed worker/watchdog should explicitly read `journal.md` as part of its recurring loop so the latest project pivots remain active operating context, not just historical notes.

## 2026-03-20 00:45 PDT — Landed worker dedupe/state layer to prevent repeated cron work

### Directional change
- Hanson explicitly asked how to make sure the cron job does not repeat work, then explicitly said to implement it.
- I moved the dedupe/state hardening from an isolated worktree onto the working branch once the smoke path passed.

### Why this changed now
- The previous setup had partial continuity (watchdog state, journal, results), but no dedicated authoritative dedupe/planning layer.
- That left the loop vulnerable to relaunching stale or already-completed work after restarts.

### Evidence / citations
- Explicit Hanson steering in chat: make sure the cron job does not repeat work; implement it.
- Internal repo evidence motivating the change:
  - repeated stale-logic drift after pivots
  - stale remote checkouts / repeated sweeps risk when worker restarts

### What was landed
- Added `scripts/research_state.py` as a machine-readable orchestration state layer.
- Added `automation/state/research_state.json` bootstrap/update flow.
- Wired `start_continuous_worker.sh` to bootstrap research state on launch.
- Wired `check_continuous_worker.py` to reconcile:
  - worker state
  - journal tail
  - recent `results/results.tsv`
  - active process/log info
- Added dedupe-aware `shouldRestart` handling into `watchdog_tick.py`.
- Wired `stop_continuous_worker.sh` to mark stop state in research state.
- Added `scripts/smoke_research_state.sh` as a lightweight validation path.

### Validation
- Python syntax checks passed:
  - `scripts/research_state.py`
  - `scripts/check_continuous_worker.py`
  - `scripts/watchdog_tick.py`
- Shell syntax checks passed:
  - `scripts/start_continuous_worker.sh`
  - `scripts/stop_continuous_worker.sh`
  - `scripts/smoke_research_state.sh`
- Smoke path passed:
  - `bash scripts/smoke_research_state.sh`

## 2026-03-20T07:37:04Z — RunPod exact-export verify continuation

### Run
- Maintained main lane on RunPod H100 pod `imaginative_tan_coyote` (`f5fbuhtz75bb5u`), avoiding friend-owned pod.
- Launched detached `scripts/run_experiment.sh` rerun:
  - `scripts/run_experiment.sh --name runpod_h100_1gpu_l11_d496_untied_verify3 --track runpod_h100 --trainer train_gpt.py --status keep --notes "verify-export-path: validate best frontier with verify enabled after fix (detached)" -- env NUM_LAYERS=11 MODEL_DIM=496 TIE_EMBEDDINGS=0 MAX_WALLCLOCK_SECONDS=600 VERIFY_EXPORT_ROUNDTRIP=1 EVAL_STRIDE=1024 EVAL_BATCH_SEQS=32 torchrun --standalone --nproc_per_node=1 train_gpt.py`
- This validated quant roundtrip/eval with the device-mismatch fix (commit `70e1307`) in the live export/eval path.

### Result
- Completed successfully with `exit_code=0`; parsed summary JSON recorded at `/workspace/parameter-golf/logs/experiments/20260320T073704Z_runpod_h100_1gpu_l11_d496_untied_verify3.json`.
- Final row added to `results/results.tsv`:
  - experiment: `20260320T073704Z_runpod_h100_1gpu_l11_d496_untied_verify3`
  - status: `keep`
  - `exact_final_val_bpb=1.31193434`
  - `pre_quant_val_bpb=1.3107`
  - `bytes_total=15070268`
  - `wallclock_seconds=783.016748`
  - `step_stop=1187`

### Directional impact
- Exact roundtrip export path is now end-to-end healthy again after the earlier GPU-side `VERIFY_EXPORT_ROUNDTRIP` crash.
- Result remains above 1.0, so next work should continue precision-aware compression sweeps (int4/expression-level knobs) as directed by current priority before additional shape/curve sweeps.

## 2026-03-20T07:52:33Z — Compression sweep: all-block int4_step=4 on RunPod

### Run
- Continued on primary RunPod pod `imaginative_tan_coyote` (`f5fbuhtz75bb5u`) with verify/eval path:
  - `scripts/run_experiment.sh --name runpod_h100_1gpu_l11_d496_untied_verify_int4all4 --track runpod_h100 --trainer train_gpt.py --status keep --notes "int4-compression: all 11 layers int4_step=4 fp16_tied_embedding_export=1 verify roundtrip exact" -- env NUM_LAYERS=11 MODEL_DIM=496 TIE_EMBEDDINGS=0 MAX_WALLCLOCK_SECONDS=600 VERIFY_EXPORT_ROUNDTRIP=1 FP16_TIED_EMBEDDING_EXPORT=1 INT4_LAYERS="0,1,2,3,4,5,6,7,8,9,10" INT4_STEP=4 EVAL_STRIDE=1024 EVAL_BATCH_SEQS=32 torchrun --standalone --nproc_per_node=1 train_gpt.py`

### Result
- Completed with `exit_code=0`; summary JSON at `/workspace/parameter-golf/logs/experiments/20260320T075233Z_runpod_h100_1gpu_l11_d496_untied_verify_int4all4.json`.
- Final `results/results.tsv` row:
  - experiment: `20260320T075233Z_runpod_h100_1gpu_l11_d496_untied_verify_int4all4`
  - `exact_final_val_bpb=1.32846427`
  - `pre_quant_val_bpb=1.3135`
  - `bytes_total=11419963`
  - `wallclock_seconds=776.502659`
  - `step_stop=1155`

### Learnings
- All-layer int4 at `int4_step=4` plus fp16 tied embeddings was too lossy on this lane, worse than baseline keep run with no int4 (`1.31193434`).
- Next compression hypotheses should reduce quant pressure (subset layers, lower step, alternative precision settings) before additional architecture sweeps.

## 2026-03-20T08:35:42Z — Compression refinement: int4_step=2 with sliding-window eval tuning on RunPod

### Run
- Main lane remained `imaginative_tan_coyote` (`f5fbuhtz75bb5u`) / H100 SXM x1, SSH target `64.247.201.34:14882`.
- Launched detached continuation on the same 11x496 untied frontier with stronger sliding-window controls and denser quantization:
  - `scripts/run_experiment.sh --name runpod_h100_1gpu_l11_d496_untied_verify_stride256_int4all2 --track runpod_h100 --trainer train_gpt.py --status keep --notes "int4-compression: all 11 layers int4_step=2 fp16_tied_embedding_export=1 verify exact; sliding eval stride/batch tune" --eval-stride 256 --eval-batch-seqs 32 -- env NUM_LAYERS=11 MODEL_DIM=496 TIE_EMBEDDINGS=0 MAX_WALLCLOCK_SECONDS=600 VERIFY_EXPORT_ROUNDTRIP=1 FP16_TIED_EMBEDDING_EXPORT=1 INT4_LAYERS="0,1,2,3,4,5,6,7,8,9,10" INT4_STEP=2 torchrun --standalone --nproc_per_node=1 train_gpt.py`
- Runtime artifact sync: local path copy from `/workspace/parameter-golf/logs/experiments/20260320T083542Z_runpod_h100_1gpu_l11_d496_untied_verify_stride256_int4all2.log|meta|json` to local `logs/experiments/`.

### Result
- Completed successfully with `exit_code=0` and produced:
  - `final_int8_zlib_roundtrip_exact val_bpb: 1.30962111`
  - `pre_quant_val_bpb: 1.3375` (final pre-quant check at step 1086)
  - `bytes_total: 13250579` (model 13195096 + code 55483)
  - `step_stop: 1086`
  - `wallclock_seconds: 797.572465`
- Artifact summary JSON: `results/../logs/experiments/20260320T083542Z_runpod_h100_1gpu_l11_d496_untied_verify_stride256_int4all2.json`.
- Added row to `results/results.tsv` with `track=runpod_h100`, `branch=feat/baseline-direct`, `status=keep`.
- This is the current best exact final `val_bpb` in local+remote logs since March 20 start of RunPod lane and a meaningful continuation of the eval/compression-first strategy.

### Directional impact
- The slope improved over both `int4_step=4` and untuned stride-1024 baselines, confirming that tighter sliding-window cadence (stride 256 / batch_seqs 32) plus all-block `int4_step=2` is a valid high-signal axis.
- Immediate next hypothesis: test `INT4_STEP=1` on the same topology/eval settings before broadening architecture again, since this remains a compression-focused improvement path and is materially low-cost.

## 2026-03-20T08:50:03Z — Compression frontier jump: INT4_STEP=1 with sliding-window eval

### Run
- Continued on RunPod H100 lane with immediate next low-hanging follow-up:
  - `scripts/run_experiment.sh --name runpod_h100_1gpu_l11_d496_untied_verify_stride256_int4all1 --track runpod_h100 --trainer train_gpt.py --status keep --notes "int4-compression: all 11 layers int4_step=1 fp16_tied_embedding_export=1 verify exact with stride/batch tune" --eval-stride 256 --eval-batch-seqs 32 -- env NUM_LAYERS=11 MODEL_DIM=496 TIE_EMBEDDINGS=0 MAX_WALLCLOCK_SECONDS=600 VERIFY_EXPORT_ROUNDTRIP=1 FP16_TIED_EMBEDDING_EXPORT=1 INT4_LAYERS="0,1,2,3,4,5,6,7,8,9,10" INT4_STEP=1 EVAL_STRIDE=256 EVAL_BATCH_SEQS=32 torchrun --standalone --nproc_per_node=1 train_gpt.py`
- Remote artifacts synced locally from `/workspace/parameter-golf/logs/experiments/20260320T085003Z_runpod_h100_1gpu_l11_d496_untied_verify_stride256_int4all1.{log,meta,json}`.

### Result
- Completed successfully with `exit_code=0` and pushed a keep row to local `results/results.tsv`.
- Final exact metric:
  - `exact_final_val_bpb=1.29896417` (new local best)
  - `pre_quant_val_bpb=1.3275`
  - `bytes_total=13493894`
  - `step_stop=1186`
  - `wallclock_seconds=772.590117`
- This is a material improvement over the previous best `1.30962111` and keeps us on the compression-first lane.

### Directional impact
- `INT4_STEP=1` beat `INT4_STEP=2` under the same stride/batch/eval settings, so the next follow-up should continue this compression axis:
  - test narrower quantization pressure variants (e.g., all layers `INT4_STEP=1` with `INT4_LAYERS` subsets on the same stride regime),
  - only then move to other structural hypotheses if no additional monotonic gains appear.

## 2026-03-20T09:05:23Z — Subset quantization check confirms all-layer INT4 remains strongest so far

### Run
- Kept the same 11x496 untied + sliding-window verify lane and tested first-8-layer quantization:
  - `scripts/run_experiment.sh --name runpod_h100_1gpu_l11_d496_untied_verify_stride256_int4half1 --track runpod_h100 --trainer train_gpt.py --status keep --notes "int4-compression: first 8 layers int4_step=1 fp16_tied_embedding_export=1 verify exact; sliding eval stride/batch tune" --eval-stride 256 --eval-batch-seqs 32 -- env NUM_LAYERS=11 MODEL_DIM=496 TIE_EMBEDDINGS=0 MAX_WALLCLOCK_SECONDS=600 VERIFY_EXPORT_ROUNDTRIP=1 FP16_TIED_EMBEDDING_EXPORT=1 INT4_LAYERS="0,1,2,3,4,5,6,7" INT4_STEP=1 EVAL_STRIDE=256 EVAL_BATCH_SEQS=32 torchrun --standalone --nproc_per_node=1 train_gpt.py`
- Synced the new artifacts from `/workspace/parameter-golf/logs/experiments/20260320T090523Z_runpod_h100_1gpu_l11_d496_untied_verify_stride256_int4half1.*` to local `logs/experiments`.

### Result
- Completed successfully (`exit_code=0`), `exact_final_val_bpb=1.30082265`, `status=keep`.
- `pre_quant_val_bpb=1.3292`, `bytes_total=13418850`, `step_stop=1175`, `wallclock_seconds=775.605728`.
- This is behind the all-layer `int4_step=1` frontier (`1.29896417`) and therefore should be retained for comparison but not as primary direction.

### Directional impact
- Supports the current hypothesis that this lane’s strongest compression point is at higher quantization coverage (`int4_step=1` across all layers), while limiting quantized layers reduced objective quality here.
- Next experiment should therefore revert to all-layer coverage and explore either:
  - alternative `INT4_STEP` values near 1 (e.g., 1 with different compile/eval settings),
  - warmdown/optimizer schedule interactions with the already-learned quantized frontier.

## 2026-03-20T09:18:57Z — Warmdown interaction on all-layer int4_step=1

### Run
- Ran warmdown-sweep follow-up on the current all-layer quant frontier:
  - `scripts/run_experiment.sh --name runpod_h100_1gpu_l11_d496_untied_verify_stride256_int4all1wd2400 --track runpod_h100 --trainer train_gpt.py --status keep --notes "int4-compression: all 11 layers int4_step=1 with warmdown 2400" --eval-stride 256 --eval-batch-seqs 32 -- env NUM_LAYERS=11 MODEL_DIM=496 TIE_EMBEDDINGS=0 MAX_WALLCLOCK_SECONDS=600 WARMDOWN_ITERS=2400 VERIFY_EXPORT_ROUNDTRIP=1 FP16_TIED_EMBEDDING_EXPORT=1 INT4_LAYERS=\"0,1,2,3,4,5,6,7,8,9,10\" INT4_STEP=1 EVAL_STRIDE=256 EVAL_BATCH_SEQS=32 torchrun --standalone --nproc_per_node=1 train_gpt.py`
- Synced run artifacts into local `logs/experiments`.

### Result
- `exact_final_val_bpb=1.30667957` (`step_stop=1125`, `wallclock_seconds=776.47949`).
- `pre_quant_val_bpb=1.3345`, `bytes_total=13291021`.
- This is worse than the same configuration without warmdown (`1.29896417`) and does not improve the frontier.

### Directional impact
- Confirms warmdown extension is currently a non-promising axis for this quantized frontier.
- Next moves should likely prioritize additional architecture/sequence/optim schedule alternatives rather than longer warmdown on this exact config.
