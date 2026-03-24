# Scripts

Experiment helpers and worker lifecycle for this repo.

## Architecture

This project operates on a split architecture:
- **Mac Mini (Controller):** Local machine running Claude and maintaining the Git system of record. It manages branch creation, planning, dispatch, and final diagnosis/reflection.
- **RunPod (Workers):** Remote pods acting purely as pull-only executors.
- **GitHub:** Intermediary layer to sync code between Mac and RunPod.

There are two canonical execution lanes:
- `pg-exp-*` (1xH100) for exploration
- `pg-rec-*` (8xH100) for candidate/record checks

## Core Lifecycle

### Controller Commands
- `scripts/branch_cycle.sh <node_id>`: Deterministic, phase-bounded 3-step Claude session (`plan`, `diagnose`, `reflect`) in an isolated Git worktree. The script handles creating the local worktree, running the plan phase, committing local changes, pushing to GitHub, dispatching to RunPod, polling for completion, collecting artifacts, and running the diagnosis/reflection phases.
- `scripts/supervisor.sh`: Claims the first pending node from `registry/nodes.jsonl` under a portable local lock and launches one `branch_cycle.sh` execution for unattended queue draining.
- `scripts/sync_upstream_context.sh`: Syncs issues, PRs, and frontier status from the official OpenAI repository using the `gh` CLI. 

### Pod Lifecycle & Dispatch (Mac Side)
- `scripts/runpod_pool.sh`: Manage pod clusters using local `runpodctl` (`get`, `create`, `start`, `stop`, `terminate`) and the hardware settings in `config/runpod_profiles.json`.
- `scripts/runpod_dispatch.sh`: Reads a job spec JSON, finds or provisions an appropriate pod, resolves the SSH endpoint with `runpodctl ssh connect`, persists host/port metadata under `registry/spool/`, and launches the remote job. Set `RUNPOD_POD_ID` to pin the dispatch to a specific pod during smoke tests.
- `scripts/runpod_collect.sh`: Connects to the pod via SSH and port-aware `rsync` to pull back the canonical experiment directory, wrapper logs, and spool summary, then securely appends the results to `registry/runs.jsonl` with a macOS/Linux-safe file lock.

### Remote Execution (RunPod Side)
These scripts are deployed and executed on the pod by the Mac controller over SSH:
- `scripts/runpod_bootstrap_remote.sh`: Normalizes `origin` to the tracked GitHub repo, fetches it (`git fetch origin --prune`), creates a detached worktree at the exact designated commit SHA, and verifies the SHA matches.
- `scripts/runpod_run_remote.sh`: Validates hardware (exact GPU count and model), applies an outer timeout, and starts the `run_experiment.sh` invocation inside `tmux`.

## Execution Wrapper
`scripts/run_experiment.sh` is used inside pods to execute runs:
- Isolates outputs under `experiments/<run_id>`
- Validates `--required-gpu-count` and hardware strings via `nvidia-smi -L`
- Enforces an outer `timeout -k 30s` wrap around the training command
- Writes structured JSON metrics to be collected by the Mac controller

## Notes
- The controller never runs heavy processes locally; all execution logic MUST pass through the queue and RunPod.
- RunPod executors use the official Parameter Golf environment and are strictly pull-only. They will checkout an exact commit SHA for deterministic reproduction.
- Controller-side queue and ledger updates use portable local file locks so the same scripts work on this macOS controller and Linux workers.