---
name: source-command-ship
description: Commit the current task's changes, push the current branch, and open a GitHub PR. Use only when the user invokes `/ship-pr` or explicitly asks to commit, push, and open a PR. Does not merge, poll CI, or run code review.
---

# Ship

`/ship-pr` authorizes staging this task's changes, committing, pushing, and opening a PR. It does not authorize merge or unrelated cleanup.

## Preconditions

- `git fetch origin`. Stop on `main` / `master` / `dev`, unresolved conflicts, or an active merge / rebase / cherry-pick / revert.
- Take `base_ref` from the user, the project convention, or the remote default branch; never assume `dev`.

## Scope and commit

- Inspect all staged, unstaged, deleted, and untracked changes, and include only source, tests, docs, and config that clearly belong to this task. Stop and ask when a suspected secret or other user changes cannot be separated safely.
- Never stage secrets, credentials, `.env`, signing material, caches, build output, IDE state, `.specs/`, or `.reviews/` (leave them in place; do not delete them).
- When the task changes workflow, module boundaries, project structure, public contracts, tooling, or non-obvious constraints that agents need to know long-term, update the project docs in the same PR, integrated into the existing structure rather than appended at the end. Ordinary product / UI / bugfix work needs none.
- Stage explicit paths with `git add -A -- <paths>` and check `git diff --cached --check` and `--stat` before committing. One-line conventional commit matching repository style; no empty commits.

## Sync, check, push

- If an upstream other than `base_ref` exists, rebase onto it first, then `git rebase <base_ref>`. On conflict, stop and report the paths; never discard user work.
- Before push, run the repository's cheap check (e.g. `just check`). Stop on failure; do not auto-fix. `/ship-pr` does not repeat build / test.
- `git push -u origin HEAD --force-with-lease`; never plain `--force`.

## PR

If a PR already exists, return its link instead of creating a duplicate. Title: a suitable conventional commit subject. Body:

```markdown
## TL;DR

<what changed and why>

## What changed

- <reviewer-facing change>

## Test plan

- [x] <command actually run>
- [ ] <manual or CI check not run>

## Risk / Rollback

- **Risk**: <blast radius>
- **Rollback**: <revert or recovery path>
```

Add `## UI changes` for user-facing UI changes.

## Return

PR link, commit / push result, checks actually run, validation evidence this task already has, and unverified items. Optionally suggest `/code-review <PR> --comment` (Claude) or `pr-review` (Codex) as a next step; do not poll CI.
