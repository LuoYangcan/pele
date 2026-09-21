# Architecture

Pele installs onto Claude Code, Codex, or both; the workflow content is host-neutral and only the config layout differs (see the host support table in the README). Pele's center is plan-first delivery with model tiering. Native Plan mode turns a request into a decision-complete plan, which an independent `plan-challenger` reviews before it is finalized; the same Root — a strong planning-tier model — then owns decisions, integration, and verification in Default mode, while code writing is delegated by default to the `implementer` subagent running a general implementation-tier model. Roles are orthogonal gates, not a fixed pipeline.

## Control flow

```text
user request (code-writing)
  ↓
Plan mode (or a read-only planning turn): Root explores, clarifies,
produces a candidate plan
  ↓
plan-challenger: fresh read-only challenge for over-design, over-strict
validation, and over-protection → Root revises (one targeted recheck)
  ↓
final plan — the single source of requirement truth
  ↓ explicit execute authorization
Root: create isolated worktree .worktrees/<slug> from origin/<base>
  ↓
Root freezes decision-complete units → implementer writes the code
  (Root writes directly only for micro-edits, integration fixes, narrow repairs)
  ↓
Root reviews the returned diff, integrates, commits each verified feature unit
  ↓
post-change verify: cheap lint/check → build → targeted tests when required
  ↓
orthogonal gates (zero or more per task):
  ├─ needs_independent_review → verifier (fresh, read-only semantic acceptance)
  ├─ needs_ui_review          → ui-reviewer (static + motion acceptance vs design)
  └─ needs_parallel_write     → multiple implementer instances, exclusive ownership
  ↓
Root reports: observable behavior, verification results, decision audit, docs disposition
```

## Model tiering

| Role | Tier | Owns |
|---|---|---|
| Root (session) | strong planning tier (e.g. `/model fable`) | plan, decisions, diff review, integration, verification, user interaction |
| `plan-challenger` | planning tier (inherits Root on Claude) | independent read-only challenge of a formal plan before it is finalized |
| `implementer` | general implementation tier (`core/agents/implementer.md`) | code writing inside frozen ownership; returns diff + open questions |
| `verifier` / `ui-reviewer` | mid tier | independent acceptance when their gate hits |
| `command-runner` | small tier | mechanical command execution with trimmed logs |

Each agent ships twice: `core/agents/<name>.md` for Claude Code and `core/agents/<name>.toml` for Codex. `install.sh` links only the extension the target host reads, then the model-policy helper renders Codex TOML with its absolute harness root.

The implementer never commits, never runs final verification, and returns material decisions to the Root instead of deciding them.

## File contracts

- Final plan lives in the Plan-mode conversation. A single-file ExecPlan (`templates/exec-plan-template.md`) is written only for cross-session/host, multi-writer, irreversible, or audited work.
- `.reviews/` holds local delivery artifacts (decision audit, frozen review snapshots); never committed or shipped.
- `.specs/<slug>-assets/` holds frozen design-input artifacts (measurement HTML, PNG, preview.html) for strict Figma tasks; rebuilt only when the design input itself changes.

## Enforcement

1. The protected-branch script blocks direct edit tools on protected branches (main / master / dev), including apply_patch payloads. Claude installs it as a managed hook entry; Codex installs the script for the user to enable through `/hooks`.
2. `plan-first-delivery` defines the state machine, orthogonal gates, delegation, and failure routing; `post-change-verify` defines the verification ladder and receipt invalidation.
3. Agent definitions constrain read/write scope and structured returns.

## Installed layout

```text
~/.claude/ or ${CODEX_HOME:-~/.codex}/
├── CLAUDE.md
├── rules/
├── agents/
├── commands/
├── skills/
├── templates/
├── scripts/
└── settings.json
```

Content entries are symlinked to `<pele-checkout>`. Claude hook entries and Codex `hooks.json` entries are merged by Pele ownership instead of replacing complete hook configuration; `/hooks` remains the user-facing trust control for Codex. Pulling changes updates existing symlink targets immediately. Re-run `install.sh` when a release adds or removes top-level rules, agents, commands, skills, templates, scripts, or hook definitions.
