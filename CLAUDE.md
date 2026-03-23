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
3. `registry/spool/*.json`
4. `PLAN.md`
5. `README.md`
6. `AGENTS.md` (durable preferences and workspace facts; updated via continual-learning)

## Standard Start Sequence

1. Confirm branch and git state.
2. Sync from `upstream` (`https://github.com/openai/parameter-golf`).
3. Check what is currently running on RunPod. Do not use pods that are not explicitly named with a `pg-` prefix.
4. If a Parameter Golf task is already running on a `pg-*` pod, inspect its ETA before launching anything new.
5. If a task finished, record the outcome, compare with best legal frontier, discard if worse.
6. If a new direction is needed, check upstream PRs or other novel approaches before falling back to repetitive sweeps.
7. If nothing useful is active, choose one bounded hypothesis from the compressed frontier or from a novel upstream approach.

## Worker Lifecycle

Start an autonomous worker cycle for a specific branch node:

```bash
scripts/branch_cycle.sh <node_id>
```

This runs a deterministic, phase-bounded 3-step Claude session (`plan`, `diagnose`, `reflect`) in an isolated Git worktree (`worktrees/<node_id>`). It enforces `--no-session-persistence` and strict `.claude/settings.json` permissions to keep runs concurrency-safe and side-effect free.

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
- Run metadata is spooled to `registry/spool/<run_id>.json`, not a shared full archive.
- Avoid repeating stale work; reconcile state before launching runs.
- Prefer one bounded hypothesis per run.
- Preserve exact metric and byte accounting on materially important runs.
- When the live journal or spooled results become noisy, compress them again.

### Quality

- No emojis in code or docs.
- Professional commit messages.
- Run relevant validation after making changes.
