# Retained Work and Deferred Cleanup

Owns record archival, nested SwiftPM checkouts, idle caches of retained task worktrees and the pending queue. Authorizes no machine-wide sweep, hooks, scheduled jobs or age-based deletion.

## Archive Task Records

Before removing any worktree, archive its ignored task records and local settings, even when clean. With delivered HEAD, `git status --porcelain=v1 --untracked-files=all` decides: tracked edits or untracked files outside `.reviews/`/`.specs/` → retain worktree and branch; only untracked `.reviews/`/`.specs/` → copy out, verify every file/symlink against the copy, delete only verified originals, require a fresh clean status, then ordinary gates.

Destination: `<git-common-dir>/cleanup-and-exit/backups/<worktree-id>/<UTC timestamp>/` (absolute) or a user-chosen path outside all removal targets; owner-only, relative paths kept, original root/branch/HEAD in the receipt, location reported. Archival never authorizes later backup deletion. Copy, verify or re-check failure → retain and report; removal failing afterwards → restore records from the archive. Changed log files never make a dirty worktree disposable.

## Nested SwiftPM Checkouts

In a delivered worktree, Git-ignored worktree-local checkouts under `SourcePackages/checkouts` or `.build/checkouts`, with origin known from package state or lockfile, may go with whole-worktree removal (only) when each checkout and initialized submodule prints nothing for:

```bash
git status --porcelain=v1 --untracked-files=all --ignore-submodules=none
git rev-list --max-count=1 --all HEAD --not <verified-revision>...
```

Verified revisions: matching dependency pins, committed submodule gitlinks, verified upstream refs; local tags or an empty upstream range prove nothing. Otherwise retain the worktree and record the checkout path and reason.

## Idle Caches

```bash
python3 $HARNESS_ROOT/core/skills/cleanup-and-exit/scripts/worktree-caches.py <inspect|clean> --worktree <path> [--worktree <path> ...]
```

Run on every retained task worktree, even dirty or undelivered; `inspect` is read-only. A task cleanup request authorizes `clean` on this task's retained linked worktrees minus exclusions, never on unrelated inventory finds. The helper owns the allowlist and safety/activity checks (primary checkouts: `--machine` only); accept its retained/recreated results without killing tools, re-deleting or widening the allowlist. Report rebuild/reindex cost and busy/unsupported paths.

## Pending Queue

```bash
q=$HARNESS_ROOT/core/skills/cleanup-and-exit/scripts/pending-cleanups.py
python3 "$q" add --worktree <path> --reason <reason> [--pr <recorded-PR-URL>]
python3 "$q" list --repo <repo>
python3 "$q" remove --repo <repo> --worktree <path>
```

`add` only when a real task cleanup leaves an identified task worktree behind; reasons: pending delivery (`open-pr`), dirty source, active work, unresolved inspection. Pass `--pr` when known so renames and squash merges keep the evidence. State lives in `<git-common-dir>/cleanup-and-exit/pending.json`.

Next default cleanup in that repo:

1. `list` (read-only). Only `identity_status: match` entries join the targets; `changed` → retain for clarification; a new HEAD on the same branch needs fresh delivery proof. A queued PR is a lookup hint, never permission or proof.
2. Inspect with all ordinary gates.
3. `remove` only after directory and registration are both verified absent (`stale_registration` is not success), or on explicit keep or cancel of deferred removal (cache exclusions apply separately). Unresolved entries stay with their current reason.

Never silently reset malformed state. Retries run only on a later invocation (no watcher); never promise post-merge execution.
