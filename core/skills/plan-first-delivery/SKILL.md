---
name: plan-first-delivery
description: Main code-delivery flow for Default mode. Use when a request will land Edit / Write / NotebookEdit, when executing a final plan that native Plan mode already produced for the same task, and when fixing bugs, refactoring, adding tests or implementing UI. Root (planning-tier strong model) owns the plan, decisions, integration and objective verification; non-trivial implementation is delegated to `implementer` (implementation-tier model) by default; subagents are also used for independent research and final independent acceptance. Does not trigger inside native Plan mode, pure Q&A, read-only diagnosis, status queries, meta configuration or slash commands.
---

# Plan-first delivery

Native Plan mode turns the requirement into a decision-complete plan; every formal plan is independently reviewed per [plan-challenge](../plan-challenge/SKILL.md) before it is finalized. The same Root in Default mode reuses valid review conclusions and takes over delivery, without a second plan, file-existence checkpoint or fixed approval turn. Model tiering: Root runs on the planning-tier strong model (Claude host: `/model fable`) and owns the plan, shared decisions, diff review, integration and verification; code writes are delegated by default to `implementer` on the implementation-tier model (Claude models live in agent Markdown; Codex uses the [model policy](../../../docs/model-policy.md)). Semantic verification must not use a weaker tier than implementation; recheck that constraint when changing either role.

## Entry routing

| Current state | Handling |
| --- | --- |
| Native Plan mode | Do not run this skill; write no code or plan files, and handle Figma style previews per the AGENTS entry routing. The final plan is the requirement source of truth for the same task |
| Default, user explicitly asks to execute the same task's final plan | Execute after reusing a valid review, or the user's explicit skip record, per `plan-challenge`; when no record exists, review the existing text first. Do not re-plan, do not copy it into a second plan file |
| Default, narrow goal with no decision that would change the outcome | Micro-changes only: single file or few lines, no new observable behavior, one unambiguous implementation; or the user's instruction is already specific enough that the implementation is uniquely determined and introduces no new observable behavior. Confirm entry points and impact scope read-only; use `update_plan` for multi-step tasks, then implement. New features, multi-file changes, multiple reasonable implementations or behavior changes, and any case where you cannot tell whether a decision of the next row's kind exists, are handled by the next row |
| Default, product behavior, scope, architecture, hard constraint or acceptance decisions remain | Use available planning/question tools per the [host adapter](../../rules/host-adapter.md). Clarify decisions that change the result; once the goal is clear and implementation is authorized, continue without a second GO turn merely because mode switching is unavailable |
| User explicitly asks for an implementation worker | Treat it as an implementation delegation; Root still owns boundaries, integration and final verification |

Pure Q&A, read-only diagnosis, status queries, changes to global rule / skill / hook / settings, and the internal flows of `/ship`, `/review`, `/pr-review` do not trigger.

`update_plan` only shows execution progress; it is not Plan mode and does not carry requirement truth.

## State machine

```text
DISCOVER (Plan/read-only)
  ├─ material decision → WAIT_INPUT → DISCOVER
  ├─ no-plan micro change → PLAN_READY
  └─ candidate complete → PLAN_CANDIDATE → PLAN_CHALLENGE
       ├─ revise / missing facts → DISCOVER (bounded by plan-challenge)
       ├─ material user choice → WAIT_INPUT
       └─ resolved / explicit skip → PLAN_READY
PLAN_READY + existing implementation authorization
  → EXECUTE
EXECUTE + next action needs fresh authority
  → AWAIT_ACTION_APPROVAL
  ├─ exact approval → EXECUTE (perform that action once)
  └─ denied/changed → DISCOVER or COMPLETE (blocked/cancelled)
EXECUTE + local implementation complete
  → INTEGRATE → VERIFY
  → [INDEPENDENT_REVIEW] [UI_REVIEW]
  → COMPLETE
```

Root always owns user interaction, the final plan, shared decisions, main-workspace integration, failure routing and the final report.

## Before implementation starts

1. Resolve the existing implementation authorization and the Plan preview boundary per the host adapter; in Default, a clear change request or instruction to execute the proposal authorizes local reversible changes and planned checks. When a formal plan exists, first check its review validity per `plan-challenge`; do not dispatch again when a valid conclusion exists.
2. When an Edit/Write will land and you are not in an isolated worktree, load `use-worktree` first; skip it when continuing the current task already inside a worktree. Meta configuration follows AGENTS' separate branch/worktree routing.
3. Record `base_ref="$(git rev-parse HEAD)"`, check for a dirty tree, and protect the user's existing changes.
4. If the project AGENTS/CLAUDE is already in context, check its trigger markers directly; otherwise read it. Load `scan-trigger-docs` when trigger-on-touch markers exist.
5. Load the architecture, language, Figma, documentation or platform skills this task actually hits. For Figma UI, check the planning-stage H5 preview and frozen artifacts per [figma-precise-extract](../figma-precise-extract/SKILL.md) and reuse them; when missing, complete them before the first source write. Do not load `architecture-first` when project rules, precedent or the authoritative final plan already settle the structure; return to a discovery/Plan decision only when an unresolved material boundary surprise appears during implementation.
6. Non-trivial code writes, and writes of any size that would add or widen validation/error handling/fallback, must load `lean-diff` and freeze the prompt field `validation_fallback_contract` before the first Edit; only micro-changes confirmed not to touch these semantics may skip it. The default value is `NONE`; new validation may be listed only when the user/final plan, project rules, an authoritative external contract or reproduction evidence proves it necessary. A fallback must in addition be explicitly authorized by the user/final plan, project rules or an authoritative product contract; a failure trace only proves a fault, it cannot authorize degrading. Each entry writes `site/kind`, `evidence`, `invariant_owner`; a fallback also writes `degraded_result` and `recovery_or_failure_owner`. With fault evidence but no authorization, stop before the first Edit and have Root show the user a `fallback_proposal`: the triggering evidence, the result without a fallback, the proposed degradation, the data/semantic loss, and the recovery-or-failure owner; the default recommendation is not to add it, only an explicit user choice may update the contract, and no reply is not authorization. This field is not a new plan or an on-disk artifact.
7. Write a single-file ExecPlan only when the persistence boundary of `exec-plan` is hit; an implementation that one Root can finish in one pass on one task does not land a plan file.

## Orthogonal gates

Judge each gate below separately; one task may hit zero or more:

| Gate | Triggers |
| --- | --- |
| `needs_worktree` | A source write will land and you are not in an isolated worktree |
| `needs_durable_plan` | Cross-session/host, multiple writers/worktrees, irreversible migration, long-lived Goal, audit, or the user asks for a plan file |
| `needs_parallel_write` | At least two implementation units with mutually exclusive write domains, where parallelism clearly shortens the critical path |
| `needs_independent_review` | The user asks for independent/full acceptance; or the final diff touches auth/permissions, PII/security, payments, persistence/schema/migration, public API/cross-module contracts, concurrency/cache consistency, or broad architecture boundaries; merging multiple writers also triggers it |
| `needs_ui_review` | Figma handoff, animation, complex UI, subjective visual judgment, or the user explicitly asks for UI acceptance |
| `needs_explicit_approval` | Actions requiring new permission, such as deleting/overwriting data, irreversible migration, external publishing/messaging/writes |

Once requirement ambiguity is resolved in Plan mode, "it was ambiguous once" does not auto-trigger independent review. Figma auto-triggers only the UI gate; unless a semantic risk is hit at the same time, do not start a second full pipeline.

### Strength of independent review

- `mandatory-risk`: auth/permissions, PII/security, payments, schema/persistence/migration, public API/cross-module contracts, concurrency/cache consistency, broad architecture boundaries, and fan-in from multiple writers. After objective verification PASSes, a fresh, read-only verifier must do the acceptance; without that capability, completion is blocked, and Root self-review is no substitute.
- `optional-requested`: the task itself carries none of the above risks and is enabled only because the user asked for independent/full acceptance. The user may explicitly revoke it later.
- "No review / I'll look at it myself" revokes only `optional-requested`. If the user wants to waive `mandatory-risk`, Root must first list the specific risks left without independent acceptance and obtain explicit acceptance of those risks; when a higher-level safety rule forbids the waiver, it stays blocked.

### Implementation authorization and action authorization

Accepting a plan, switching back to Default, or saying "Implement" authorizes only local, reversible source/doc changes within the current scope plus the planned verification. It does not authorize real data migration, deleting/overwriting data, production release, external messaging or any other irreversible/external write.

Before a `needs_explicit_approval` action, check whether existing authorization covers its exact target, parameters and impact. If it does, continue. Otherwise resolve the target, impact and recovery options, then obtain the missing authorization before acting. Changed scope requires fresh authorization; never perform a side effect first and ask afterwards.

## Execution and delegation

### Default: delegate implementation to implementer

1. For multi-step tasks use the available progress UI per the host adapter; single-step changes do not need it.
2. A decision-complete implementation goes to `implementer` by default: the prompt states the goal and completion conditions, exclusive ownership and the off-limits scope, the frozen shared interfaces, `validation_fallback_contract`, the project docs that must be read, the return format, and the permitted narrow-scope checks (frozen before dispatch, as in `parallel-subagents`).
3. Exceptions where Root writes directly: single-file, decision-free micro-changes; integration-level fixes; narrow fixes for verification failures; and hosts with no subagent (Root then implements serially). Root's direct writes are bound by the same `validation_fallback_contract`; shared manifests, public interfaces and final merged files are always written by Root.
4. After a worker returns, Root checks the actual diff, out-of-bounds writes, shared interfaces, the user's existing changes, and that added validation/fallback matches the contract item by item; code this task added but did not list must be removed, or go back to discovery with evidence — Root may not grant the authorization itself after the fact. Enter unified verification only after the necessary integration fixes; a worker's local checks are no substitute for final integration verification.
5. When the user adds local implementation details, update the execution checklist and continue; do not create amendment/status files.
6. When the user changes observable behavior, scope, architecture, hard constraints or acceptance criteria, pause the writer, keep the current diff, return to DISCOVER to produce a replacement plan, and review it per `plan-challenge` before entering PLAN_READY; do not roll back the user's changes on your own. The replacement plan must restate in full every substantive user decision accumulated so far, not just the delta; when an ExecPlan exists, sync it per the `exec-plan` update rules.

### Parallel delegation

When `needs_parallel_write` is hit, load `parallel-subagents` and hand mutually exclusive write domains to several `implementer` instances; every worker must know other writers exist concurrently and must not revert or overwrite their changes. Handle returns as in item 4 above.

### Incremental commits

- Local incremental commits are authorized by default and need no per-commit confirmation. When the user asks not to commit, or project rules forbid automatic commits or require an explicit commit instruction, follow that constraint.
- After each independently verifiable feature unit (implementation done and that unit's narrow checks pass), Root commits once inside the task worktree using [commit-message](../../rules/commit-message.md); do not batch several features until the end of the task.
- Stage only the unit's explicit paths; do not sweep in the user's existing changes, and do not commit `.reviews/` or `.specs/`. Workers do not commit; Root commits their diff after integration checks.
- Do not commit intermediate states or failed verification; fixes after final unified verification land as follow-up commits. Push, PR and publishing each check their own authorization.

## Lightweight judgment-call audit

`<repo-or-worktree>/.reviews/judgment-calls.md` is a local, append-only log of implementation judgments. It is not a requirement source of truth and does not replace user authorization.

- When the user, the final plan, project rules or direct precedent have not decided, and more than one reasonable implementation exists, Root first judges whether the choice is material. Anything that changes observable behavior, scope, architecture, hard constraints or acceptance criteria, and any added fallback, default, conversion, skip or discard that changes semantics or loses data, must stop to ask the user or return to Plan; do not log an entry and continue. When unsure whether it is material, treat it as material.
- A non-material, reversible implementation judgment that does not change business semantics may continue, but must be appended as one entry before completion (write it before dispatching review or after review returns, never inside the freeze window); when there are no such judgments, do not create the file. Mechanical naming, formatting and implementations uniquely determined by existing rules are not logged.
- Each entry writes only `Decision`, `Rationale`, `Impact and rollback`, with the heading `## YYYY-MM-DD HH:MM — <task>`; old entries must not be modified or deleted.
- Only Root writes the log. Workers return candidate judgments for Root to decide; they must not write the shared log directly.

`.reviews/` is a local delivery artifact; `/ship` must not stage or commit it. When the final reply has no entries, state explicitly "Judgment calls: none"; when there are entries, summarize the decisions and give the log's absolute path.

When the project AGENTS designates an equivalent local audit carrier (such as an iteration log), use the project path instead of the default file; the three fields and the append-only convention are unchanged.

## Documentation impact

Before final verification, check whether the actual diff changes the workflow, module boundaries, project structure, toolchain, public contracts or counter-intuitive constraints that agents need to know long-term. On a hit, load `agent-readable-docs` and update the corresponding project docs; ordinary product/UI/local bugfixes do not force doc writes just to leave a trace.

The final report's doc disposition is one of two: `NONE + specific rationale` (why the diff contains no long-term constraint change) or `UPDATED + path list` (paths must appear in `git diff --name-only $base_ref` or the untracked list).

## Verification

Run one round of relevant verification on the final candidate source per `rules/post-change-verify.md`. Root may run it directly; hand it to `command-runner` when the command is long, the log is large, or only a mechanical result is needed (Root runs it directly on hosts without that agent). Objective commands do not need a separate verification role.

When verification fails:

- Implementation problem: Root fixes narrowly and directly; large-scale rework is re-dispatched to `implementer` with the failure evidence; for the stale-rerun details see the failure routing in `rules/post-change-verify.md`;
- Environment/dependency problem: diagnose safely first; do not disguise it as a code failure or hand it to a new writer to rewrite;
- Two consecutive rounds of the same diagnosis with no progress: stop blind fixing and return to Plan or ask the user; retain existing implementation authorization unless the scope changed; native Plan mode remains read-only. When the same required gate accumulates 4 FAILs (whether or not the diagnosis changed), you must ask the user.

## Conditional acceptance routing

When `needs_independent_review` or `needs_ui_review` is hit, after objective verification PASSes read [references/review-binding.md](references/review-binding.md) in full (candidate identity freeze, fingerprint binding, verifier / UI reviewer launch and invalidation rules) before starting the corresponding acceptance. mandatory-risk cannot be replaced by Root self-review; a waiver requires explicit per-risk user acceptance per "Strength of independent review".

## Host fallback

- Codex / Claude have a native Plan: use the native mode and native question tools; do not pass `update_plan` off as Plan mode.
- No mode-switch tool: follow the host adapter; clarify material open questions and continue already-authorized implementation in Default.
- No subagent: Root executes serially; if independent review is a hard gate and no fresh reviewer capability exists, report the block explicitly and do not label self-review as independent acceptance.
- Non-interactive/unattended session: when required input or authorization is missing at WAIT_INPUT, PLAN_READY, AWAIT_ACTION_APPROVAL or a mandatory-risk block and cannot be obtained in this session, output the final plan / pending-approval action list and end in blocked state; never treat it as authorized on your own.
- Tool-name differences affect only the adapter; they do not change the state machine or the gates.

## User overrides

- "Just change it / no Plan" → execute directly when in Default mode and the goal is clear enough; verification is not skipped.
- "Write it yourself / no worker" → Root implements the whole task directly; integration and verification are unchanged.
- "Full acceptance / independent acceptance" → enable an independent verifier.
- "No review / I'll look at it myself" → skip only `optional-requested`; `mandatory-risk` follows the specific risk-acceptance rule above, and action-permission confirmation stays separate throughout.

## Completion conditions

The final reply must state separately: the observable behavior delivered, the main changes, the verification actually run and its results, whether independent/UI acceptance triggered, the judgment-call audit, the doc disposition, and unverified items / remaining risks. Do not call it complete without PASS evidence.

Items not triggered or empty may be merged into a one-line brief (e.g. "Independent/UI acceptance: not triggered; judgment calls: none; docs: NONE (no long-term constraint change)"). For a micro-change that is single-file, whose behavior matches an explicit user request, where needs_independent_review / needs_ui_review / needs_durable_plan / needs_explicit_approval are all unhit, with no judgment-call entries and doc disposition NONE: state only the change, the verification actually run and its results, and remaining risks, plus "Judgment calls: none"; report the rest only when triggered.
