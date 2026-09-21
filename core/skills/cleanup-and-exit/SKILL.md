---
name: cleanup-and-exit
description: Clean up this task's Git worktrees before exiting, including related backport worktrees. Use when the user invokes /cleanup-and-exit or /clean-and-exit, asks to clean up before exit, or asks to remove or keep a task worktree. Automatically remove clean, delivered task worktrees and their local branches; preserve unfinished work.
---

# cleanup-and-exit

Resolve installed paths per the [host adapter](../../rules/host-adapter.md) before running helpers.

Treat a cleanup request as authorization to perform the routine cleanup below. Honor the user's existing scope and keep/delete choices without asking again. Do not push, merge, delete remote branches, poll CI, or edit product code.

## Resolve Task Worktrees

Use explicit user targets first. Otherwise, use registered worktrees that this conversation established as the task's implementation or backport workspaces. This may include multiple worktrees even when the host's cwd is the main checkout. Read-only references to other worktrees do not establish ownership.

Run `git worktree list --porcelain` to verify exact paths and branches. If the conversation provides no target, use the current worktree under `.worktrees/`. Stop only when neither task context nor cwd identifies a task worktree; do not stop merely because cwd is the main checkout. Ask a targeted question only when ownership or scope is ambiguous; never sweep unrelated worktrees by name or location.

For each target, capture its root with `git -C <target> rev-parse --show-toplevel`. Resolve the main repo from the first registered worktree. Use an explicit per-target working directory for all state and simulator commands.

## Inspect and Report

Inspect each target before choosing its action:

```bash
git -C "$worktree_path" branch --show-current
git -C "$worktree_path" status --short
git -C "$worktree_path" log --oneline '@{u}..HEAD'
# Run gh from the target repository; use pr list --head "$branch" --state all if needed.
gh pr view "$branch" --json number,state,mergedAt,headRefOid,url
```

Refresh relevant remote refs or query current remote heads as needed to establish delivery. Missing upstreams or failed commands mean unknown, not zero unpushed commits. Either of these establishes that the current HEAD is delivered:

- `gh` reports `MERGED` or a non-null `mergedAt`, and local HEAD equals or is an ancestor of the PR's `headRefOid`. Squash/rebase merges and a deleted remote source branch do not prevent cleanup. A merged PR does not cover later local commits.
- The intended remote delivery branch contains the local HEAD, such as a release branch updated by a direct cherry-pick and push. This means the destination for finished work, not merely a pushed feature branch. No PR is required for this route.

These proofs can replace a missing upstream. For an explicit deletion of an unfinished worktree, separately verify that any local commits are pushed before deleting its branch.

Before acting, give a compact per-target summary, using `unknown` where evidence is missing:

```text
worktree / branch: <path> / <branch>
uncommitted / unpushed: <counts or unknown>
delivery: <PR state and number | direct-push target | unknown>
nested worktrees: <none | paths and branches>; action: <delete | keep | needs clarification>
```

## Choose Action

| Request and verified state | Action |
| --- | --- |
| Cleanup request; clean worktree and delivered HEAD | Delete worktree and local task branch directly |
| Explicit delete worktree and branch; clean, no unpushed commits | Delete both, including for an open PR |
| Explicit delete worktree, keep branch; clean | Delete worktree, preserve branch and any local-only commits |
| Explicit keep | Keep worktree and branch; shut down its simulator |
| Explicit cancel | Do nothing |
| Dirty worktree, or unfinished/unknown delivery without an explicit deletion choice | Keep and report the concrete reason |

Do not show a fixed menu or require a second confirmation for an authorized, eligible cleanup. Ask only for an unresolved target or a material keep/delete choice. A retained target does not block cleanup of other independent eligible targets.

## Safety Gates

- Every deletion requires no uncommitted files. Local branch deletion also requires no unpushed work beyond the verified delivery proof. Do not interpret a failed inspection as a passed gate.
- Never use `git worktree remove --force`.
- Never remove the worktree from inside itself; run `git worktree remove` from the main repo root.
- Run simulator cleanup before changing cwd because `worktree-sim.sh` locates the worktree from cwd.
- Capture the target worktree root with `git rev-parse --show-toplevel` before changing cwd. Run DerivedData cleanup only after worktree removal succeeds.
- Delete Xcode DerivedData only through `scripts/remove-worktree-derived-data.sh`; never match caches by project name or a broad glob.
- Do not separately delete `build/`, local `DerivedData`, or Swift Package `.build` below the target; successful worktree removal deletes them. Do not delete the shared `~/Library/Caches/org.swift.swiftpm` cache.

## Nested Worktrees

Before deletion, list registered worktrees whose absolute path starts with `<worktree-path>/.subworktrees/`.

- Apply the same task scope, action selection, and safety gates to each descendant. No extra confirmation is needed for eligible descendants already within the task's cleanup scope.
- Keep the parent if any descendant is unrelated, retained, or fails its safety gate. Clarify ambiguous descendants together rather than asking once per path.
- From `<main-repo>`, remove eligible descendants deepest-path-first without `--force`. After each successful removal, run `scripts/remove-worktree-derived-data.sh` with that descendant path.
- Remove the parent only after no registered descendant remains.

If the current target is itself a sub-worktree, capture its root before moving to its parent and apply the normal option flow to that captured path.

## Execute

Resolve:

- `<main-repo>`: first column of the first `git worktree list` row
- `<worktree-path>`: absolute target root from `git rev-parse --show-toplevel` before changing cwd
- `<slug>`: directory name under `.worktrees/`
- `<branch>`: current branch

Delete worktree and local task branch:

```bash
worktree_path="$(git rev-parse --show-toplevel)"
bash "$HARNESS_ROOT/scripts/worktree-sim.sh" delete
cd <main-repo>
git worktree remove "$worktree_path"
bash "$HARNESS_ROOT/core/skills/cleanup-and-exit/scripts/remove-worktree-derived-data.sh" "$worktree_path"
git branch -D <branch>
```

Delete worktree, keep branch:

```bash
worktree_path="$(git rev-parse --show-toplevel)"
bash "$HARNESS_ROOT/scripts/worktree-sim.sh" delete
cd <main-repo>
git worktree remove "$worktree_path"
bash "$HARNESS_ROOT/core/skills/cleanup-and-exit/scripts/remove-worktree-derived-data.sh" "$worktree_path"
```

Keep worktree and branch:

```bash
bash "$HARNESS_ROOT/scripts/worktree-sim.sh" shutdown
```

The DerivedData script removes only cache entries whose `WorkspacePath` equals `<worktree-path>` or is below it, and refuses to run while `<worktree-path>` still exists. Run it after any successful deletion path, including `ExitWorktree remove`, and report its removed count and size. Then continue future commands from `<main-repo>`. If an `ExitWorktree` tool exists, use its matching remove/keep action. Otherwise, report the main repo path without simulating a host exit or archiving the task.
