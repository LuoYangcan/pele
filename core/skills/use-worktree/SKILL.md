---
name: use-worktree
description: Do code changes in a dedicated git worktree; the main checkout stays read-only. Triggers before coding to confirm the worktree and which task its branch belongs to. When already in a worktree on the same task's branch, continue there. Pure Q&A, reading code and status checks skip it. Meta configuration follows the AGENTS routing.
---

# use-worktree

## Decide

- Use `git rev-parse --git-dir` against `--git-common-dir` to tell whether you are in a linked worktree, then check the branch with `git branch --show-current`. Continue in that worktree only when its branch is clearly for the same task.
- When the current worktree is on a detached HEAD, the baseline branch or another task's branch, create a new task worktree from the target baseline and leave the current checkout and its changes alone.
- Project rules forbid creating branches and grant no worktree exception: ask the user first. Leave the main checkout's uncommitted changes and current branch as they are; do not move or revert them.

## Create

Starting from the main checkout, run `git worktree list` first. A worktree is reusable only if it sits under `.worktrees/`, is not in use by another task, has a clean tree, its branch is merged into `origin/<baseline>`, and its tip is not equal to the baseline. After fetching, run only inside that worktree `git switch -c <new-branch> --no-track origin/<baseline>`; if the machine-local hook `${XDG_CONFIG_HOME:-~/.config}/pele/worktree-post-create` is executable, then run it there as `WORKTREE_PATH="$PWD" WORKTREE_BRANCH=<new-branch> WORKTREE_NOTE="<task summary>" <hook>`.

To create a new one, use the baseline the project AGENTS names:

```bash
"$HARNESS_ROOT/scripts/worktree-bootstrap.sh" <slug> --base <baseline> --note "<task summary>" \
  [--type feat|fix|refactor|chore|docs|test|perf] [--copy <relative-path>]... [--init "<command>"]
```

The script fetches, creates `.worktrees/<slug>` from `origin/<baseline>` with `--no-track`, copies `.claude/settings.local.json`, trusts the directory, then runs the machine-local post-create hook above in the new worktree when it exists and is executable. The one-line `--note` reaches the hook as `WORKTREE_NOTE`; a failing hook only warns. The hook is not part of the repo; each machine places its own. Pass `--copy` for gitignored files the project needs to build (e.g. a local signing `.xcconfig`). `--init` runs only the initialization required to make the repo editable; no baseline build, no Simulator warm-up.

## Fill in (already in a worktree but missing local config)

Worktrees created outside the bootstrap (e.g. a desktop app's `.claude/worktrees/<name>`) may lack local config; copy `.claude/settings.local.json` and the gitignored files the project needs from the main checkout. SPM caches stay local to each worktree and are not shared with the main checkout.

## Lifecycle

Keep it while a PR or further iteration still needs it; remove it when the task is cancelled with no changes; with uncommitted changes, never discard or force-remove without the user's consent. Clean up with `cleanup-and-exit`.
