---
name: source-command-review
description: Claude implementation of `/review` — a report-only correctness review with `/code-review`, then `/simplify` cleanup only when there is no must-fix, then the project's cheap check, with conclusions given directly in the conversation. Does not post PR comments, ship, or merge.
---

# /review (Claude)

1. Resolve `base_ref`: the user's choice first, otherwise the project convention or the remote default branch; ask when unsure. Scope is `<base_ref>...HEAD` plus staged, unstaged, and untracked changes.
2. Run `/code-review high`, report-only: do not edit the working tree or post PR comments. Pass `model: "fable"` explicitly to every finder / verifier it dispatches (reviewer agent definitions without a pinned model would otherwise inherit the Root's Opus). Use `xhigh` instead for concurrency / ownership, auth / security / privacy, persistence / schema migrations, cross-package public API, or 15+ product files.
3. Must-fix found: list the issues, skip cleanup, and stop.
4. No must-fix: run `/simplify` on the same scope (when the session model is not Opus, run it through a `general-purpose` subagent with `model: opus`).
5. Cleanup changed files: run the project's cheap check (e.g. `just check`); on failure revert this cleanup's changes and report.
6. Report the review verdict and findings (file:line), what cleanup changed, and the check result. Do not write a report file, commit, push, or open a PR.
