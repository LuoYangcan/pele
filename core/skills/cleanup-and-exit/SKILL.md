---
name: cleanup-and-exit
description: Clean task worktrees and their idle build caches, and retry deferred cleanup in the same repository. Use for /cleanup-and-exit, /clean-and-exit, or explicit worktree/cache cleanup requests; --repo inventories read-only, --machine cleans rebuildable machine caches. Preserves unfinished source.
---

# cleanup-and-exit

## Scope

`/cleanup-and-exit` and alias `/clean-and-exit` (or plain-language equivalents) take the same arguments; forward all. Asking to implement or change a mode is not a request to run it.

- No args: remove eligible task worktrees, release their leases, clean idle caches of retained ones, retry same-repo pending entries. Authorizes every routine step here without re-asking; honor existing keep/delete/cache exclusions. Never push, merge, delete remote branches, poll CI or edit product code.
- `--repo [path]` (default cwd): read-only inventory. `--machine [--repo path]`: clean rebuildable machine caches plus that repo's local build caches; never other tasks' worktrees, branches, simulator devices/data, runtimes, archives or the queue. Both: [scopes.md](references/scopes.md).

Archival, nested SwiftPM checkouts, retained-worktree caches, pending queue: [retained-work.md](references/retained-work.md).

## Targets

- Explicit targets first; a repo-wide request covers its registered worktrees.
- Bare command: worktrees this task created or reused (implementation, validation/review, backport) and the original copy if work moved elsewhere, per conversation history, plans/logs and attached worktrees (not just cwd or the PR branch), plus matching [pending entries](references/retained-work.md#pending-queue). Else the current registered non-primary worktree plus pending entries. Else report "no task worktree identified", not "all worktrees cleaned"; a main-checkout cwd alone is no reason to stop.
- Never enroll arbitrary discovered or merely-read worktrees or infer ownership from name or location; ask only if ownership or scope is ambiguous.
- Verify with `git worktree list --porcelain` in each affected repo (main repo = first entry); registration, not location, defines a linked worktree (`.worktrees/`, `.claude/worktrees/`, `~/.codex/worktrees/`). Capture each root via `git -C <t> rev-parse --show-toplevel` before any cd; use explicit target paths.
- Absent = no directory and no registration (report leftover branch/cache separately); directory gone but registered = stale registration. Skip commands for missing directories.

## Inspect

Per target: dirty and unpushed (`@{u}..HEAD`) counts and, in its repo, `gh pr view <branch> --json state,mergedAt,headRefOid,url` (or `gh pr list --head <branch> --state all`). Refresh remote refs as needed; a missing upstream or failed command = unknown, never zero. HEAD is delivered only if either holds (each replaces a missing upstream):

- PR merged and HEAD equals or is an ancestor of `headRefOid` (squash/rebase or deleted remote branch fine; later local commits uncovered).
- The intended delivery branch (destination, e.g. a release branch after a direct cherry-pick push; not a pushed feature branch) contains HEAD.

Empty lookup: first follow this task's recorded PR URL, renamed branch or export/backport history; a related PR or similar title is not proof. Report feature delivery apart from local commits/uncommitted changes in the original copy. Never reset, stash or commit to pass a gate. Before acting, per target (`unknown` where unproven):

```text
<path> / <branch> / <implementation | original copy | validation/review | backport>
uncommitted / unpushed: <counts | unknown>; delivery: <PR state #n | direct-push target | unknown>
nested: <none | paths, branches>; action: <delete | keep | already absent | needs clarification>; reason: <evidence | remaining work>
```

## Simulators

Before removal, inspect all targets in one read-only call:

```bash
python3 $HARNESS_ROOT/scripts/worktree-simulators.py inspect --worktree <path> [--worktree <path> ...]
```

Cleanup keeps every device with its app/login data and only releases leases. `shutdown`/`delete` only on separate request (pooled devices are only released); keep shared/ambiguous devices and other owners' registrations; `--include-named` needs proven ownership of that exact generated-name device; a custom-named device needs its task-history UDID matched against `simctl` and repo registrations. On failure keep the registration and report.

## Choose Action

| Request; verified state | Action |
| --- | --- |
| Cleanup; clean, delivered | Remove worktree and task branch |
| Delete worktree + branch; clean, nothing unpushed | Delete both, even with an open PR |
| Delete worktree, keep branch; clean | Delete worktree only |
| Delivered; only untracked `.reviews/`/`.specs/` | [Archive](references/retained-work.md#archive-task-records), re-check clean, then normal gates |
| Keep | Keep both, cancel pending removal, honor cache exclusions, release lease when idle |
| Cancel | Nothing: no removal, cache cleanup or queue update |
| Dirty, undelivered/unknown or active, no explicit delete | Keep source and branch; clean eligible idle caches; queue with concrete reason |

No fixed menu or second confirmation for eligible authorized cleanup; ask only about an unresolved target or a material keep/delete choice. Retained targets never block independent ones.

## Gates

- Deletion needs zero uncommitted files; branch deletion also no unpushed work beyond the delivery proof. A failed inspection never passes.
- Never `git worktree remove --force`; run it from the main repo root. Never remove an active worktree or stop builds, debuggers or interaction sessions.
- A removed worktree's global DerivedData only via `remove-worktree-derived-data.sh` after successful removal; don't pre-delete `build/`, `DerivedData` or `.build` of a removal target. Retained worktrees' caches only via `worktree-caches.py`; `--machine` follows scopes.md. Never delete `~/Library/Caches/org.swift.swiftpm`.
- Nested: list registered worktrees under the target (incl. `.subworktrees/`, nested `.claude/worktrees/`); each gets the same scope and gates without extra confirmation. Keep the parent if any is unrelated, retained or failing; clarify ambiguous ones together. Remove deepest-first from the main repo, DerivedData helper after each, parent last. For a sub-worktree target capture its root before moving to its parent.
- Unregistered nested repos are preserved, except [verified SwiftPM checkouts](references/retained-work.md#nested-swiftpm-checkouts).

## Execute

Record inspection results and legacy mappings in the receipt, then release leases of removal targets and explicitly kept idle worktrees. Check every command; report failures and continue independent targets.

```bash
python3 $HARNESS_ROOT/scripts/worktree-simulators.py release --worktree <path> [--worktree <path> ...]
cd <main-repo> && git worktree remove "$wt"   # $wt captured before cd
bash $HARNESS_ROOT/core/skills/cleanup-and-exit/scripts/remove-worktree-derived-data.sh "$wt"
git branch -D <branch>                       # only when deleting the branch
```

Run the DerivedData helper after every successful removal, including `ExitWorktree remove`; report its count and size. Report a refusal or unsupported location instead of bypassing it; skipped/failed/unsupported is not a zero-item success. Continue from `<main-repo>`; use an available `ExitWorktree` tool's matching remove/keep action, else report the main repo path without simulating a host exit or archiving the task.

## Verify and Close

- Per removal: exact directory absent and registration gone from `git worktree list --porcelain` (and branch, if deleted); command success or a merged PR is not the receipt. Then update the [queue](references/retained-work.md#pending-queue).
- Re-enumerate once at the end; report each original target as removed, already absent, retained (reason, queued, retry condition) or failed (error), with simulator/cache outcomes, archive paths, helper failures, busy/recreated caches and remaining actions. Count source worktrees and caches separately with measured `df` change, never summed nested estimates.
- A host-recreated worktree is a remaining target (report path and reason); don't delete it repeatedly.
- Say "all task worktrees removed" only when every target is verified absent; else "eligible worktrees cleaned; remaining directories: ...". Preserve unrelated worktrees and report them apart from retained task targets.
