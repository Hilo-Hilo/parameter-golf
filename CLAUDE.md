# CLAUDE.md - Parameter Golf Project

Project-specific operating context for this repo.

## Challenge Overview

- Goal: best language model under the `16,000,000`-byte artifact cap and 10-minute `8xH100` train/eval budget.
- Canonical metric: exact final roundtrip `val_bpb`.
- Stretch target: sub-1.0 exact final `val_bpb`.
- Legality rules: eval budget is separate, no network calls during evaluation, backward-looking TTT is allowed, pre-eval adaptation on validation is not allowed, val tokens cannot be stored in the artifact. Serious SOTA claims should plan for 3-seed significance checks.
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

1. **HARD REQUIREMENT**: Read `context/upstream/issue_140.md`, `context/upstream/pr_digest.md`, and `context/upstream/frontier_digest.md` to understand the true current SOTA and legality rules. You MUST do this before planning a new approach.
2. Read `registry/jobs.jsonl` and `registry/runs.jsonl` to understand the current research frontier.
3. If a new direction is needed, check upstream PRs or other novel approaches before falling back to repetitive sweeps.
4. Propose a single bounded hypothesis via the `plan` phase JSON schema. The shell controller will manage the git branching, pushing to GitHub, execution via RunPod, and validation.

## Worker Lifecycle

Start an autonomous worker cycle for a specific branch node:

```bash
scripts/branch_cycle.sh <node_id>
```

This runs a deterministic, phase-bounded 3-step Claude session (`plan`, `diagnose`, `reflect`) in an isolated Git worktree (`worktrees/<node_id>`). The controller still owns the shared `registry/` and `experiments/` ledgers, pod leases, cleanup, and crash recovery. It enforces `--no-session-persistence` and strict `.claude/settings.json` permissions to keep runs concurrency-safe and side-effect free. 

**Note**: Branch creation, git upstream synchronization, and infrastructure execution are strictly handled by the shell wrapper. Do not attempt to run git branch/push/fetch commands or interact directly with remote infra in the worker cycle.

## Working Style

### Git

1. The shell controller handles all worktree creation, branching, and commits during autonomous runs.
2. If working manually, each experimental approach gets its own `approach/<name>` branch. Never commit experiments to `main` or `research/*`.
3. The worker agent must not run `git push`, `git fetch`, or `git worktree`.
4. Do not edit repo files directly over SSH.

### Controller
Pods are dumb executors. Claude never touches RunPod directly. The local controller owns branch pushes, the shared registry, job queueing, pod selection, remote launch, artifact collection, and post-run stop/terminate decisions.

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
