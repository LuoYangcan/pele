---
name: cleanup-and-exit
description: Clean up the current git worktree before exiting an agent session. Use when the user invokes `/cleanup-and-exit`, `/clean-and-exit`, asks to clean worktree before exit/quit, or wants to remove/keep a task worktree after PR review/merge. Handles git worktree state, nested sub-worktrees, PR OPEN/MERGED/CLOSED status, optional simulator cleanup, worktree-local build artifacts, Xcode DerivedData tied to deleted worktrees, and Codex/Claude fallback when no interactive prompt UI is available.
---

# cleanup-and-exit

Clean the current task worktree before the user exits. Do not push, merge, or edit product code.

## Inspect State

Run from the current cwd:

```bash
pwd
git rev-parse --abbrev-ref HEAD 2>/dev/null
git status --short 2>/dev/null | wc -l
git worktree list 2>/dev/null
git log --oneline @{u}..HEAD 2>/dev/null
gh pr view "$(git rev-parse --abbrev-ref HEAD)" --json number,state,mergedAt,url 2>/dev/null \
  || gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --state all --json number,state,mergedAt,url 2>/dev/null \
  || true
```

Use `gh` PR state as truth. `MERGED` or non-null `mergedAt` means the PR is merged even if local git does not show the branch merged.

If cwd is not under `.worktrees/<slug>/`, report that there is no worktree cleanup needed and stop.

## Report Summary

Before any action, report:

```text
worktree: .worktrees/<slug>/
branch: <branch>
uncommitted files: <N>
unpushed commits: <M>
PR: <not opened | #123 OPEN | #123 MERGED | #123 CLOSED>
nested worktrees: <none | paths and branches>
```

## Choose Action

If an interactive question tool is available, ask the user to choose:

1. Delete worktree + delete local branch
2. Delete worktree, keep branch
3. Keep worktree + branch
4. Cancel

If no interactive question tool is available, ask a plain-text confirmation instead. Do not run option 1 or 2 from a bare `/cleanup-and-exit` / `/clean-and-exit` message unless the user's current or immediately previous message explicitly selected that action.

Allowed textual selections:

- Option 1: "删 worktree + branch", "delete worktree and branch", "PR merged 了删掉"
- Option 2: "删 worktree 保留 branch", "delete worktree keep branch"
- Option 3: "保留", "keep worktree", "别删"
- Option 4: "取消", "cancel"

Recommended default for the prompt: option 1 when PR is `MERGED`, uncommitted files = 0, and unpushed commits = 0; otherwise option 3.

## Safety Gates

- Option 1 requires uncommitted files = 0 and unpushed commits = 0.
- Option 2 requires uncommitted files = 0.
- Never use `git worktree remove --force`.
- Never remove the worktree from inside itself; run `git worktree remove` from the main repo root.
- Run simulator cleanup before changing cwd because `worktree-sim.sh` locates the worktree from cwd.
- Capture the target worktree root with `git rev-parse --show-toplevel` before changing cwd. Run DerivedData cleanup only after worktree removal succeeds.
- Delete Xcode DerivedData only through `scripts/remove-worktree-derived-data.sh`; never match caches by project name or a broad glob.
- Do not separately delete `build/`, local `DerivedData`, or Swift Package `.build` below the target; successful worktree removal deletes them. Do not delete the shared `~/Library/Caches/org.swift.swiftpm` cache.
- Do not run `git push`, `gh pr merge`, or any CI polling.

## Nested Worktrees

Before option 1 or 2, list registered worktrees whose absolute path starts with `<worktree-path>/.subworktrees/`.

- Inspect each descendant's branch, uncommitted files, and unpushed commits with the same safety gates as the parent.
- Ask one explicit confirmation listing every descendant and whether to delete its local branch. Abort parent deletion if any descendant is kept or fails its safety gate.
- From `<main-repo>`, remove confirmed descendants deepest-path-first without `--force`. After each successful removal, run `scripts/remove-worktree-derived-data.sh` with that descendant path.
- Remove the parent only after no registered descendant remains.

If the current target is itself a sub-worktree, capture its root before moving to its parent and apply the normal option flow to that captured path.

## Execute

Resolve:

- `<main-repo>`: first column of the first `git worktree list` row
- `<worktree-path>`: absolute target root from `git rev-parse --show-toplevel` before changing cwd
- `<slug>`: directory name under `.worktrees/`
- `<branch>`: current branch

Option 1:

```bash
worktree_path="$(git rev-parse --show-toplevel)"
bash ~/.claude/scripts/worktree-sim.sh delete
cd <main-repo>
git worktree remove "$worktree_path"
bash ~/.claude/skills/cleanup-and-exit/scripts/remove-worktree-derived-data.sh "$worktree_path"
git branch -D <branch>
```

Option 2:

```bash
worktree_path="$(git rev-parse --show-toplevel)"
bash ~/.claude/scripts/worktree-sim.sh delete
cd <main-repo>
git worktree remove "$worktree_path"
bash ~/.claude/skills/cleanup-and-exit/scripts/remove-worktree-derived-data.sh "$worktree_path"
```

Option 3:

```bash
bash ~/.claude/scripts/worktree-sim.sh shutdown
```

The DerivedData script removes only cache entries whose `WorkspacePath` equals `<worktree-path>` or is below it, and refuses to run while `<worktree-path>` still exists. Run it after any successful deletion path, including `ExitWorktree remove`, and report its removed count and size. Then continue future commands from `<main-repo>`. If an `ExitWorktree` tool exists, use `remove` for option 1 and `keep` for options 2/3. In Codex Desktop/CLI where no `ExitWorktree` tool exists, do not simulate it; just report the main repo path.

Option 4: do nothing.
