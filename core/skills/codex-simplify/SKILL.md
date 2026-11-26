---
name: codex-simplify
description: Behavior-preserving cleanup for a Git diff in Codex. Use when the user asks to simplify, clean up, reduce, or quality-polish recent code, or when `source-command-review-codex` requests its cleanup phase. Produces fixed/skipped findings across reuse, simplification, efficiency, and abstraction altitude; does not perform correctness review, feature work, or PR actions.
---

# Codex Simplify

Clean a target diff without changing externally observable behavior. Review in parallel when allowed, but apply fixes through exactly one writer.

## Input

Use the caller's target; otherwise resolve `base_ref` from the user, project convention, or remote default branch and include `<base_ref>...HEAD` plus staged, unstaged, and untracked changes. Read applicable `AGENTS.md`, matching project rule documents, and the complete target diff before producing findings.

Inspect untracked files but do not edit them or create new files; record their cleanup findings as skipped so every cleanup edit stays revertible through Git.

## Phase 1: Read-Only Findings

For a small diff, cover all four dimensions in one read-only pass. Parallelize only when distinct file domains or costly independent questions justify it; keep each prompt scoped, use the configured explorer role, and respect the available concurrency slots. Cover these dimensions:

1. `reuse`: find existing APIs/helpers that replace new duplicate logic
2. `simplification`: reduce unnecessary branches, wrappers, comments, and indirection
3. `efficiency`: remove repeated work, needless allocation, and hot-path overhead
4. `altitude`: move logic to the existing abstraction level that already owns it; do not introduce a new architecture

Every review subagent must be read-only: no edits, file writes, Git mutation, stash, commit, or formatting commands. Return:

```yaml
- file: <path>
  line: <line>
  category: reuse | simplification | efficiency | altitude
  summary: <finding>
  evidence: <existing symbol or concrete diff evidence>
  proposed_change: <minimal cleanup>
  behavior_risk: low | uncertain | high
```

## Phase 2: Single-Writer Cleanup

The invoking agent or one designated writer must:

1. Deduplicate findings and verify their evidence in the repository.
2. Apply only low-risk, behavior-preserving changes.
3. Keep user changes outside the target untouched.
4. Record every applied item in `fixed` and every rejected item in `skipped` (file, line, category, summary; `skipped` adds a reason).

Skip a finding when it may change public API, user-visible behavior, persistence/state transitions, concurrency ordering, error/logging policy, test semantics, or package ownership. Also skip speculative abstraction, broad refactors, and changes that require product intent.

Do not let multiple writers edit overlapping files. If local rules require implementation delegation, send the deduplicated list to one worker and keep all reviewers read-only.

## Verification and Return

When called by `source-command-review-codex`, let the caller own build verification. When called standalone, follow the repository's required checks for the changed files; use meta-only validation when no production code changed. Do not skip project-required lint or add unrelated tests/builds.

Return:

```yaml
changed: true | false
fixed: [...]
skipped: [...]
verification: pass | fail | delegated | not-run
```
