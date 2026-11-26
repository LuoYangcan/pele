---
name: plan-first-delivery
description: Delivery checklist for coding tasks. Use when an implementation, bug fix, refactor, test addition or UI implementation will land Edit / Write, or when executing a settled plan. Covers asking when unclear, worktree, project rules, implementation approach, incremental commits, verification, independent acceptance for high-risk changes and the final report. Does not trigger in native Plan mode, pure Q&A, read-only diagnosis, status queries, meta configuration or the internal flows of slash commands.
---

# Plan-first delivery

## 1. Ask when unclear

- Before starting, restate the requirement as an acceptance-testable goal. Wherever the requirement, business terms, existing code behavior or design intent is unclear, not understood or open to more than one reasonable reading, ask the user first. Do not guess, and do not keep writing on unconfirmed assumptions.
- Settle facts that code, docs or git history can answer yourself; ask only when they cannot. When asking, separate "my understanding" from "open points", and give each question a leaning option with a reason; use the host's question tool (Claude: AskUserQuestion).
- Stop and ask likewise when new uncertainty appears mid-implementation: observable behavior, scope, architecture, acceptance criteria, and any fallback, default, conversion or skip that changes semantics or loses data. When unsure whether it matters, treat it as mattering. Pure implementation details such as naming and local structure are yours to decide.
- If the user changes the goal or acceptance criteria: pause writing, keep the current diff, update the plan, then continue. The new plan must keep every decision the user already made.

## 2. Before starting

- When not inside a git linked worktree, load `use-worktree` first.
- Following the rule index in the project AGENTS / CLAUDE, read in full the rule docs this change hits; rules are implementation and acceptance conditions.
- Overall designs and major redesigns get reviewed via `plan-challenge`; ordinary fixes and local changes do not trigger it.
- Write an ExecPlan (`exec-plan`) only for cross-session / cross-host work, multiple writers or irreversible migrations.

## 3. Implementation

- Root writes directly. On Claude the `implementer` runs on the same model as Root, so do not delegate by default; dispatch via `parallel-subagents` only when two or more non-overlapping write domains are worth parallelizing. On Codex the `implementer` runs on the implementation-tier model (see the [model policy](../../../docs/model-policy.md)), so non-trivial implementation may be delegated; Root owns boundaries, integration and verification.
- Before writing, apply `lean-diff`: no validation without evidence, no unauthorized fallback, no unnecessary abstraction or comments.
- After each independently verifiable feature unit, make one local commit in the task worktree ([commit-message](../../rules/commit-message.md)); when project rules require an explicit instruction to commit, follow them. Stage only that unit's paths, and do not commit `.reviews/` or `.specs/`. Push, PR, publishing, deleting data and other external or irreversible actions need separate user authorization.

## 4. Verification and acceptance

- Run one round of objective verification on the final candidate per [post-change-verify](../../rules/post-change-verify.md).
- When the final diff touches auth / permissions, PII / security, payments, persistence / schema / migration, public or cross-module contracts, or concurrency / cache consistency, or the user asks for independent acceptance: after verification passes, dispatch a fresh read-only `verifier`. Give it the user's goal, the final plan, `base_ref`, the changed paths, the path of a patch exported with `git diff --binary <base_ref>` into a temp directory, and the verification results. After blocking findings are fixed, the same verifier rechecks once; if it still fails, stop and align with the user. Skipping requires the user to explicitly accept the specific risk.
- Figma, animation, complex UI, or a user request for UI acceptance: dispatch `ui-reviewer` against the actually installed build.
- When the change affects workflow, module boundaries, toolchain or public contracts that agents need to know long-term, update the project docs; ordinary features and bug fixes do not write docs just to leave a trace.

## 5. Report

State the observable behavior delivered, the main changes, the verification actually run and its results, whether independent / UI acceptance triggered, whether docs were updated, and unverified items and remaining risks. Do not call it done without passing evidence.
