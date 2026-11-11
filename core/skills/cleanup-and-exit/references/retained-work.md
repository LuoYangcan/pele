# Retained Work and Deferred Cleanup

This reference owns task-record archival, idle caches in retained task worktrees, and retries for previously authorized cleanup. It does not authorize a machine-wide sweep, new hooks, scheduled jobs, or deletion merely because a cache or worktree is old.

## Keep source; reclaim generated data separately

For every retained task worktree, inspect generated caches even when source is dirty or delivery is pending:

```bash
python3 "$HARNESS_ROOT/core/skills/cleanup-and-exit/scripts/worktree-caches.py" inspect --worktree <path>
python3 "$HARNESS_ROOT/core/skills/cleanup-and-exit/scripts/worktree-caches.py" clean --worktree <path>
```

Both commands accept repeated `--worktree`. `inspect` is read-only; a task cleanup request authorizes `clean` for its own retained linked worktrees, subject to explicit exclusions. Do not pass unrelated worktrees discovered by an inventory. The helper rejects primary checkouts; explicit machine-mode cleanup of a primary checkout still follows `scopes.md`.

The helper owns the executable allowlist: generated children of local `build/DerivedData` or `DerivedData`, and module/index children of tracked Swift package roots' local `.build`. It verifies registration, exact paths, Git ignore/tracked state, protected content, and current process/open-file activity before removal. Its report distinguishes removed, absent, retained, failed, and recreated paths. An activity-probe failure is retention, not proof of inactivity; a recreated directory is reported once rather than repeatedly deleted.

Preserve source, dependency checkouts/repositories/artifacts, `.xcresult`/`.xcarchive`, task records, shared SwiftPM caches, and all parent `build`/`DerivedData`/`.build` directories. Compiled `.xctest` products are rebuildable; actual test results remain protected. Do not kill tools, clear another worktree's cache, or broaden the allowlist with a project-name glob. Report rebuild/reindex cost and any busy or unsupported paths.

## Archive task records

Before removing a worktree, archive and verify its ignored task records and local settings even if Git status is clean.

When current HEAD is delivered, distinguish source changes from untracked task records with `git status --porcelain=v1 --untracked-files=all`:

- Tracked edits or any untracked file outside `.reviews/` and `.specs/`: retain the worktree and branch. Never reset, stash, or commit to satisfy cleanup.
- Only untracked `.reviews/`/`.specs/` records: copy them outside the worktree, verify every file or symlink against the copy, then remove only the verified original records. Require a fresh clean status before ordinary worktree removal. Nested Git content still follows the skill's nested-repository gates.

Store archives beneath `<git-common-dir>/cleanup-and-exit/backups/<worktree-id>/<UTC timestamp>/`, or the user's chosen backup destination outside all removal targets. Resolve the absolute common directory using Git, preserve relative record paths and local ignored task settings, and record original root/branch/HEAD in the receipt. Restrict the backup directory to the current user. Report its location; record archival is not permission to discard backups later.

If copying, verification, or subsequent clean-state checks fail, retain the worktree and report the failure. Restore original record paths from the verified archive if a later removal fails while the worktree remains. Never classify a whole dirty worktree as disposable merely because some changed files are logs.

## Remember authorized unfinished cleanup

Use the repository-local pending helper only after a real task cleanup request leaves an identified task worktree behind:

```bash
python3 "$HARNESS_ROOT/core/skills/cleanup-and-exit/scripts/pending-cleanups.py" add --worktree <path> --reason open-pr --pr <recorded-PR-URL>
python3 "$HARNESS_ROOT/core/skills/cleanup-and-exit/scripts/pending-cleanups.py" list --repo <repository>
python3 "$HARNESS_ROOT/core/skills/cleanup-and-exit/scripts/pending-cleanups.py" remove --repo <repository> --worktree <path>
```

Reasons may include pending delivery, dirty source, active work, or an unresolved inspection. The PR argument is optional; store it when known so branch renames or squash merges do not hide the delivery evidence. The helper stores versioned metadata at `<git-common-dir>/cleanup-and-exit/pending.json`, outside the worktree, with worktree/Git-directory identity, branch, observed HEAD, reason, and timestamp. It never deletes worktrees, caches, branches, or devices, and never queries remote services.

On the next authorized default task cleanup in that repository:

1. Read the queue without modifying it. Only entries whose registered root, Git-directory identity, and branch still match are additional deletion targets. Reconcile absent entries separately: remove their metadata only after verifying both directory and registration are absent. A changed identity is retained for clarification; a changed HEAD on the same task branch requires fresh delivery coverage, not an assumption that the earlier PR covers it.
2. Inspect each matching target once using the ordinary delivery, dirty-source, activity, nested-worktree, and simulator gates. A remembered PR or queue entry is a lookup hint, not permission or evidence that current work is finished.
3. Remove eligible targets and verify absence of both directory and registration before removing their queue entry. Keep unresolved entries with their current reason. A missing directory with a stale registration is not successful cleanup.

An explicit keep choice, or an explicit request to cancel deferred removal, suppresses deferred deletion and removes that target's pending entry; honor any cache exclusions separately. Cancelling the current cleanup performs no cache or queue mutation. `--repo` may display pending entries but remains read-only. `--machine` does not consume the worktree queue. Do not enroll unrelated worktrees, silently reset malformed state, or promise immediate post-merge execution: this is a retry on a later invocation, with no background watcher.

## Close with an actionable receipt

Report source-worktree results separately from generated-cache results. Include the actual paths retained, why they remain, whether they are queued, and what will make the next retry eligible. Include archived-record paths, helper failures, busy/recreated caches, and `df` change; do not sum nested estimates or imply that retained source means all its caches were retained.
