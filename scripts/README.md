# Scripts

Experiment helpers and worker lifecycle for this repo.

## Architecture

This project operates on a split architecture:
- **Mac Mini (Controller):** Local machine running Claude and maintaining the Git system of record. It manages branch creation, planning, dispatch, and final diagnosis/reflection.
- **RunPod (Workers):** Remote pods acting purely as pull-only executors.
- **GitHub:** Intermediary layer to sync code between Mac and RunPod.

The controller owns the shared runtime state under the main checkout:
- `registry/` is the single controller ledger for leases, nodes, heartbeats, spool records, and collected runs.
- `experiments/` under the main checkout is the canonical collection target, even when planning happens in a scratch worktree.
- Worktrees are disposable planning sandboxes; they are not the source of truth for controller state.

There are two canonical execution lanes:
- `pg-exp-*` (1xH100) for exploration
- `pg-rec-*` (8xH100) for candidate/record checks

## Core Lifecycle

### Controller Commands
- `scripts/branch_cycle.sh <node_id>`: Deterministic, phase-bounded 3-step Claude session (`plan`, `diagnose`, `reflect`) in an isolated Git worktree. The script acquires a per-node controller lock, reconciles stale pod leases, runs the plan phase, commits local changes, pushes to GitHub, dispatches to RunPod, polls the remote tmux session with a controller TTL, collects artifacts, performs post-run pod cleanup, and only then runs the diagnosis/reflection phases.
- `scripts/supervisor.sh`: Reconciles stale pod leases, claims the first pending node from `registry/nodes.jsonl` under a portable local lock, and launches one `branch_cycle.sh` execution for unattended queue draining.
- `scripts/sync_upstream_context.sh`: Syncs issues, PRs, and frontier status from the official OpenAI repository using the `gh` CLI. 

### Pod Lifecycle & Dispatch (Mac Side)
- `scripts/runpod_pool.sh`: Manage pod clusters using local `runpodctl` (`get`, `create`, `start`, `stop`, `terminate`) and the hardware settings in `config/runpod_profiles.json`.
- `scripts/runpod_dispatch.sh`: Reads a job spec JSON, selects the first unleased `pg-*` pod that matches the requested lane (or provisions one), resolves the public SSH endpoint with `runpodctl ssh connect`, writes a lease record under `registry/spool/`, and launches the remote job. Set `RUNPOD_POD_ID` to pin the dispatch to a specific pod during smoke tests.
- `scripts/runpod_collect.sh`: Connects to the pod via SSH and port-aware `rsync` to pull back the canonical experiment directory, wrapper logs, and spool summary, then securely appends the results to `registry/runs.jsonl` with duplicate `run_id` protection.
- `scripts/runpod_cleanup.sh`: Applies the controller-owned post-run action (`stop`, `terminate`, or release-only) recorded in the lease metadata and records the final pod state.
- `scripts/runpod_reconcile.sh`: Crash-recovery path for unattended mode. It scans unreleased leases, collects artifacts for finished jobs, and forces cleanup when a job exceeds its controller TTL.

### Remote Execution (RunPod Side)
These scripts are deployed and executed on the pod by the Mac controller over SSH:
- `scripts/runpod_bootstrap_remote.sh`: Normalizes `origin` to the tracked GitHub repo, fetches it (`git fetch origin --prune`), creates a detached worktree at the exact designated commit SHA, and verifies the SHA matches.
- `scripts/runpod_run_remote.sh`: Validates hardware (exact GPU count and model), applies an outer timeout, and starts the `run_experiment.sh` invocation inside `tmux`.

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
- RunPod executors use the official Parameter Golf environment and are strictly pull-only. They checkout an exact commit SHA for deterministic reproduction, then the controller collects artifacts back over full SSH.
- Controller-side queue and ledger updates use portable local file locks so the same scripts work on this macOS controller and Linux workers.