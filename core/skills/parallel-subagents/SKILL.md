---
name: parallel-subagents
description: Hand independent read-only investigation or mutually exclusive write domains to subagents concurrently. Triggers when the user explicitly asks for parallelism, or when Root judges that parallelism clearly speeds things up and the task boundaries are decision-complete. Write tasks must not depend on each other and must not overlap in file ownership.
---

# Parallel subagents

Parallelism is an execution strategy, not a fixed process stage. Root always owns user interaction, the final plan, shared decisions, main-worktree integration, and the final report.

## When to parallelize

- Two or more mutually independent, time-consuming repo/docs investigation questions: explorers may run concurrently.
- Implementation decisions are already complete, two or more independent write domains exist, and concurrency clearly shortens the time: workers may run concurrently.
- The user explicitly asks for parallelism or for a specific subagent: split as the user asks, but still check the safety boundaries.

Run serially when: the shared API is still evolving, one task consumes another's new results, the same file would be modified, merge cost outweighs the concurrency gain, or a single Root can finish it quickly.

Use the installed role policy. Prefer a self-contained narrow prompt and no full-history fork when the task does not need conversation history; preserve the exact user constraints and required docs. Full-history forks are for tasks that depend on prior decisions. Bound returned summaries and do not start more agents than the host permits.

## Freeze before dispatch

Root spells out in the prompt:

- the goal, observable completion conditions, and relevant constraints;
- exclusive file or module ownership, and the off-limits scope;
- the frozen shared interfaces and dependencies;
- project docs that must be read;
- the return format and the narrow-scope checks it may run.

Every worker must know: it is not the only writer in the repo, and it must not revert or overwrite someone else's changes; on finding concurrent changes it adapts to the current file state, and on conflict it stops and reports.

Before dispatching write tasks, also freeze the handoff mechanism: direct fan-in of mutually exclusive files in a shared worktree, or a diff handoff from separate worktrees. Do not wait until the workers have finished writing to decide between commit, patch, or copying files.

## Isolation and ownership

- Read-only explorers can share a worktree and write no files.
- When the host can hand a separate worktree's uncommitted diff back to Root intact, write workers prefer separate worktrees; Root records their absolute path and `base_ref`.
- In a shared worktree, one file must have exactly one owner; a worker writes its own ownership directly, and Root does not edit those files at the same time.
- Shared manifests, public interfaces, the canonical plan, project-level config, and final merged files are written by Root only.
- Do not spin up fresh agents over and over to match mechanical task numbering; create an instance only for a real parallel boundary or an independence requirement.

## Worker handoff

Every write worker returns: the worktree's absolute path, `base_ref`/current HEAD, `git status --short`, the complete changed/untracked paths, the diff within its ownership, the narrow-scope checks and their results, and open items. It must not commit, merge, push, or open a PR on its own.

- Shared worktree: Root reviewing the current files against the returned list is enough; stop and handle any out-of-bounds path first.
- Separate worktree: prefer the host-native uncommitted diff handoff. On shared local disk, Root can read `git diff --binary <base_ref> -- <owned paths>` from the recorded worktree, check untracked/binary files separately, and then apply it to the main worktree.
- If the host can only hand off faithfully via commit/cherry-pick, get the user's explicit authorization for that Git mutation first; without authorization, do not pick this isolation mode. When untracked or binary files cannot be handed off losslessly, switch to mutually exclusive ownership in a shared worktree.
- Root may clean up a worker worktree only after confirming the main worktree is fully integrated; never delete the only copy first.

## Integration

1. Root collects each handoff and checks `base_ref`, changed paths, out-of-bounds writes, conflicts, and shared contracts.
2. Root integrates the diffs into the main worktree by the frozen mechanism, confirms untracked/binary files item by item, and makes the integration fixes needed.
3. Run the verification frozen in `rules/post-change-verify.md` once, on the post-fan-in final candidate only.
4. A change to the final source invalidates the corresponding verification and reviews; a change to the authoritative plan or design inputs invalidates the semantic/UI reviews. Rerun only the affected gates.

Workers may run the narrow-scope checks needed for a safe merge, but these do not replace the final integration verification, and workers do not run broad reviews on their own.
