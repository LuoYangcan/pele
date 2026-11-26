---
name: plan-challenge
description: Independent adversarial review of the overall design of a new approach or large request, or of a major redesign; also used when the user explicitly asks for a plan review. Ordinary bug fixes, local refactors, small features and small config tweaks do not trigger it; writing a plan or touching multiple files does not trigger it by itself.
---

# Plan challenge

Root owns the plan and the final decisions; `plan-challenger` runs on the review-tier model (Claude: Fable; Codex: see the [model policy](../../../docs/model-policy.md)) in a fresh context and looks for counterexamples that would make the plan fail.

## When to trigger

- A new approach or large request that has to choose an overall product / technical route, or a major redesign of an existing system (cross-module responsibilities, core flows, state ownership, migration route); also when the user explicitly asks for a review.
- Ordinary bug fixes, local refactors, small features, UI fine-tuning, copy and small config tweaks do not trigger it.
- Dispatch once a complete candidate plan exists and before writing code (in native Plan mode, before `ExitPlanMode`). When the plan only changes locally, keep the existing conclusion; re-review only when the overall goal, key architecture, core flow or migration route changes.
- When the user explicitly skips it, note "plan review skipped" and continue.

## Dispatch

Dispatch one fresh, read-only `plan-challenger` that does not inherit Root's long argument. Inputs: the original request and the decisions the user has made, scope / non-goals, hard constraints and acceptance criteria, the complete candidate plan, the repo path and relevant evidence. When no independent agent or review-tier model is available, tell the user "the plan was not independently reviewed"; do not pass off self-review as the review.

## Reviewer contract

- First check whether added complexity is necessary: abstractions / config / state machines added for hypothetical extension, or duplicating an existing capability; re-validating trusted internal values, or tightening input without a basis; fallbacks, retries, confirmation steps or artifacts with no clear need. For each suspicious item ask: without it, which confirmed requirement or contract breaks? The plan's own "may be useful later" or "safer" is not a basis. The criteria are the same as `lean-diff`.
- Then check for missed requirements, factual premises, failure paths, dependency feasibility and whether acceptance is meaningful.
- Your own suggestions follow the same necessity standard: do not add frameworks or approvals to prevent over-design; do not pad findings, zero issues may pass.
- Read-only: no file writes, no plan edits, no commands, no further dispatch.

```yaml
verdict: READY | REVISE | NEEDS_INPUT | NEEDS_DECISION
findings:
  - id: PC-001
    severity: blocking | advisory
    scenario: <triggering scenario>
    consequence: <concrete failure>
    evidence: <file line / requirement / checkable counterexample>
    minimal_fix: <minimal fix or missing decision>
summary: <one sentence>
```

## Root convergence

Verify each finding: accept and revise, or reject with evidence; ask the user only about trade-offs they must decide. At most one full review plus one targeted recheck by the same reviewer; if the second round still has blocking findings, report the disagreement to the user as-is, and do not start another reviewer to reset the count. When showing the user the final plan, add a one-line review summary: issue count, main fixes, remaining disagreements.
