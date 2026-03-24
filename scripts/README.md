# Scripts

Experiment helpers and worker lifecycle for this repo.

## Architecture

This project operates on a split architecture:
- **Mac Mini (Controller):** Local machine running Claude and maintaining the Git system of record.
- **RunPod (Workers):** Remote pods executing the actual 1xH100 exploration and 8xH100 record lanes.
- **GitHub:** Intermediary layer to sync code between Mac and RunPod.

## Core Lifecycle

### Controller Commands
- `scripts/branch_cycle.sh <node_id>`: Deterministic, phase-bounded 3-step Claude session (`plan`, `diagnose`, `reflect`) in an isolated Git worktree.
- `scripts/push_branch_for_job.sh`: Commits and pushes branch, generating a job spec for the pod queue.
- `scripts/run_record_candidate.sh`: The official lane for creating candidates on 8xH100 hardware.
- `scripts/sync_upstream_context.sh`: Syncs issues, PRs, and frontier status from the official OpenAI repository.

### Pod Lifecycle & Queue
- `scripts/runpod_pool.sh`: Manage pod clusters (`list`, `create`, `stop`, `terminate`).
- `scripts/runpod_dispatch.py`: Read the job queue and dispatch work to idle pods.
- `scripts/runpod_reconcile.py`: Sync state between pods and queue.
- `scripts/runpod_status.sh`: Get an overview of queue depth and pod health.

### Remote Execution
These scripts run *on the pod* via SSH and are managed by the Mac:
- `scripts/runpod_bootstrap_remote.sh`: Fetches repo, ensures `jq`/`tmux`/`rsync`, prepares `data/` volume.
- `scripts/runpod_prepare_worktree_remote.sh`: Creates a detached git worktree from the designated commit.
- `scripts/runpod_launch_remote.sh`: Validates GPUs, applies timeouts, and starts the `run_experiment.sh` invocation inside `tmux`.
- `scripts/runpod_collect_remote.sh` (executed locally): Connects to the pod to `rsync` back metrics, logs, and `registry/runs.jsonl` summaries.
- `scripts/runpod_cancel_remote.sh`: Kills active tmux sessions.

## Local & Pod Runner Wrapper
`scripts/run_experiment.sh` is used inside pods to execute runs:
- Isolates outputs under `experiments/<run_id>`
- Validates `--required-gpu-count` and hardware strings
- Emits heartbeat JSON updates during run
- Writes structured JSON metrics to the global `registry/runs.jsonl` under `flock`

## Notes
- To debug a remote pod, connect via SSH and `tmux attach -t job_<job_id>`.
- The controller never runs heavy processes; all execution logic MUST pass through the queue and RunPod.
