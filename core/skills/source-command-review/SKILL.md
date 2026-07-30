---
name: source-command-review
description: Claude Code backend for the migrated `/review` workflow. Use in Claude when the user invokes `/review` or asks for branch cleanup plus correctness review. Runs Claude `/simplify` followed by Claude `/code-review`; does not apply to Codex, PR-comment review, shipping, or merging.
---

# source-command-review

Read [`../review-contract.md`](../review-contract.md) completely, then run its `active-command` mode with the Claude backend below.

If the host cannot invoke Claude `/simplify` and `/code-review`, stop and report that the Claude backend is unavailable. Do not use Codex commands or silently downgrade to manual review.

## Claude Backend

1. Inspect the target and create the report/snapshot paths from the shared contract.
2. Resolve `base_ref` from the project or remote default, then invoke Claude `/simplify` on `<base_ref>...HEAD plus staged, unstaged, and untracked working-tree changes`. Require the shared cleanup result schema.
3. If cleanup changed code, start the shared build verification.
4. Invoke Claude `/code-review` with high effort. Pass a self-contained prompt containing the shared reviewer input and cleanup result. Add the hard constraint `report-only; do not post PR comments`.
5. Join build verification, calculate the shared verdict, write the shared report, and return the compact summary.

Do not let `/code-review` edit the working tree or use its default GitHub-comment behavior.

The Claude `/review` command remains the public entry point. Do not expose this backend as Codex's review implementation.
