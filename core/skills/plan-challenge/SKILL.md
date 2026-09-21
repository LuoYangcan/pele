---
name: plan-challenge
description: Independent adversarial review of a formal candidate plan before it is finalized, checking first for over-design, over-strict validation and over-protection. Covers native Plan, Default, architecture and meta plans; valid reviews are reused, and progress checklists or wording edits do not trigger.
---

# Plan challenge

Root owns the plan and the final decisions; `plan-challenger` independently looks for counterexamples that would make the plan fail. This skill is the single process owner for plan review. It does not replace the post-implementation verifier / UI review and adds no fixed user-approval turn.

## Entry and validity

- Review once Root has a complete candidate plan ready to choose or execute, before finalizing it with the user: before `ExitPlanMode` in native Plan, before writing from that plan in Default / meta. Option lists during exploration are not reviewed one by one; a draft that keeps a pending user trade-off may be shown when clearly marked as pending, and is not called the final plan.
- When the user asks to execute an existing plan, reuse its valid review; when there is no record, review the existing text once without writing a second plan and without asking again for implementation authorization.
- Do not manufacture a plan for a mechanical micro-change that never needed one; progress checklists, ordinary Q&A, wording revisions and the reviewer's own fix suggestions do not trigger. Only Root dispatches; reviewers / workers never start this flow recursively.
- A prior conclusion becomes invalid when the user goal, observable behavior, scope, architecture, hard constraints, acceptance criteria or key factual premises change; Root updates the complete plan and reviews again. Pure wording, execution progress or a transcription persisted without semantic change does not invalidate it.
- When the user explicitly asks to skip this plan review, record `SKIPPED` and continue within existing authorization; "just do it / no Plan / write it yourself" alone does not waive a plan that has already been formed. The waiver does not change post-implementation mandatory-risk acceptance or action permissions.

## Dispatch and inputs

Check actual capabilities per the [host adapter](../../rules/host-adapter.md) first. On first use dispatch a fresh, read-only `plan-challenger`: Codex `fork_turns="none"`, Claude a new independent Agent; it does not inherit Root's full analysis or a long argument meant to persuade the reviewer.

Use the planning-tier model: the Claude role inherits the planning Root's model; Codex resolves `plan-challenger` through the [model policy](../../../docs/model-policy.md). When the current session does not expose the custom role, use a fresh general-purpose subagent with the same read-only contract and the planning-tier model passed explicitly; do not borrow the verifier, which only reviews final code. When the required model is unsupported or there is no independent agent, mark `NOT_REVIEWED` and state the gap; a draft may be shown, but it cannot be claimed as passed, and implementation that depends on the review cannot continue unless the user explicitly skips it.

Root supplies the following complete inputs, writing `NONE` where the repo does not apply:

- the original request, accumulated user decisions, scope / non-goals, hard constraints and acceptance criteria;
- the complete candidate plan text, a unique `plan_ref` (task identifier + revision number) and `review_round`;
- the repo/worktree absolute path, the allowed search scope, relevant factual evidence and open uncertainties;
- on recheck, additionally the previous `plan_ref`, all findings, Root's disposition of each, and the complete revised text.

Freeze the supplied text and key inputs during review; when receiving the result, confirm that `plan_ref` and content still match the current candidate. Never reuse the same ref for different text. Do not create a plan file, hash artifact or persistent gate for this; when an ExecPlan exists, reuse its revision — the review itself does not trigger an ExecPlan.

## Reviewer contract

Read only the necessary project rules and directly relevant evidence, judge independently, and do not substitute Root's conclusions for facts. Do not write files, change the plan, run build/test/install, cause external side effects or dispatch further agents; when evidence is missing, say so instead of guessing.

First review whether added complexity is necessary, then check for missed requirements, factual premises, counterexamples/failure paths, dependency feasibility and whether acceptance is meaningful. A plan that achieves the goal does not mean every structure, check or protection in it deserves to stay.

| Primary check | Plan content to challenge |
| --- | --- |
| Over-design | Abstraction layers, protocols, configuration, state machines or general frameworks added for hypothetical extension; duplicating an existing capability; inflating a local need into an infrastructure overhaul |
| Over-strict validation | Re-validating trusted internal values or an invariant the upstream already established; tightening legal input without a contractual basis; escalating an unrelated optional failure into a full block |
| Over-protection | Fallbacks, swallowed errors, retries or recovery with no clear need; repeated confirmation of authorized reversible actions; artifacts, isolation, full verification or approval steps added for hypothetical risk |

For each suspicious addition ask: without it, which confirmed requirement, contract or proven behavior concretely breaks? The basis must come from the user, project rules, an authoritative contract or a verifiable fact; the candidate plan saying "needed", "may be useful later" or "safer" is not an independent basis. For code structure, validation or fallback, judge with the necessity, single-owner and degradation-authorization criteria in [lean-diff](../lean-diff/SKILL.md) sections 2/3; do not run its write flow, and do not treat the candidate under review as an approved final plan that is exempt.

When you find redundancy, prefer recommending deletion, merging, reuse or keeping the check at its real owner boundary, stating the concrete cost/behavior consequence and how the requirement is still met after the cut. A single caller or the mere existence of a check does not prove it redundant. Keep checks required at untrusted input boundaries, by independent authorization/ordering contexts, by real failures, and by hard constraints. When an existing mandatory rule looks redundant, only point out the conflict for Root; do not authorize its removal yourself.

The reviewer's own suggestions are held to the same necessity standard: do not add frameworks, check matrices or approval steps to prevent over-design, and do not list unrelated hypothetical risks as evidence gaps that must be filled. Style preferences and purely maintainability simplifications are `advisory`; only a concrete break of the goal, contract or behavior blocks. Do not pad findings; zero issues may pass.

Each finding uses a stable ID and gives the triggering scenario, the concrete consequence, the evidence (file line / requirement / checkable counterexample) and the minimal fix. Mark issues that break the goal or a hard constraint as `blocking`, the rest as `advisory`. Output:

```yaml
plan_ref: <echo verbatim>
verdict: READY | REVISE | NEEDS_INPUT | NEEDS_DECISION
findings:
  - id: PC-001
    severity: blocking | advisory
    scenario: <triggering scenario>
    consequence: <concrete failure>
    evidence: <checkable basis>
    minimal_fix: <minimal fix or missing decision>
coverage_gaps: []
summary: <one sentence>
```

`READY` requires no blocking finding, no evidence gap that prevents judgment and no pending user trade-off; advisory findings alone can still be `READY`. Use `REVISE` for clearly fixable blocking issues, `NEEDS_INPUT` for missing facts, and `NEEDS_DECISION` for trade-offs the user must decide. A recheck covers only the disposition of the original findings, the impact of the revision and newly introduced issues.

## Root convergence

1. Verify each finding: accept and revise, or reject with evidence; ask the user only for a material trade-off they must choose. Fill facts that can be gathered read-only yourself; do not dress missing facts up as user decisions.
2. Default to one full review plus one targeted recheck by the same reviewer. A revision, or a disputed rejection of a blocking finding, goes to the recheck; with no issues and unchanged text, converge directly. Do not automatically widen scope because the reviewer suggested an "improvement".
3. If the second round still has blocking issues, disputes or key evidence gaps, keep the status unresolved and report the specific issues and the next step; do not count rounds as a pass, start another reviewer to reset the count, or reopen full reviews indefinitely because this round's revision was substantive. Further review requires an explicit user request; authorized work that does not depend on the unresolved plan may continue.
4. After convergence, show the user the final plan and a short review summary: issue count, main fixes, remaining disagreements / skip reason. Keep the reviewer's original verdict and Root's accept/reject basis; do not rewrite self-review or rejected findings as the reviewer's pass.
5. Keep in the current task the `plan_ref`, rounds, reviewer verdict, per-item disposition and final status `READY / UNRESOLVED / SKIPPED / NOT_REVIEWED`. Mark `READY` only when all blocking issues and key gaps are closed; when an ExecPlan exists, carry this short record with the plan, and backfill a review across tasks when the record is missing. With existing implementation authorization and status `READY` or an explicit user `SKIPPED`, continue directly.

When a converged plan changes materially because of a later user request or new fact, start a new candidate review; revisions for issues found in the same round follow the two-round cap above. In a non-interactive environment missing required inputs, return a pending draft with the not-reviewed / not-converged reason; do not treat that as a waiver.
