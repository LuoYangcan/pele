---
name: source-command-ship
description: Commit pending work, push the current branch, and open a GitHub PR for `/ship` or `/openpr`. Use only when the user invokes those commands or explicitly asks to commit, push, and create a PR. Does not merge, poll CI, or run code review.
---

# Ship

Explicit `/ship` or `/openpr` authorizes staging the current task, committing, pushing, and opening a PR. It does not authorize merge or unrelated cleanup.

## Preconditions

Run:

```bash
git status --short --branch
git branch --show-current
git fetch origin
```

Stop on `main`, `master`, or `dev`, unresolved conflicts, or an active merge/rebase/cherry-pick/revert.

## Inspect and scope

Inspect staged, unstaged, deleted, and untracked changes:

```bash
git diff --stat
git diff
git diff --cached --stat
git diff --cached
git ls-files --others --exclude-standard
```

- Include only source, tests, docs, and config that clearly belong to the current task.
- Preserve a coherent staged boundary. Otherwise create one cohesive commit; split only genuinely independent changes.
- Never stage secrets, credentials, `.env`, signing material, caches, build output, IDE state, `.specs/`, or `.reviews/`.
- Temporary plan/review artifacts are preserved by default and simply excluded from staging. Delete them only when the user asks for cleanup.
- Stop and ask if a suspected secret or unrelated user change cannot be separated safely.

## Final docs check

Inspect `origin/dev...HEAD` plus working-tree changes. Project agent docs need sync only when the task changes agent-facing workflow, module boundaries, project structure, public contracts, tooling, commands, SDK setup, or non-obvious constraints.

New targets/packages/subsystems, cross-platform contracts, endpoint families, or signing/build-chain changes require a concrete docs decision. Ordinary product/UI/bugfix code normally needs no docs update. If required docs are missing, propose exact paths and outline; edit and commit only after user approval. When editing docs, load `agent-readable-docs` and follow its rewrite rules: integrate new content into the document's existing structure, never just append it at the end.

## Commit

Stage explicit paths with `git add -A -- <paths>`. Before every commit run:

```bash
git diff --cached --check
git diff --cached --stat
git diff --cached
```

Use a concise one-line conventional commit matching repository style. Do not create an empty commit. Afterward, require that remaining visible changes are intentionally excluded artifacts or user changes.

Confirm the branch has commits ahead of the base:

```bash
git log --oneline origin/dev..HEAD
```

## Sync and check

If an upstream other than `origin/dev` exists, rebase onto it first; then run:

```bash
git rebase origin/dev
```

On conflict, stop and report conflicted paths. Never resolve by discarding user work.

After rebase, run the repository's standard cheap check before push. For `某 iOS monorepo`:

```bash
just check
```

Stop on failure; do not run auto-fix unless asked. `/ship` does not repeat build/test; final delivery evidence or CI owns those checks.

## Push and PR

Push safely:

```bash
git push -u origin HEAD --force-with-lease
```

Never use plain `--force`. Use base `dev` unless the repo or user specifies another base.

PR title: use a good leading conventional commit subject, otherwise synthesize one from the diff.

PR body:

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

Add `## UI changes` for user-facing UI. If a PR already exists, return its URL rather than creating a duplicate.

## Return

Return the PR URL, commit/push result, checks actually run, earlier validation evidence supplied by the current task, and any unverified item. Mention `/pr-review` as an optional next action; do not poll CI.
