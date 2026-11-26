# Repository Inventory and Machine Cache Cleanup

Neither mode widens task/queue authorization. Repo = toplevel of `<path>` (default cwd); `--machine` outside a repo covers global caches only and says so. Validating an implementation of these modes stays read-only unless the user separately asked to clean the live machine; test mutation on disposable fixtures.

## `--repo [path]`

Strictly read-only (no fetch, prune, stash, branch switch, queue, archival or simulator changes); helpers only via `inspect`/`list`. Cover every registered worktree (incl. external Codex and nested Claude paths); list missing directories, stale registrations and pending entries separately. Per directory:

- branch/HEAD, dirty count, upstream/ahead, delivery per the SKILL.md proof (remote-tracking refs may be stale; unknown is not delivered);
- `du -sk` and largest caches, parents and children never summed (APFS clones make totals estimates, not promised gains);
- simulators from `worktree-simulators.py inspect`, legacy `.claude/sim-udid*` and `xcrun simctl list devices -j` (UDID, runtime, state, last use, size); a custom name or old last use is a candidate, not ownership;
- descendant worktrees, ignored records/config, unregistered nested repos, SwiftPM checkout eligibility.

Group as eligible (delivered, clean), retained (dirty/undelivered) and rebuildable cache candidates, plus a simulator table with association evidence and shared/unresolved status. Inventory never authorizes its suggestions.

## `--machine [--repo path]`

Before acting, show `df -k` and each candidate's exact path, size and impact; the mode authorizes eligible cleanup without a confirmation round, within user exclusions or narrower choices.

| Candidate | Check / impact |
| --- | --- |
| `~/Library/Developer/Xcode/DerivedData/<entry>` | Each entry's `info.plist` `WorkspacePath` (other repos possible); shared module/SDK caches identified individually; build/index regenerate |
| `~/Library/Developer/Xcode/iOS DeviceSupport/<entry>` | Exact device/OS entries, skip in-use; symbols re-prepared on next device debug |
| Selected repo's worktrees: `build/DerivedData`, local `DerivedData`, package `.build` | Verified generated, Git-ignored, no tracked files; never the worktree or whole `build/`; keep test results, logs, config, dependency-checkout changes; dirty worktrees keep source |

Excluded (inventoried only on request): Archives/dSYMs, exports/IPAs, `.xcresult`, `.reviews`, source checkouts, simulator devices/data/runtimes, `~/Library/Caches/org.swift.swiftpm`, other repos' build trees, arbitrary system caches. Deleting simulators needs explicit device/task scope plus the SKILL.md association checks; removing runtimes needs an explicit choice and Xcode's management interface, never the filesystem.

1. Snapshot candidates as resolved absolute paths; drop unknown/out-of-scope ones; no project-name globs. Check builds, indexing and device debugging (process cwd, absolute output paths); keep shared caches unless activity is ruled out.
2. Task worktree caches keep their SKILL.md helpers and guards; this mode may additionally delete individually inventoried global entries whose source worktree remains.
3. Recheck activity right before each deletion; skip and report in-use or recreated targets; never kill builds or re-delete.
4. Delete individually (partial = failed); verify absence, leave recreated caches, rerun `df -k`; report removed/already absent/retained/failed counts, actual space change and retained paths with reasons.
