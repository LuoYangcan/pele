---
name: source-command-review
description: Claude backend for `/review`-style branch cleanup plus report-only correctness review. Runs `/simplify`, captures structured `/code-review` output, and renders the shared report; not for Codex, PR comments, shipping, or merging.
---

# source-command-review

Read [`../review-contract.md`](../review-contract.md) completely, then run its `active-command` mode with the Claude backend below.

If the host cannot invoke Claude `/simplify` and `/code-review`, stop and report that the Claude backend is unavailable. Do not use Codex commands or silently downgrade to manual review.

## Claude Backend

1. Freeze the fingerprint, changed paths, relevant untracked product paths, and pre-cleanup snapshot. Create the report path from the shared contract.
2. Invoke Claude `/simplify` on `dev...HEAD plus staged, unstaged, and untracked working-tree changes`. Require the shared cleanup result schema.
3. If cleanup changed code, start the shared build verification.
4. Recompute the post-cleanup fingerprint. Invoke Claude `/code-review` with Opus high effort; use highest effort only for a contract risk gate. Pass the frozen scope, applicable latest plan/ExecPlan and rules, cleanup result, reviewer checklist, scanner/cache/network prohibitions, and `review-result.schema.json`. Add `report-only; return raw JSON only; do not edit or post PR comments`.
5. Capture the final JSON in the contract's `$temp_result`. Apply the contract's 30-minute hard timeout, one transport retry, and one repair-only JSON retry. Validate and publish through `review-result.sh publish active ...`; the backend—not `/code-review`—writes Markdown and the JSON sidecar. Join build verification and return metadata plus cleanup/build counts.

Do not let `/code-review` edit the working tree or use its default GitHub-comment behavior.

The Claude `/review` command remains the public entry point. Do not expose this backend as Codex's review implementation.
