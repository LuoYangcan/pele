---
name: cleanup-and-exit
description: Clean task worktrees, reclaim their idle build caches, and retry previously deferred cleanup in the same repository. Use for /cleanup-and-exit, /clean-and-exit, or explicit worktree/cache cleanup requests; --repo inventories and --machine cleans rebuildable machine caches. Preserve unfinished source.
---

# cleanup-and-exit

Resolve installed paths per the [host adapter](../../rules/host-adapter.md) before running helpers.

## Select Scope

Both command aliases accept the same arguments. Forward all arguments to this skill.

| Invocation | Scope and action |
| --- | --- |
| No arguments | Remove eligible task worktrees, release their simulator leases, reclaim idle caches in retained task worktrees, and retry pending cleanup in the same repositories |
| `--repo [path]` | Read-only inventory of every registered worktree in the given repository (default: cwd), including cache sizes and simulator associations |
| `--machine [--repo path]` | Inventory then clean rebuildable machine caches; `--repo path` selects the repository whose local build caches are included |

Natural-language requests may select these scopes explicitly. `--repo` alone never authorizes deletion. `--machine` authorizes cache cleanup, not other tasks’ worktrees, local branches, simulator devices/data, runtime installations, or archives. For either non-default mode read [repository and machine modes](references/scopes.md). A request to implement or change these modes is not a request to run their cleanup.

Treat a task cleanup request as authorization to perform the routine cleanup below, including preservation of local task records and bounded generated-cache cleanup. Honor existing keep/delete/cache exclusions without asking again. Do not push, merge, delete remote branches, poll CI, or edit product code. For record archival, retained caches, and pending cleanup, read [retained-work handling](references/retained-work.md).

## Resolve Task Worktrees

Build the target list before choosing actions. Use explicit user targets first; a repository-wide cleanup request covers registered worktrees in that repository. A bare command covers this task's worktrees plus matching pending entries from prior authorized cleanup in the affected repositories; it never enrolls arbitrary discovered worktrees.

Read pending entries with `scripts/pending-cleanups.py list --repo <repository>`. Only matching worktree identities join the target list. Revalidate their current source, activity, and delivery exactly like current task targets; queue membership is not delivery proof. `--repo` remains read-only, and `--machine` does not process queued worktree removal.

For task cleanup, include every worktree created or reused for implementation, validation/review, or backport work in this conversation. Include the original working copy when this task moved or exported changes to another branch, worktree, or repository. Use available conversation history, task plans/logs, and attached worktrees to identify each path and its role; cwd and the final PR branch are not the entire target list. Read-only references to unrelated worktrees do not establish ownership.

Run `git worktree list --porcelain` in each affected repository to verify exact paths and branches, including task paths already removed. If the conversation provides no target, use the current registered non-primary worktree and matching pending entries. Stop only when task context, cwd, and the affected repository's pending queue identify no target; report "no task worktree identified", not "all worktrees cleaned". Do not stop merely because cwd is the main checkout. Ask only when ownership or scope is ambiguous; never infer task ownership from name or location alone.

Mark a target already absent only when both its directory and registration are absent; record any remaining branch/cache separately. If only the directory is absent, report the stale registration. Skip per-target git/simulator commands for missing directories.

Use Git registration to recognize linked worktrees regardless of their location, including `.worktrees/`, `.claude/worktrees/`, and `~/.codex/worktrees/`. Do not infer task ownership from these directory names. For each existing target, capture its root with `git -C <target> rev-parse --show-toplevel`. Resolve the main repo from the first registered worktree. Use an explicit per-target working directory for all state and simulator commands.

## Inspect and Report

Inspect each target before choosing its action:

```bash
git -C "$worktree_path" branch --show-current
git -C "$worktree_path" status --porcelain=v1 --untracked-files=all
git -C "$worktree_path" log --oneline '@{u}..HEAD'
# Run gh from the target repository; use pr list --head "$branch" --state all if needed.
gh pr view "$branch" --json number,state,mergedAt,headRefOid,url
```

Refresh relevant remote refs or query current remote heads as needed to establish delivery. Missing upstreams or failed commands mean unknown, not zero unpushed commits. Either of these establishes that the current HEAD is delivered:

- `gh` reports `MERGED` or a non-null `mergedAt`, and local HEAD equals or is an ancestor of the PR's `headRefOid`. Squash/rebase merges and a deleted remote source branch do not prevent cleanup. A merged PR does not cover later local commits.
- The intended remote delivery branch contains the local HEAD, such as a release branch updated by a direct cherry-pick and push. This means the destination for finished work, not merely a pushed feature branch. No PR is required for this route.

These proofs can replace a missing upstream. For an explicit deletion of an unfinished worktree, separately verify that any local commits are pushed before deleting its branch.

If the branch-name PR lookup is empty, follow this task's recorded PR URL, renamed branch, or export/backport history before concluding delivery is unknown. Verify the same HEAD coverage above; a related feature's merged PR or similar title is not proof. Report feature delivery separately from local commits and uncommitted changes left in the original working copy. Do not reset, stash, or commit changes just to make a retained worktree pass the cleanup gates.

Before acting, give a compact per-target summary, using `unknown` where evidence is missing:

```text
worktree / branch / role: <path> / <branch> / <implementation | original copy | validation/review | backport>
uncommitted / unpushed: <counts or unknown>
delivery: <PR state and number | direct-push target | unknown>
nested worktrees: <none | paths and branches>; action: <delete | keep | already absent | needs clarification>; reason: <evidence or remaining work>
```

## Resolve Simulator Associations

On hosts with Xcode, inspect selected worktrees together before removing them. On hosts without Xcode, use existing registration and task records for any known associations. Lease release does not require Xcode.

```bash
python3 "$HARNESS_ROOT/scripts/worktree-simulators.py" inspect --worktree <path> [--worktree <path> ...]
```

It reports pooled leases, legacy `.claude/sim-udid*` registrations, generated-name candidates and other owners across runtime variants. Routine worktree cleanup preserves every simulator and its app data, including login sessions. For a removed worktree, record the UDID and any legacy mapping before the worktree disappears.

For a separately requested simulator shutdown or deletion, use the helper's `shutdown` or `delete` action after inspection. These actions only release pooled leases. Keep shared or ambiguous devices and their surviving owners' registrations. Use `--include-named` only after establishing ownership of the exact generated-name candidate. For custom-named devices, verify the exact UDID from task history against `simctl` and repository registrations. On failure, retain the registration and report the error.

## Choose Action

| Request and verified state | Action |
| --- | --- |
| Cleanup request; clean worktree and delivered HEAD | Remove the worktree and local task branch after the nested Git checks. Verified clean SwiftPM checkouts go with the worktree |
| Explicit delete worktree and branch; clean, no unpushed commits | Delete both, including for an open PR |
| Explicit delete worktree, keep branch; clean | Delete worktree, preserve branch and any local-only commits |
| Delivered HEAD; only untracked review/plan records remain | Archive and verify those records outside the worktree, require a fresh clean status, then apply ordinary removal gates |
| Explicit keep | Keep worktree and branch, cancel pending removal, honor cache exclusions, and release its simulator lease when idle |
| Explicit cancel | Do nothing |
| Dirty source, unfinished/unknown delivery, or active work without an explicit deletion choice | Keep source and branch; reclaim independently eligible idle caches and record pending cleanup with the concrete reason |

Do not show a fixed menu or require a second confirmation for an authorized, eligible cleanup. Ask only for an unresolved target or a material keep/delete choice. A retained target does not block cleanup of other independent eligible targets.

Do not remove an actively used worktree or stop builds, debuggers, or interaction sessions to make cleanup pass. Retaining source does not automatically retain every generated cache: use `scripts/worktree-caches.py inspect|clean --worktree <path>` under the retained-work contract. Explicit cancel performs neither cache cleanup nor queue updates.

## Safety Gates

- Every deletion requires no uncommitted files. Local branch deletion also requires no unpushed work beyond the verified delivery proof. Do not interpret a failed inspection as a passed gate.
- Never use `git worktree remove --force`.
- Never remove the worktree from inside itself; run `git worktree remove` from the main repo root.
- Resolve simulator associations before removing the worktree and pass each exact target path to the helper.
- Capture the target worktree root with `git rev-parse --show-toplevel` before changing cwd. Run DerivedData cleanup only after worktree removal succeeds.
- Remove global DerivedData entries for a removed worktree only through `scripts/remove-worktree-derived-data.sh`; never match caches by project name or a broad glob. Retained-worktree cache cleanup uses the separate exact-child helper; it does not bypass the removed-worktree guard. Explicit machine-mode global cleanup follows its scope reference.
- For a worktree selected for removal, do not pre-delete `build/`, local `DerivedData`, or Swift Package `.build`; successful removal handles its generated files. For retained worktrees, remove only verified children selected by `scripts/worktree-caches.py`, never those whole parent directories or dependency source. Do not delete shared `~/Library/Caches/org.swift.swiftpm`.

## Nested Worktrees

Before deletion, list all registered worktrees below `<worktree-path>/`, including `.subworktrees/` and nested `.claude/worktrees/`. Inspect unregistered nested Git repositories separately.

- Apply the same task scope, action selection, and safety gates to each descendant. No extra confirmation is needed for eligible descendants already within the task's cleanup scope.
- Keep the parent if any descendant is unrelated, retained, or fails its safety gate. Clarify ambiguous descendants together rather than asking once per path.
- From `<main-repo>`, remove eligible descendants deepest-path-first without `--force`. After each successful removal, run `scripts/remove-worktree-derived-data.sh` with that descendant path.
- Remove the parent only after no registered descendant remains.

If the current target is itself a sub-worktree, capture its root before moving to its parent and apply the normal option flow to that captured path.

### Generated SwiftPM checkouts

For a delivered worktree, treat Git-ignored, worktree-local SwiftPM checkouts under Xcode's `SourcePackages/checkouts` or SwiftPM's `.build/checkouts` as rebuildable when package state or the lockfile identifies their origin. Inspect each checkout and initialized nested submodule with `git status --porcelain=v1 --untracked-files=all --ignore-submodules=none`. Check detached HEAD, local refs and stashes with `git rev-list --max-count=1 --all HEAD --not <verified-revision> ...`. Use matching dependency pins, committed submodule gitlinks and verified upstream refs as exclusions. Any remaining commit is unverified. Local tags and an empty upstream range alone do not establish recoverability.

If all checks pass, remove the whole worktree with ordinary `git worktree remove`. Archive ignored task records and local settings first. Retain the worktree and record the exact path and reason if a checkout has local changes, unpublished commits or unknown provenance. Preserve other unregistered nested Git repositories. The SwiftPM exception applies only to whole-worktree removal.

## Execute

Release leases for worktrees selected for removal and idle worktrees the user explicitly chose to keep. Record the inspection results and any legacy mappings in the cleanup receipt before removing their source worktrees:

```bash
python3 "$HARNESS_ROOT/scripts/worktree-simulators.py" release --worktree <path> [--worktree <path> ...]
```

Run each step as a checked command. Report lease release failures and continue independent targets.

Resolve:

- `<main-repo>`: first column of the first `git worktree list` row
- `<worktree-path>`: absolute target root from `git rev-parse --show-toplevel` before changing cwd
- `<slug>`: basename of the resolved worktree root
- `<branch>`: current branch

Delete worktree and local task branch:

```bash
worktree_path="$(git rev-parse --show-toplevel)"
# Simulator associations recorded and leases released.
cd <main-repo>
git worktree remove "$worktree_path"
bash "$HARNESS_ROOT/core/skills/cleanup-and-exit/scripts/remove-worktree-derived-data.sh" "$worktree_path"
git branch -D <branch>
```

Delete worktree, keep branch:

```bash
worktree_path="$(git rev-parse --show-toplevel)"
# Simulator associations recorded and leases released.
cd <main-repo>
git worktree remove "$worktree_path"
bash "$HARNESS_ROOT/core/skills/cleanup-and-exit/scripts/remove-worktree-derived-data.sh" "$worktree_path"
```

The DerivedData script removes only cache entries whose `WorkspacePath` equals `<worktree-path>` or is below it, and refuses to run while `<worktree-path>` still exists. Run it after any successful deletion path, including `ExitWorktree remove`, and report its removed count and size. The helper supports `.worktrees/`, `.claude/worktrees/`, and `.codex/worktrees/`; for another location report the unsupported path instead of bypassing its guard. A skipped, failed, or unsupported helper is not a successful zero-item cleanup; report it separately. Then continue future commands from `<main-repo>`. If an `ExitWorktree` tool exists, use its matching remove/keep action. Otherwise, report the main repo path without simulating a host exit or archiving the task.

## Verify and Close

After removal, verify that the exact directory is absent and its registration is absent from `git worktree list --porcelain`. If deleting the local branch was selected, verify that it is absent too. A successful command or merged PR alone is not the removal receipt.

Re-enumerate the affected repositories once at the end and reconcile every target with the original target list. Report each path as removed, already absent, retained with its reason, or failed with the error; include simulator/cache outcomes, archival paths, and remaining action. Report source-worktree and generated-cache counts separately, with measured space change rather than overlapping estimated totals. Remove pending entries only after both directory and registration are verified absent, or when the user explicitly cancels deferred removal. Retained targets remain visible with their pending status and retry condition.

If the host recreates a task worktree, report the replacement path and reason as a remaining target. Do not repeatedly delete replacements or claim that cleanup is complete while the directory remains. Say "all task worktrees removed" only when every task target is verified absent; otherwise say "eligible worktrees cleaned; remaining directories: ...". Preserve unrelated worktrees and distinguish them from retained task targets.
