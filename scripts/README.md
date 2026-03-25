# Scripts

Experiment helpers and worker lifecycle for this repo.

## Architecture

This project operates on a split architecture:
- **Mac Mini (Controller):** Local machine running Claude and maintaining the Git system of record. It manages branch creation, planning, dispatch, and final diagnosis/reflection.
- **RunPod (Workers):** Remote pods acting purely as pull-only executors.
- **GitHub:** Intermediary layer to sync code between Mac and RunPod.

The controller owns the shared runtime state under the main checkout:
- `registry/` is the single controller ledger for leases, nodes, heartbeats, spool records, and collected runs.
- `registry/controller_events.jsonl` is the append-only controller event log for dispatch, collect, cleanup, and TTL actions.
- `experiments/` under the main checkout is the canonical collection target, even when planning happens in a scratch worktree.
- Worktrees are disposable planning sandboxes; they are not the source of truth for controller state.

There are two canonical execution lanes:
- `pg-exp-*` (1xH100) for exploration
- `pg-rec-*` (8xH100) for candidate/record checks

## Core Lifecycle

### Controller Commands
- `scripts/start_swarm.sh [--no-validation] [--once]`: Bootstrap a controller run from a clean checkout. It ensures `registry/nodes.jsonl` exists, seeds `tree/<node_id>` from the requested base ref when missing, appends a pending node if there is no active pending/running entry yet, and then runs the supervisor once or in a loop. Use `--reset-tree-ref` when you intentionally want to rebase the seed node back to the chosen base ref before restarting.
- `scripts/branch_cycle.sh [--no-validation] <node_id>`: Deterministic, phase-bounded 3-step Claude session (`plan`, `diagnose`, `reflect`) in an isolated Git worktree. The script acquires a per-node controller lock, reconciles stale pod leases, runs the plan phase, commits only scoped source/doc changes (excluding runtime state like `worktrees/`, `experiments/`, and `registry/`), pushes to GitHub, dispatches to RunPod, polls the remote tmux session with a controller TTL, collects artifacts, performs post-run pod cleanup, and only then runs the diagnosis/reflection phases. With `--no-validation`, the controller rewrites the dispatched job spec to the regular `pg-exp-*` 1xH100 lane and tags it as `non_record_h100x1` instead of routing to `pg-rec-*`.
- `scripts/supervisor.sh [--no-validation]`: Reconciles stale pod leases, claims the first pending node from `registry/nodes.jsonl` under a portable local lock, and launches one `branch_cycle.sh` execution for unattended queue draining. This remains a one-pass worker; `start_swarm.sh` is the looped/bootstrap wrapper for unattended use.
- `scripts/install_reconcile_schedule.sh`: Installs a periodic Mac-side reconcile job via `launchd` or `cron` so crash recovery continues even when no controller cycle is currently running. The generated macOS agent writes an explicit Homebrew-aware `PATH` so `runpodctl` remains available outside an interactive shell.
- `scripts/sync_upstream_context.sh`: Syncs issues, PRs, and frontier status from the official OpenAI repository using the `gh` CLI. 
- `scripts/run_record_candidate.sh <name> [--3seed] [--no-validation]`: Helper that pushes the current branch and writes manual queue artifacts under `registry/queue/` for candidate-style launches. By default it emits the 8xH100 record/candidate lane. With `--no-validation`, it rewrites the generated job spec and wrapper command to the regular 1xH100 non-record lane instead.

### Pod Lifecycle & Dispatch (Mac Side)
- `scripts/runpod_pool.sh`: Manage pod clusters using local `runpodctl` (`get`, `create`, `start`, `stop`, `terminate`) and the hardware settings in `config/runpod_profiles.json`. `RUNPOD_TEMPLATE_ID` is required for pod creation; the controller no longer falls back to a generic image and will resolve the template's `imageName` automatically (or accept `RUNPOD_TEMPLATE_IMAGE_NAME` as an override for CLIs that require both flags). By default it preserves the template's startup behavior so built-in SSH services can come up; set `RUNPOD_CONTAINER_ARGS` only when you intentionally need to override the container start command. Exploration lanes can try multiple configured GPU types in priority order when RunPod capacity for the preferred H100 SKU is temporarily unavailable.
- `scripts/runpod_dispatch.sh`: Reads a job spec JSON, selects the first unleased `pg-*` pod that matches the requested lane (or provisions one), resolves the public SSH endpoint with `runpodctl ssh connect`, writes a lease record under `registry/spool/`, logs pod choice and dispatch events to `registry/controller_events.jsonl`, and launches the remote job. The job spec's `env_overrides` map is forwarded to the remote bootstrap and run scripts. Set `RUNPOD_POD_ID` to pin the dispatch to a specific pod during smoke tests.
- `scripts/runpod_collect.sh`: Connects to the pod via SSH and port-aware `rsync` to pull back the canonical experiment directory, wrapper logs, and spool summary, then securely appends the results to `registry/runs.jsonl` with duplicate `run_id` protection and logs success/failure in the controller event log.
- `scripts/runpod_cleanup.sh`: Applies the controller-owned post-run action (`stop`, `terminate`, or release-only) recorded in the lease metadata, records the final pod state, and logs the cleanup result in the controller event log.
- `scripts/runpod_reconcile.sh`: Crash-recovery path for unattended mode. It scans unreleased leases, collects artifacts for finished jobs, logs TTL-expiry events, and forces cleanup when a job exceeds its controller TTL. On macOS it prepends common local binary paths so controller tools like `runpodctl` also work under `launchd`.

### Remote Execution (RunPod Side)
These scripts are deployed and executed on the pod by the Mac controller over SSH:
- `scripts/runpod_bootstrap_remote.sh`: Normalizes `origin` to the tracked GitHub repo, fetches it (`git fetch origin --prune`), creates a detached worktree at the exact designated commit SHA, and verifies the SHA matches. If a template ships `/workspace/parameter-golf` without git metadata, bootstrap removes that directory and reclones before continuing. It also materializes the published FineWeb cache on first use under the shared repo cache at `/workspace/parameter-golf/data`; tune this with `RUNPOD_FINEWEB_VARIANT` and `RUNPOD_FINEWEB_TRAIN_SHARDS` if needed. The pod template is expected to already contain `git`, `jq`, `tmux`, and `rsync`; bootstrap only uses `apt-get` if `RUNPOD_BOOTSTRAP_ALLOW_APT_FALLBACK=1` is set explicitly.
- `scripts/runpod_run_remote.sh`: Validates hardware (exact GPU count and model), applies an outer timeout, and starts the `run_experiment.sh` invocation inside `tmux`. It now preserves caller-provided `DATA_PATH` and `TOKENIZER_PATH` values instead of overwriting them, and otherwise defaults them to the shared `/workspace/parameter-golf/data` cache that bootstrap prepares. `pg-exp` jobs default to a much larger outer timeout than `pg-rec` so 1-GPU exploratory runs can finish full final evaluation; override with `RUNPOD_OUTER_TIMEOUT_SECONDS` when needed.

## Execution Wrapper
`scripts/run_experiment.sh` is used inside pods to execute runs:
- Isolates outputs under `experiments/<run_id>`
- Validates `--required-gpu-count` and hardware strings via `nvidia-smi -L`
- Enforces a hard outer timeout around the training command, using the system timeout binary when available and a checked-in Python fallback otherwise
- Cleans up heartbeat state and writes a final spool state on exit, including failure exits
- Writes structured JSON metrics to be collected by the Mac controller

## Smoke Execution
- `scripts/run_smoke_sliding_eval.sh`: Short-TTL wrapper around `scripts/smoke_sliding_eval.py`. Use this instead of calling the Python smoke check directly so CUDA smoke hangs are killed quickly, even on controller machines that lack GNU `timeout`.

## Notes
- The controller never runs heavy processes locally; all execution logic MUST pass through the queue and RunPod.
- `scripts/start_swarm.sh` is the easiest first-run entrypoint because it bootstraps the missing runtime-only controller state (`registry/nodes.jsonl` and `tree/<node_id>`) that is intentionally not tracked in git.
- `--no-validation` means "do not route this launch to the 8xH100 record lane." It does **not** skip the normal final evaluation path inside `train_gpt.py`.
- Set `RUNPOD_TEMPLATE_ID` on the Mac controller before unattended launches so new pods always come from the known-good template.
- Install `scripts/runpod_reconcile.sh` on a periodic scheduler (`launchd` on macOS or `cron`) before leaving the controller unattended overnight; the checked-in installer now writes a PATH that includes common Homebrew locations.
- RunPod executors use the official Parameter Golf environment and are strictly pull-only. They checkout an exact commit SHA for deterministic reproduction, then the controller collects artifacts back over full SSH.
- Controller-side queue and ledger updates use portable local file locks so the same scripts work on this macOS controller and Linux workers.