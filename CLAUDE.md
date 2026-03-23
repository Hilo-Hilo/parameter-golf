# CLAUDE.md - Parameter Golf Project

Project-specific operating context for this repo.

## Challenge Overview

- Goal: best language model under the `16,000,000`-byte artifact cap and 10-minute `8xH100` train/eval budget.
- Canonical metric: exact final roundtrip `val_bpb`.
- Stretch target: sub-1.0 exact final `val_bpb`.
- Official repo: `https://github.com/openai/parameter-golf`
- Tracked repo: `https://github.com/Hilo-Hilo/parameter-golf`

## Startup Files

Read these first:

1. `worker_program.md`
2. `journal.md`
3. `results/results.tsv`
4. `PLAN.md`
5. `README.md`

## Standard Start Sequence

1. Confirm branch and git state.
2. Sync from `upstream` (`https://github.com/openai/parameter-golf`).
3. Check what is currently running on RunPod. Do not use pods that are not explicitly named with a `pg-` prefix.
4. If a Parameter Golf task is already running on a `pg-*` pod, inspect its ETA before launching anything new.
5. If a task finished, record the outcome, compare with best legal frontier, discard if worse.
6. If a new direction is needed, check upstream PRs or other novel approaches before falling back to repetitive sweeps.
7. If nothing useful is active, choose one bounded hypothesis from the compressed frontier or from a novel upstream approach.

## Worker Lifecycle

Start the autonomous worker:

```bash
scripts/start_worker.sh
```

Check status:

```bash
scripts/worker_status.sh
```

Stop:

```bash
scripts/stop_worker.sh
```

The worker runs `claude -p` with `worker_program.md` as the prompt. State is a PID file at `automation/worker.pid`, output logs to `automation/worker.log`.

## Infrastructure

### RunPod

- Primary remote lane.
- Use RunPod CLI to create, manage, and monitor pods.
- Parameter Golf work should only run on pods with a `pg-` prefix.
- There may be other pods on the account used by a friend; those are off-limits.

## Working Style

### Git

1. Edit locally.
2. Each experimental approach gets its own `approach/<name>` branch. Never commit experiments to `main` or `research/*`.
3. Commit locally when asked or when the task explicitly requires it.
4. `git push`, then sync remote machines with `git pull` if needed.
5. Do not edit repo files directly over SSH.

### Research

- `worker_program.md` is the canonical autonomous operating program.
- `journal.md` is the compressed bootstrap journal and is append-only from this reset onward.
- `results/results.tsv` is the live frontier ledger, not the full archive.
- Avoid repeating stale work; reconcile state before launching runs.
- Prefer one bounded hypothesis per run.
- Preserve exact metric and byte accounting on materially important runs.
- When the live journal or results file becomes noisy, compress it again.

### Quality

- No emojis in code or docs.
- Professional commit messages.
- Run relevant validation after making changes.
