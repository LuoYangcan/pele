# Repository Inventory and Machine Cache Cleanup

These modes do not expand the default task/pending-worktree authorization. Resolve the repository with `git -C <path> rev-parse --show-toplevel`; its `git worktree list --porcelain` is the inventory source. Omitted repository path means cwd. `--machine` outside a repository still covers global caches; report that no local repository was included. Retained task caches and same-repository pending retries are defined in [retained-work handling](retained-work.md).

## `--repo [path]`: Read-only Inventory

Inspect all registered worktrees, including external Codex paths and nested Claude paths. Report missing directories, stale registrations, and pending-cleanup identity/state separately. Never fetch, prune, stash, switch branches, update the queue, archive records, shut down a simulator, or delete anything in this mode. Both new helpers may be used only in their read-only `inspect`/`list` modes here.

For each existing directory collect:

- Path, branch/HEAD, dirty entry count, upstream/ahead state and verified delivery status. Missing upstream or failed remote lookup means unknown, not delivered. Apply the task workflow’s delivery proof before recommending deletion; local remote-tracking refs may be stale.
- `du -sk` size and largest cache directories. Measure parents and children separately but do not add overlapping totals. APFS clone/shared blocks mean apparent totals are estimates, not promised free-space gains.
- Pooled-simulator leases, legacy `.claude/sim-udid*` registrations and helper output from `scripts/worktree-simulators.py inspect --worktree <path>`. Cross-reference all devices from `xcrun simctl list devices -j`; include UDID, runtime, state, last use and size. A custom name or old last-use date is only a candidate, not proof of task ownership.
- Descendant worktrees, ignored task records/config and unregistered nested repositories. Apply the main skill's SwiftPM checkout checks when assessing eligibility for whole-worktree removal.

Show three categories: eligible delivered/clean worktrees; retained dirty or undelivered worktrees; rebuildable cache candidates. Simulators are a separate table with association evidence and shared/unresolved status. A full-repository inventory is not authorization to execute its suggestions.

## `--machine [--repo path]`: Clean Rebuildable Caches

Start with `df -k` and a concrete inventory below. Present the exact paths, sizes and impact before acting in the same run; the explicit mode already authorizes eligible cache cleanup, so do not add a fixed confirmation round. Preserve exclusions or narrower choices from the user.

| Candidate | Verification and impact |
| --- | --- |
| `~/Library/Developer/Xcode/DerivedData/<entry>` | Inspect each exact entry and its `info.plist`/`WorkspacePath`; may include other repositories. Build/index data regenerates. Shared module/SDK cache entries must be identified individually. |
| `~/Library/Developer/Xcode/iOS DeviceSupport/<entry>` | List exact device/OS entries. Symbol support may need to be prepared again during device debugging. Skip entries currently in use. |
| Selected repository’s registered worktrees: `build/DerivedData`, local `DerivedData`, package `.build` | Delete only verified generated, Git-ignored cache directories without tracked files; never the parent worktree or its whole `build` directory. Preserve test results, task logs, configuration and source changes inside dependency checkouts. Dirty source worktrees may retain their source while these caches are cleaned. |

Do not include Archives/dSYMs, exports/IPAs, `.xcresult`, `.reviews`, source checkouts, simulator device data or runtime images, shared `~/Library/Caches/org.swift.swiftpm`, other repositories’ local build trees, or arbitrary system caches by default. Inventory those separately only when requested. Deleting simulators needs explicit device/task scope and the association checks in the main skill; `--machine` alone never erases app/login data. Runtime removal needs an explicit choice and Xcode’s supported management interface, not filesystem deletion.

### Execute and Verify

1. Capture the candidate list before mutation. Resolve symlinks, use absolute paths, and exclude unknown/out-of-scope targets; never glob-delete by project name. Check active builds, indexing and device-debugging processes against each candidate, including process cwd and absolute output paths. Retain shared caches while related activity cannot be ruled out.
2. Whole global DerivedData entries for removed task worktrees still use `remove-worktree-derived-data.sh`. Retained task worktrees use only the exact local children selected by `worktree-caches.py`; do not weaken the removed-worktree helper's guard. This explicit machine mode also permits deleting individually inventoried global entries while their source worktrees remain.
3. Recheck activity immediately before each removal. If another process starts using or recreating a directory, stop deleting that target, report it as active/recreated, and continue independent candidates. Never kill a build or repeatedly delete its output to complete cleanup.
4. Delete eligible paths individually; record errors without treating a partial deletion as success. Verify exact path absence, leave any newly recreated cache intact, then record `df -k` again. Finish with removed/already absent/retained/failed counts, actual available-space change and concrete retained paths with reasons.

Running either mode to validate an implementation must remain read-only unless the user separately asked to clean the live machine. Test mutation logic using disposable fixtures.
