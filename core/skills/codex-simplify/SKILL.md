---
name: codex-simplify
description: Behavior-preserving cleanup for a Git diff in Codex. Use when the user asks to simplify, clean up, reduce, or quality-polish recent code, or when `source-command-review-codex` requests its cleanup phase. Produces fixed/skipped findings across reuse, simplification, efficiency, and abstraction altitude; does not perform correctness review, feature work, or PR actions.
---

# Codex Simplify

Clean a target diff without changing externally observable behavior. Review in parallel when allowed, but apply fixes through exactly one writer.

## Input

Use the caller's target. Default to `dev...HEAD` plus staged, unstaged, and untracked changes. Read applicable `AGENTS.md`, trigger-on-touch documents, and the complete target diff before producing findings.

If no caller supplied a pre-cleanup snapshot, create one under `.reviews/` using the naming and snapshot commands in [`../review-contract.md`](../review-contract.md).

Inspect untracked files but do not edit them or create new files; record their cleanup findings as skipped because the tracked patch snapshot cannot restore their previous contents.

## Phase 1: Read-Only Findings

When subagents are available and allowed, run up to four read-only explorer passes. Otherwise perform the same passes serially:

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
4. Record every applied item in `fixed` and every rejected item in `skipped` using the schema in [`../review-contract.md`](../review-contract.md).

Skip a finding when it may change public API, user-visible behavior, persistence/state transitions, concurrency ordering, error/logging policy, test semantics, or package ownership. Also skip speculative abstraction, broad refactors, and changes that require product intent.

Do not let multiple writers edit overlapping files. If local rules require implementation delegation, send the deduplicated list to one worker and keep all reviewers read-only.

## Verification and Return

When called by `source-command-review-codex`, let the caller own build verification. When called standalone, run only the repository's required post-change build command; do not run lint, tests, or format-fix unless requested.

Return the shared `fixed` and `skipped` lists plus:

```yaml
changed: true | false
snapshot: <path>
fixed: [...]
skipped: [...]
verification: pass | fail | delegated | not-run
```
