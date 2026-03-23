## Learned User Preferences

- Use Claude Code for autonomous worker flows, scripts, and documentation in this repo; do not substitute Codex for that role.
- Keep `CLAUDE.md` tracked in git so Claude Code can load project context on init; do not git-ignore files that are required for correct branching, worker behavior, or onboarding.
- Before destructive git commands that discard working tree changes, use stash, recovery paths, or explicit user confirmation; do not use `git reset --hard` casually when uncommitted work could disappear.
- Prefer minimal, explicit shell wrappers over large orchestration stacks unless added complexity clearly buys reliability here.
- Keep novel Parameter Golf experiments on dedicated `approach/<name>` branches; treat `main` as the shared integration baseline.
- When the user asks to change git attribution on this machine (for example dropping Claude from co-authored trailers), follow that for local commits.
- After substantive code or script changes, update the markdown that documents behavior so operators are not misled (only where such docs already exist and apply).

## Learned Workspace Facts

- Use GitHub CLI for GitHub auth and Git credential helper: run `gh auth login` (HTTPS) and `gh auth setup-git` so `git push`/`git pull` to `github.com` use `gh` tokens; prefer `gh` for PRs and repo browser workflows; keep `origin` as HTTPS.
- RunPod usage for Parameter Golf should target pods whose names start with `pg-`; avoid using unrelated pods on the account without explicit user approval.
- Detached or non-TTY launches of `claude -p` should feed non-interactive stdin (for example `< /dev/null`) so the process does not block waiting for terminal input.
- Default training layouts that write fixed artifact filenames under the repo root can collide when multiple runs share one checkout; isolate outputs per run when parallelism or overlapping experiments are possible.
