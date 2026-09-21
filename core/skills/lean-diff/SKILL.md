---
name: lean-diff
description: Lean-diff judgment standard covering comment noise, patchwork bloat, over-abstraction, speculative or duplicate validation, and defensive fallback. Use in write mode before edits and in review mode when tagging issues. This skill owns local copy/paste, TODO, validator, fallback, silent-catch, and premature-abstraction signals; they do not trigger architecture-first unless diagnosis requires an unresolved durable boundary change. Skip typo, format, rename, comment-only doc, and lint-only diffs.
---

# lean-diff

The **lean judgment standard** for writing and reviewing code:

1. Comment noise
2. Stacking patches without deleting the old / without reusing what exists
3. Over-defensive code (swallowed errors / redundant unwraps / fake fallbacks)

The implementation owner self-checks in **write mode** before writing code; `verifier` or `/review` lists issues in **review mode** when reviewing code. Both sides use the same issue_type set.

This skill handles these local anti-patch signals directly; the appearance of a branch, flag, copy/paste, fallback, or TODO does not automatically escalate into an architecture decision.

## How to use

### Write mode

Run through §Self-check list (write) before every Edit / Write. Any hit → change it back before landing.

### Review mode

Scan the complete diff under review and check each change's necessity; for a bug fix, check the basis for each behavior change against the §3 "Default contract" — passing a correctness check does not replace the necessity review. Emit a structured issue for each hit, per the §issue_type tables:

```yaml
- severity: blocking | warning
  issue_type: <type name from the table>
  file: <path/to/file.swift>
  line: <if available>
  description: <one sentence stating the problem>
  suggested_fix: <fix direction if obvious; not required>
```

## Does not trigger

Skipped cases (these diffs do not trigger this skill's standard):

- typo / single-character fix / rename / formatting adjustment
- comment-only / doc-only changes (the comment is itself the object of review; do not use this skill to review comments again)
- changes auto-fixed by a lint tool (the tool already backstops them)
- code deletion (this skill covers the quality of added / modified code; deletion inherently satisfies "prefer removing code")

## Three judgment standards

### 1. Comments

#### Default to no comment

Good naming + types already state the what. Write a comment **only when the WHY is non-obvious** — a hidden constraint, an invariant, a workaround for a specific bug, behavior that would confuse the reader.

#### Comments not to write (delete on sight / tag an issue on sight)

| issue_type | Trigger | Example |
|---|---|---|
| `verbose-comment` | explains the what (what the adjacent code does) | `// add user to the list` right above `users.append(user)` |
| `task-bound-comment` | references the current task, a plan section, an issue/fix number, or a temporary checklist | `// to fix #123`, `// the plan requires...`, `// task-7` |
| `removal-marker` | deletion residue | `// removed`, `// renamed from X` |
| `stale-todo` | a TODO with no deadline / no owner | `// TODO: optimize later` |

#### Exceptions (**not an issue**)

- `// MARK: -` (Swift section markers, IDE-friendly)
- pointer comments like `// see docs/x.md` that reference project docs or a third-party issue link

#### Contrast: write why, not trace

`task-bound-comment` bans the process trace of "why this line was touched at the time". Plans, tasks, PRs, and fix numbers drift or disappear; the comment should be rewritten as durable causality.

But **why comments are encouraged**, provided they state **causality that does not drift over time**: business constraints / system behavior / historical bugs / performance trade-offs. The test: show the comment to someone a year from now who does not know this task existed — can they still understand it?

| Banned (trace, goes dead) | Encouraged (why, durable) |
|---|---|
| `// the plan requires UTC` | `// the server stores in UTC; local conversion happens in the presenter layer` |
| `// retry added by this task` | `// iOS 17.4 NWConnection can ECONNRESET on the first handshake; retry once` |
| `// guard added to fix #1234` | `// pendingAttachments can be cleared externally during the dismiss animation; the nil check is required` |
| `// task-7 requires hiding it` | `// the composer is visually misaligned above the picker; hiding is controlled by caller-side scope` |
| `// requested by the user in review` | `// main-thread layout re-entrancy retriggers SnapKit recalculation → must be async` |

The rule is not "write fewer comments", it is "delete the part that will go dead, keep the part that will help people long-term".

#### Severity rules

- Default **warning**
- ≥ 5 hits in one file → escalate to **blocking** (that whole file is using comments as a commit message; it must be sent back)

### 2. Patch stacking

#### Four questions before writing code

- Can an existing method do it with an extra parameter?
- Can an existing type do it with an extra field?
- Can an existing helper / extension be reused?
- Can three similar branches collapse into one? Do not build an abstraction with no real axis of variation just for DRY.

Removing one line beats adding one. When adding is unavoidable, prefer adding at an existing site over creating something new.

#### Issue type

| issue_type | Trigger | severity |
|---|---|---|
| `patchwork-bloat` | creates a new method / type / file, but grep shows an existing reusable entry point; the user / final plan did not ask for a new one | warning |
| `over-abstraction` | introduces a new protocol / Manager / Service / config parameter / feature flag / **single-caller wrapper class**, but the user / final plan did not ask for it and there are only 1-2 callers today | warning |

How to spot a "single-caller wrapper class": a new class (commonly named `XxxCoordinator` / `XxxService` / `XxxManager` / `XxxHelper`) that just relays an existing API — init only stores dependencies, methods only forward calls, with **no** extra logic of its own (retry / state transitions / cross-call state / orchestration of several dependencies), and grep shows a single caller. Such a wrapper gives unit tests no seam (there is only one use anyway) and reuses nothing; it is pure added indirection → over-abstraction. Example: `VoiceMessageUploadCoordinator { init(service); upload(data) { try service.upload(data) } }` is used once at its only call site as `coord.upload(data)` and then dropped — `service.upload(data)` directly is enough.

#### Exceptions

- A hard constraint from the user or the final plan explicitly requires creating it → skip
- The authoritative final plan has approved a material architecture change and this abstraction is a necessary part of landing that decision → skip
- The wrapper **does** have extra logic (retry policy / state machine / cross-call cache / orchestration of multiple dependencies) → not over-abstraction, skip

### 3. Over-defensive code

#### Default contract

- A bug fix defaults to the minimal necessary change: every behavior change must map to verifiable evidence of a confirmed root cause, an explicit user requirement, or a hard project rule. Investigation hypotheses may drive experiments, but an unverified hypothesis cannot justify keeping a change in the final fix; this also covers alternative implementations and opportunistic optimizations, not only validation/fallback.
- Once the root cause is confirmed or corrected, Root must re-read the complete diff across all iterations of this task, withdraw this task's changes that only served ruled-out hypotheses or lack the basis above, and fix related docs accordingly; keep the necessary fix and other user changes. At delivery, summarize the basis for each retained behavior change in the existing report, without adding fixed artifacts or approval turns.
- Internal code calling internal code, and non-optionals handed over by the framework → **no validation, no try/catch**.
- Validate input structure/field semantics only at the owner boundary where untrusted input first enters the system (user input / external API / file IO), and only the invariants required to construct a trusted internal value; downstream consumes that trusted type directly.
- An invariant has exactly one validation owner: the decoder/parser owns structure, the domain constructor owns business invariants, the transport adapter owns request/response correlation, and the state machine or consumer owns ordering, session, and authorization context. Downstream may validate context invariants it newly introduces, but must not repeat the same invariant already established upstream.
- A new validation branch/helper/type must point to a requirement from the user / final plan, an authoritative external contract, or a reproducible failure fixture/trace. "It might happen" or "it's safer" alone is not evidence.
- Errors propagate or fail explicitly by default. A fallback must be explicitly authorized by the user / final plan, project rules, an authoritative product contract, or a frozen behavior test, and must spell out the degraded result plus recovery or failure ownership; a failure fixture/trace only proves the fault, it cannot authorize degradation, and the implementer's own account does not count either. Do not add a branch for "this case cannot happen".
- With failure evidence but no fallback authorization, write mode does not land code; return a `fallback_proposal` to Root: `trigger/evidence`, `without_fallback`, `proposed_degraded_result`, `data_or_semantic_loss`, `recovery_or_failure_owner`. The default choice is still no fallback; no reply from the user is not authorization.

#### Issue type

| issue_type | Trigger | severity |
|---|---|---|
| `unjustified-change` | a bug fix's behavior change cannot map to the necessity basis above, or the root cause is confirmed/corrected yet changes serving only ruled-out hypotheses remain | **blocking** |
| `silent-catch` | `try?` / `catch { }` silently swallows an error and does not meet the shared exceptions below | **blocking** |
| `speculative-validator` | new validation with none of the evidence above, or unable to name the single owner; a state machine/consumer validating its own ordering/session/context invariants does not count | **blocking** |
| `duplicate-validator` | the same invariant validated again across several layers; ordering/session/context invariants newly introduced by the consumer are not duplicates | **blocking** |
| `defensive-unwrap` | validates a case that cannot happen (`guard let` early return on something the framework guarantees non-optional) | warning |
| `defensive-fallback` | uses fallback/default/lossy decode/clamp/drop-invalid to disguise a failure as a usable result, without evidence and an explicit product degradation contract | **blocking** |

It is a fallback when `try?`, an empty-array/empty-string default, a lossy collection decode, skipping a bad item, or a generic unknown case turns a failed or unknown input into a seemingly usable result. It is not a fallback when the value is a semantic default defined by an authoritative schema, when an unknown representation preserves the raw value for an upper layer to judge, or when an owner state machine rejects an event that does not belong to the current session/ordering without synthesizing a substitute result.

#### Why `silent-catch` is blocking

Swallowing an error makes the root cause surface as some other symptom. If the requirement explicitly calls for silent failure or degradation (e.g. analytics failures must not affect the main flow), the implementation owner should write a durable causal comment rather than cite a plan section.

#### Shared exceptions

- The exceptions below apply to every issue type in this section.
- The user, the final plan, project rules, an authoritative external contract, or a test case reproducing the failure explicitly requires the validation; a fallback must still meet the product-authorization condition above
- A default value a framework hook requires you to implement (protocol witnesses such as `Equatable.==`)
- For a failure that is allowed to be silent, state the stable business reason and the failure boundary; the comment itself cannot substitute for the evidence above

## §Self-check list (write mode)

The implementation owner runs through this before writing:

- [ ] Does each behavior change in a bug fix meet the §3 necessity contract? After the root cause was confirmed or corrected, did Root re-read the complete diff and withdraw this task's unjustified changes?
- [ ] Is the comment I added a non-obvious why, or is it explaining the what / citing a plan, task, or fix number / leaving a stale TODO? Will it still make sense a year from now?
- [ ] Could the feature this new code implements be achieved by extending / modifying an existing method / type / helper?
- [ ] Does the abstraction I introduced (protocol / Manager / Service / config parameter / flag) really have ≥3 callers today, or is it prepared for "future extension"?
- [ ] Can every new validation branch/helper/type point to the user / final plan, an authoritative contract, or a reproducible fixture/trace? Does it sit at that invariant's single owner boundary?
- [ ] Was the same invariant already established by the upstream owner and then validated again downstream? Is the downstream check really an ordering/session/context invariant it newly introduced?
- [ ] Does the `try?` / `catch { }` I wrote swallow an error? Does the requirement really call for silence?
- [ ] Is my `guard let / else { return }` hard-validating something the framework already guarantees non-optional?
- [ ] Does my fallback/default/lossy decode/drop-invalid have both external evidence and an explicit product degradation result with recovery or failure-ownership semantics, rather than masking the root cause?
- [ ] With only failure evidence and no product authorization, did I stop before the Edit and return a `fallback_proposal` instead of deciding for the user?

Any violation hit, or an unanswerable evidence/owner/degradation-semantics question → do not land it; in review mode tag a blocking issue.

## §issue output contract (review mode)

`verifier` or `/review` puts the hits into an `issues` array, each in the format above. `issue_type` uses the field names from this skill's tables strictly, so Root can route fixes by type.

## Relationship to other skills / rules

- **architecture-first**: only resolves unresolved durable boundaries; this skill handles local anti-patch / reuse hygiene. A code smell by itself does not escalate; only when diagnosis proves the fix must change a boundary does it enter an architecture decision.
- **cleanup backend**: Claude uses `/simplify`; Codex uses `codex-simplify`. Cleanup fixes automatically; this skill only produces judgments and an issue list.
- **dead-code**: dead-code owns "no caller" (orphan symbols); this skill owns "should it be written at all" (the judgment before / after writing). The two are orthogonal.
- **post-change-verify** rule: this skill does not run build / lint. Formatting problems a lint tool can catch (whitespace / indentation / line length) belong to swift-formatting; this skill focuses on the semantic-level problems tools cannot catch.

## Out of scope

- ❌ Does not write code (review mode produces only the issue list; write mode produces only the self-check conclusion)
- ❌ Does not replace the format checks of swift-formatting / SwiftLint
- ❌ Does not replace a genuine material boundary decision; local code smells are still converged here
- ❌ Does not conflict with hard constraints from the user or the final plan; explicitly required tolerance, defense, or abstraction is not an issue
- ❌ Does not decide for the main agent whether a review-fix is adopted — that is the user's pick

## Why (core)

- The implementation owner and the reviewer use the same issue_type table
- Adding an issue type changes only this skill
- Reuse across agents / `/review`: other review tools can invoke it directly in future
- Consistent issue_type naming: the main agent can group review-fix operations by type
