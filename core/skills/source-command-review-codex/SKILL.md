---
name: source-command-review-codex
description: Codex `/review`-style workflow — a read-only `codex exec` reviewer does a report-only correctness review, `codex-simplify` cleanup runs only when there is no must-fix, then the project's cheap check, with conclusions given directly in the conversation. Not for Claude, PR comments, shipping, or merging.
---

# Review (Codex)

Invoke as `$source-command-review-codex`; Codex's built-in `/review` stays as is. Do not call Claude's `/code-review` or `/simplify`.

1. Resolve `base_ref`: the user's choice first, otherwise the project convention or the remote default branch; ask when unsure. Scope is `<base_ref>...HEAD` plus staged, unstaged, and untracked changes.
2. Through stdin, give one fresh read-only reviewer the scope, changed paths, applicable project rules, and the review checklist (correctness, error paths, concurrency, performance hot spots, consistency with rules and plan, package boundaries, leftover test / debug code). Require report-only output listing must-fix items and suggestions by file:line (`tmp="$(mktemp -d)"`):

   ```bash
   python3 "$HARNESS_ROOT/scripts/model-policy.py" codex branch-review --repo "$repo" -- \
     -a never -s read-only exec -C "$repo" --output-last-message "$tmp/review.md" -
   ```

   For concurrency / ownership, auth / security / privacy, persistence / schema migrations, cross-package public API, or 15+ product files, add `--effort xhigh` before the `--` (keep the policy value when it is higher).
3. Must-fix found: list the issues, skip cleanup, and stop.
4. No must-fix: run `codex-simplify` on the same scope.
5. Cleanup changed files: run the project's cheap check (e.g. `just check`); on failure revert this cleanup's changes and report.
6. Report the review verdict, cleanup changes, and the check result. Do not write a report file, commit, push, or open a PR.
