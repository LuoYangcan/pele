---
name: source-command-review
description: Claude backend for `/review`-style report-only correctness review followed by conditional branch cleanup. Captures structured `/code-review` output first, runs `/simplify` only on a passing verdict, rechecks the cleanup diff, and renders the shared report; not for Codex, PR comments, shipping, or merging.
---

# source-command-review

Resolve installed paths per the [host adapter](../../rules/host-adapter.md) before running helpers.

Read [`../review-contract.md`](../review-contract.md) completely, then run its `active-command` mode with the Claude backend below.

If the host cannot invoke Claude `/simplify` and `/code-review`, stop and report that the Claude backend is unavailable. Do not use Codex commands or silently downgrade to manual review.

## Claude Backend

1. Freeze the fingerprint, changed paths, relevant untracked product paths, snapshot, and `pre_tree`. Create the report path from the shared contract.
2. Invoke Claude `/code-review` with Opus high effort; use highest effort only for a contract risk gate. Pass the frozen scope, applicable latest plan/ExecPlan and rules, reviewer checklist, the cleanup-follows notice, scanner/cache/network prohibitions, and `review-result.schema.json`. Add `report-only; return raw JSON only; do not edit or post PR comments`. Capture the final JSON in `$main_result` with the contract's timeout, one transport retry, and one repair-only JSON retry.
3. Verdict `fail`: write the `not-run` cleanup JSON and publish `$main_result`.
4. Otherwise invoke Claude `/simplify` on Opus on `<base_ref>...HEAD plus staged, unstaged, and untracked working-tree changes`: inline when the session model is Opus, otherwise through a `general-purpose` subagent with `model: opus` that returns only the cleanup JSON. Require the shared cleanup result schema. Unchanged tree: publish `$main_result`.
5. Changed tree: start the shared build verification, write `$cleanup_diff`, recompute the fingerprint, and invoke `/code-review` again at medium effort as the contract's cleanup recheck with `$cleanup_diff`, `$main_result`, the cleanup JSON, the post-cleanup fingerprint, and the schema. Capture the final JSON in `$temp_result` with the same retries.
6. Route by the recheck: revert and publish `$main_result` on `must_fix`, otherwise publish `$temp_result`. Validate and publish through `review-result.sh publish active ...`; the backend—not `/code-review`—writes Markdown and the JSON sidecar. Join build verification and return metadata plus cleanup/build counts.

Do not let `/code-review` edit the working tree or use its default GitHub-comment behavior.

The Claude `/review` command remains the public entry point. Do not expose this backend as Codex's review implementation.
