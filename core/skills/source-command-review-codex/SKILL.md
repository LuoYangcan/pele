---
name: source-command-review-codex
description: Codex backend for `/review`-style report-only correctness review followed by conditional branch cleanup. Captures structured output from a read-only `codex exec` reviewer first, runs `codex-simplify` only on a passing verdict, rechecks the cleanup diff, and renders the shared report; not for Claude, PR comments, shipping, or merging.
---

# Source Command Review Codex

Resolve installed paths per the [host adapter](../../rules/host-adapter.md) before running helpers.

Read [`../review-contract.md`](../review-contract.md) and [`../codex-simplify/SKILL.md`](../codex-simplify/SKILL.md) completely, then run the contract's `active-command` mode with the Codex backend below.

Do not call Claude `/simplify` or `/code-review`. If `codex exec` or `--output-schema` is unavailable, stop and report that the Codex reviewer backend is unavailable; do not silently downgrade to manual review. Use `codex exec` for the shared JSON contract; native `codex exec review` has its own review output format.

## Codex Backend

1. Freeze the fingerprint, changed paths, relevant untracked product paths, snapshot, and `pre_tree`. Create the report path from the shared contract.
2. Assemble a self-contained report-only prompt containing the frozen scope, applicable latest plan/ExecPlan and rules, the contract's reviewer checklist, the cleanup-follows notice, and the exact raw JSON schema. Pass it through stdin to one fresh read-only reviewer:

   ```bash
   python3 "$HARNESS_ROOT/scripts/model-policy.py" codex branch-review --repo "$repo" -- \
     -a never -s read-only exec -C "$repo" \
     --output-schema "$HARNESS_ROOT/core/skills/review-result.schema.json" \
     --output-last-message "$main_result" -
   ```

   When a risk gate in `review-contract.md` applies, add `--effort xhigh` before the wrapper's `--` separator only if the resolved policy effort is lower. Preserve a higher configured effort.

   Tell the reviewer to inspect only the frozen target and allowed direct caller/callee context. Repeat the contract's scanner/cache/network prohibitions. Put the base and changed paths in the prompt; `--base`, `--commit`, and `--uncommitted` belong to native review and are not used here.

   Capture stderr into `$scratch`; `--output-last-message` writes only the final structured message. If the command yields a session ID, wait until exit; running state or an empty temporary file is not failure. Apply the contract's timeout, one transport retry, and one repair-only JSON retry. A request-time `invalid_json_schema` is a backend configuration failure, not a reviewer result. Never infer empty findings from a plain-text summary.

3. Verdict `fail`: write the `not-run` cleanup JSON and publish `$main_result`.
4. Otherwise run `codex-simplify` on `<base_ref>...HEAD plus staged, unstaged, and untracked working-tree changes`. Require the shared cleanup result schema. Unchanged tree: publish `$main_result`.
5. Changed tree: start the shared build verification, write `$cleanup_diff`, recompute the fingerprint, and run the same command again with `--effort medium` (a risk-gated run keeps the main effort) and `--output-last-message "$temp_result"` as the contract's cleanup recheck. Its prompt carries `$cleanup_diff`, `$main_result`, the cleanup JSON, the post-cleanup fingerprint, applicable rules, and the schema. Same retries.
6. Route by the recheck: revert and publish `$main_result` on `must_fix`, otherwise publish `$temp_result`. Validate with `review-result.sh validate`, then publish with `review-result.sh publish active ...` using the snapshot and cleanup JSON. The backend—not the reviewer—writes canonical Markdown and the JSON sidecar. Join build verification and return `review-result.sh metadata` plus cleanup/build counts. On terminal failure, report the contract status and a bounded stderr tail; never publish partial output.

Both `codex exec` reviewers are report-only. Do not ask them to run cleanup, invoke this workflow again, apply fixes, or post comments.

## Entry Point

Invoke this workflow as `$source-command-review-codex`. Codex's reserved `/review` slash command remains available as the native report-only reviewer and is not overridden.
