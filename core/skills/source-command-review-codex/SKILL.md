---
name: source-command-review-codex
description: Codex backend for `/review`-style branch cleanup plus report-only correctness review. Runs `codex-simplify`, captures structured native `codex review` output, and renders the shared report; not for Claude, PR comments, shipping, or merging.
---

# Source Command Review Codex

Read [`../review-contract.md`](../review-contract.md) and [`../codex-simplify/SKILL.md`](../codex-simplify/SKILL.md) completely, then run the contract's `active-command` mode with the Codex backend below.

Do not call Claude `/simplify` or `/code-review`. If `codex exec review` or `--output-schema` is unavailable, stop and report that the Codex reviewer backend is unavailable; do not silently downgrade to manual review.

## Codex Backend

1. Freeze the fingerprint, changed paths, relevant untracked product paths, and pre-cleanup snapshot. Create the report path from the shared contract.
2. Run `codex-simplify` on `dev...HEAD plus staged, unstaged, and untracked working-tree changes`. Require the shared cleanup result schema.
3. If cleanup changed code, start the shared build verification.
4. Recompute the fingerprint after cleanup; this is the reviewer fingerprint. Assemble a self-contained prompt containing the frozen scope, applicable latest plan/ExecPlan and rules, cleanup result, and the contract's reviewer checklist + exact raw JSON schema. Pass it through stdin to one native Custom review target:

   ```bash
   codex -a never -s read-only exec review \
     -m gpt-5.6-sol \
     -c 'model_reasoning_effort="high"' \
     --output-schema "$HOME/.claude/skills/review-result.schema.json" \
     -o "$temp_result" -
   ```

   Use `xhigh` only when a risk gate in `review-contract.md` applies.

   Tell the reviewer to inspect only the frozen target and allowed direct caller/callee context. Repeat the contract's scanner/cache/network prohibitions. Do not combine the custom prompt with `--base`, `--commit`, or `--uncommitted`; those selectors are mutually exclusive with custom instructions.

   Capture stderr into `$scratch`; `-o` writes only the final structured message to the contract's `$temp_result`. If the command yields a session ID, wait until exit; running state or an empty temporary file is not failure. Apply the contract's 30-minute hard timeout, one transport retry, and one repair-only JSON retry.

5. Validate with `review-result.sh validate`, then publish with `review-result.sh publish active ...` using the snapshot and cleanup JSON. The backend—not the reviewer—writes canonical Markdown and the JSON sidecar. Join build verification and return `review-result.sh metadata` plus cleanup/build counts. On terminal failure, report the contract status and a bounded stderr tail; never publish partial output.

`codex exec review` is report-only. Do not ask the reviewer to apply fixes or post comments.

## Entry Point

Invoke this workflow as `$source-command-review-codex`. Codex's reserved `/review` slash command remains available as the native report-only reviewer and is not overridden.
