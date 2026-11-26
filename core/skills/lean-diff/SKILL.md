---
name: lean-diff
description: Judgment standard for a lean diff: comment noise, stacked patches that skip reuse, over-abstraction, validation without evidence, unauthorized fallbacks, swallowed errors, and unrelated changes in a bug fix. Use it to self-check before writing code and to tag issues in review. Typo, formatting, rename, comment-only / doc-only and lint-autofix diffs do not trigger it.
---

# lean-diff

Self-check each item before writing code; in review, tag every hit as an issue (`blocking` or `warning`, with file line and a one-line fix direction). Anything the user, the final plan, project rules or an authoritative external contract explicitly requires is not an issue.

## Comments

- Default to none; write only a why that still holds a year from now: hidden constraints, invariants, platform bugs, performance trade-offs.
- No comments explaining the what, no references to the current task / plan / issue number, no residue like `// removed`, no TODO without an owner. `// MARK: -` and pointers to project docs are fine.

## Reuse and abstraction

- First look for an existing method, type or helper to extend; removing a line beats adding one.
- Do not create a protocol / Manager / Service / config option / flag for only one or two call sites; delete single-caller wrapper classes that only forward calls and have no logic of their own.
- When merging similar branches, do not build an abstraction with no real axis of variation just for DRY.

## Defensive code

- A bug fix makes only the minimal necessary change: every behavior change must map to a confirmed root cause, a user requirement or a project rule. Once the root cause is confirmed, re-read the task's full diff and withdraw changes added only to test hypotheses.
- Internal calls and values the framework guarantees non-optional get no validation and no try/catch. Untrusted input is validated once, at the boundary where it first enters the system; each invariant has a single validation owner, and downstream does not repeat it.
- New validation must point to a user requirement, an authoritative contract or reproducible failure evidence; "it might happen" or "it's safer" does not count.
- Errors propagate or fail explicitly by default. Fallbacks, default values, lossy decoding and skipping bad data all need explicit authorization from the user or a product contract, with the degraded result spelled out. With fault evidence but no authorization, do not write the code; hand the user the triggering evidence, the consequence of not falling back and the proposed degradation to decide.
- `try?` / empty `catch` that swallows errors is blocking by default; when the requirement really calls for silence, state the stable business reason.
