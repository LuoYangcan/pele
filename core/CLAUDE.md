# Global rule index (load on demand)

## Coding turn entry

- **Formal plan review**: candidate plans in native Plan, Default, architecture, and meta config load [plan-challenge](skills/plan-challenge/SKILL.md) before finalization / `ExitPlanMode` / implementing from that plan, for an adversarial review by an independent read-only reviewer; reuse valid conclusions, re-review substantive changes, and backfill a missing record first. This is the only plan-review path: Claude's built-in `Plan` agent only produces or compares alternative designs and is not dispatched as a reviewer. Micro changes without a plan and progress checklists do not trigger; the reviewer does not dispatch recursively.
- **Native Plan mode**: Root investigates, clarifies, and produces the final plan; do not load `plan-first-delivery`, do not write code or plan files. For Figma UI, generate and show the H5 preview before finalizing, per the host-permission and strictness rules in [figma-precise-extract](skills/figma-precise-extract/SKILL.md). The final plan is the source of truth for requirements in later implementation. When steps ≥3, ≥2 modules are involved, or there is a trade-off between approaches, draw a plan diagram with `Skill(visual-brief)` after producing the plan and before `ExitPlanMode`; no diagram for small changes.
- **Writing code in Default mode**: first step is loading `Skill(plan-first-delivery)`. When the same task already has a final plan, check its review validity and enter execution, without rewriting the plan or adding fixed approval turns; when there is no plan and an unresolved decision is hit, Root uses the available planning/question tools per `rules/host-adapter.md`. Everything else follows the skill's entry routing.
- **Code changes always in a worktree**: for any coding task that will land an Edit/Write, load `Skill(use-worktree)` before the first write and create an isolated worktree under the repo's `.worktrees/`; coding tasks must not write in the main checkout (meta config routes by the next entry). Do not switch the main repo's branch on your own and do not clean up its dirty state; leave the main repo as is when it is not on the base branch or not clean, and always create the worktree from `origin/<base>`, never depending on the main repo's HEAD. Does not trigger for continuing the current task (iterating inside a worktree), for being already in a worktree, or for pure Q&A / read-only diagnosis.
- **Meta config**: rule / skill / agent / hook / settings do not go through `plan-first-delivery` or ExecPlan, but are not exempt from protected-branch, dirty-tree, and external-write permission rules. Repo-backed meta on main/master/dev switches to a task branch or worktree first; non-Git global config can be changed directly once the live target is confirmed. Check the real target of symlinks/hooks before writing; after writing, run JSON/TOML parse, `bash -n`, Markdown/local-link check, and installer dry-run/idempotency according to what was touched; do not run an app build unless the config directly affects the app.
- **Turn checkpoint**: read `rules/iteration-checkpoint.md` when the same request has gone more than 3 consecutive turns without converging.

Pure Q&A, reading code, checking status, and meta config do not go through the coding delivery flow; still run the targeted safety and verification steps above.

## Workflow

- [host-adapter](rules/host-adapter.md) — Resolve actual Plan/question/delegation tools, installed paths, and existing authorization before invoking host-specific workflows.

- [plan-first-delivery](skills/plan-first-delivery/SKILL.md) — The main flow for writing code in Default mode: Root (planning-tier strong model) plans, integrates, and runs unified verification; implementation delegates to implementer (implementation-tier model) by default; record a lightweight judgment-call audit as needed; independent verifier / UI reviewer / parallel workers trigger on orthogonal gates.
- [exec-plan](skills/exec-plan/SKILL.md) — Persist the final plan as a single-file ExecPlan only for cross-session, cross-host, multi-writer, irreversible migration, or audit handoff.
- [visual-brief](skills/visual-brief/SKILL.md) — When presenting a multi-step plan, an implementation approach, a trade-off between approaches, or investigation/architecture conclusions, carry structure in one inline diagram and conclusions in 3–5 bullets, instead of long paragraphs.
- [use-worktree](skills/use-worktree/SKILL.md) — Always create an isolated worktree from the latest target branch for code changes (`scripts/worktree-bootstrap.sh` creates and initializes in one step; a qualifying existing worktree can be reused); the main checkout stays read-only.
- [parallel-subagents](skills/parallel-subagents/SKILL.md) — Read-only investigation can run in parallel; write tasks only when write domains are mutually exclusive and it clearly speeds things up, with Root doing integration and final verification centrally.
- [post-change-verify](rules/post-change-verify.md) — On the final candidate, run the relevant cheap lint/check first, then build, then targeted tests as the request or the risk requires; source changes invalidate old evidence.
- [agent-readable-docs](skills/agent-readable-docs/SKILL.md) — Compact inline while preserving the semantic contract when creating or modifying agent-consumed operational Markdown; read-only application, ordinary human docs, and format/link-only edits do not trigger.
- [cleanup-and-exit](skills/cleanup-and-exit/SKILL.md) — Use when the user asks to clean up the current worktree or to exit.
- [commit-message](rules/commit-message.md) — Use the single-line conventional commit format when writing a commit message, and decide the trailer by repo ownership.

## Design and code quality

- [architecture-first](skills/architecture-first/SKILL.md) — Triggers only when the user explicitly asks for an architecture review, or on a module ownership, dependency direction, public contract, state source-of-truth, or side-effect boundary decision left unresolved by the final plan / project rules; local abstractions, branches, code smells, and lint do not trigger.
- [scan-trigger-docs](skills/scan-trigger-docs/SKILL.md) — Scan the project AGENTS/CLAUDE trigger-on-touch docs before changing source, and read the ones that match.
- [lean-diff](skills/lean-diff/SKILL.md) — Check for patchwork, over-abstraction, comment noise, and defensive bloat before writing non-trivial code.
- [lint-repair-strategy](skills/lint-repair-strategy/SKILL.md) — When fixing lint, pick a structural fix by category; do not split files without semantics to dodge a threshold.
- [swift-formatting](rules/swift-formatting.md) — Follow the project's lint/format conventions when modifying Swift.
- [ios-list-ui-container](rules/ios-list-ui-container.md) — Choose a virtualized container when writing or refactoring an iOS scrolling list of same-kind items.

## Specialized operations

- [open-sim](skills/open-sim/SKILL.md) — Use when the user asks to build and open in the iOS Simulator.
- [run-device](skills/run-device/SKILL.md) — Use when the user asks to install or run on a real iPhone.
- [figma-precise-extract](skills/figma-precise-extract/SKILL.md) — For Figma UI, generate an H5 style preview and freeze design inputs before the Plan is finalized; also used to extract exact sizes, spacing, or tokens.
- [figma-asset-export](skills/figma-asset-export/SKILL.md) — Use when exporting custom icons, illustrations, or logos from Figma into iOS.

## Apple platform knowledge (provided by Xcode)

This skill set does not ship with Pele: after installing, run `scripts/sync-xcode-skills.sh` to export from the local Xcode into `skills/` (rerun that script or `install.sh` after an Xcode upgrade; do not hand-edit the bodies). The exported skills share a source with the `xcode` MCP (build / run / test, crash and field performance logs, String Catalog, target and build settings); device-interaction is unavailable when the MCP is not registered. Typical members are swiftui-specialist, swiftui-whats-new, uikit-app-modernization, app-intents-specialist, device-interaction, audit-xcode-security-settings, adopt-c-bounds-safety, and modernize-tests; see each one's description for its trigger conditions.

## Loading conventions

- Load only the bodies triggered this turn; additional references a skill cites are also read only per routing.
- Must load when the user names a skill; when unsure whether it matches, read its description first, then judge.
- On rule conflicts, user instructions and project-level AGENTS/CLAUDE outrank this global index.
