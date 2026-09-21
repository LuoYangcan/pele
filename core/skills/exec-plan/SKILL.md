---
name: exec-plan
description: Persist the result of native Plan mode or same-thread planning into a single-file ExecPlan. Required when work spans sessions/hosts, for a long-lived Goal, multiple implementation writers/worktrees, irreversible migration, audit/handoff, or when the user explicitly asks for a plan file; does not trigger when one Root can finish the same task in one pass, for short direct edits, pure Q&A, or meta configuration.
---

# ExecPlan

Resolve installed paths per the [host adapter](../../rules/host-adapter.md) before running helpers.

An ExecPlan is a cross-context execution handoff, not a precondition gate for every code task.

## When to write one

Write it when any of the following holds, after leaving Plan mode and entering Default, before the first source write:

- another task, host, long-lived Goal, or future session will continue the implementation;
- multiple implementation writers/worktrees need to share the full set of decisions;
- migration/rollback or another irreversible step needs its operation order persisted;
- the user asks for a spec, execution plan, or audit artifact.

A short-lived explorer, an independent plan review, ordinary implementation under the same Root, and a single self-contained worker prompt do not trigger it.

When any of the above flips from false to true during execution (you find the work will span sessions/hosts, a second writer/worktree appears, a step becomes irreversible, the user asks for an artifact), or substantive user decisions have accumulated during execution and there is a cross-session interruption risk (this session is not expected to finish, the user says they will continue another day / in another environment), immediately write a snapshot of the current final plan and maintain it per the update rules, unconstrained by the "before the first source write" timing.

## Path and format

Write it into the current worktree by default:

```text
.specs/<worktree-slug>.md
```

Use `"$HARNESS_ROOT/core/templates/exec-plan-template.md"`. Keep the plan itself a single file; do not create task/risk/amendment/decisions subtrees, and do not maintain two copies of status. Binary/measurement inputs such as Figma can go in a sibling `.specs/<slug>-assets/`; do not treat that as a plan state tree.

Required content:

1. the goal and its observable done state;
2. scope, non-goals, and hard constraints;
3. settled key decisions, interfaces/data flow, and the affected surface;
4. milestones, dependencies, and writer ownership;
5. verification, mandatory/optional review, immediate-authorization boundaries, risks, and rollback, plus any existing [plan review record](../plan-challenge/SKILL.md) (plan_ref, rounds, verdict, dispositions, and status);
6. currently known facts and outstanding work.

## Update rules

- Root is the only writer of the canonical ExecPlan; workers are read-only.
- When behavior, scope, architecture, constraints, or acceptance change, rewrite the corresponding canonical section and increment `revision`; do not append conflicting historical text.
- Bind reviewer input to this plan by absolute path, current `revision`, and file SHA-256; any update invalidates the old semantic/UI review.
- Track implementation progress with the host's checklist/Todo; the ExecPlan records only the milestone status that must be known across contexts.
- When the user cancels or replaces the goal, keep the existing source, do not destroy it on your own; mark the ExecPlan superseded at the top and link the replacement plan.
- `.specs/` may be cleaned up before ship; when it still holds long-lived project knowledge, migrate that into the project AGENTS/CLAUDE or trigger-on-touch docs first.

## Handoff input

The prompt for a worker/reviewer carries the ExecPlan's absolute path, the assigned scope, file ownership, base ref, and acceptance commands together. Do not just send "follow the plan".
