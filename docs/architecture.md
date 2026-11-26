# Architecture

Pele installs onto Claude Code, Codex, or both. Native Plan mode turns a request into a decision-complete plan. A `plan-challenger` independently reviews major designs and explicitly requested plans. The same Root owns decisions, implementation, integration, and verification in Default mode; on Codex it may delegate non-trivial implementation to the implementation-tier `implementer`. Independent acceptance roles run when their gates apply.

## Control flow

```text
user request (code-writing)
  ↓
Plan mode (or a read-only planning turn): Root explores, clarifies,
produces a candidate plan
  ↓
plan-challenger, when triggered: read-only challenge → Root revises
(one targeted recheck)
  ↓
final plan — the single source of requirement truth
  ↓ explicit execute authorization
Root: create isolated worktree .worktrees/<slug> from origin/<base>
  ↓
Root writes the code (Claude), or freezes decision-complete units for the
  implementer (Codex, non-trivial work); ≥2 disjoint write domains may run
  as parallel implementers
  ↓
Root reviews and integrates, commits each verified feature unit locally
  ↓
post-change verify: cheap lint/check → build → narrowest related tests
  (test commands run through command-runner)
  ↓
gates (zero or more per task):
  ├─ high-risk diff or user request → verifier (fresh, read-only semantic acceptance)
  └─ Figma / animation / complex UI → ui-reviewer (static + motion acceptance)
  ↓
Root reports: observable behavior, verification results, gates triggered,
docs updated, unverified items and remaining risk
```

## Model tiering

| Role | Tier | Owns |
|---|---|---|
| Root (session) | planning tier (e.g. `/model opus`) | plan, decisions, implementation on Claude, integration, verification, user interaction |
| `plan-challenger` | strongest review tier (pinned to Fable on Claude; does not follow Root) | independent challenge of major designs and plans the user asks to review |
| `implementer` | implementation tier (`core/agents/implementer.md`) | parallel write domains on Claude; delegated implementation on Codex; returns diff + open questions |
| `verifier` | strongest review tier (Fable on Claude) | independent semantic acceptance of high-risk diffs |
| `ui-reviewer` | mid tier | UI acceptance against the frozen design |
| `command-runner` | small tier | mechanical command execution with trimmed logs |

Each agent ships twice: `core/agents/<name>.md` for Claude Code and `core/agents/<name>.toml` for Codex. `install.sh` links only the extension the target host reads, then the model-policy helper renders Codex TOML with its absolute harness root.

The implementer never commits, never runs final verification, and returns material decisions to the Root instead of deciding them.

## File contracts

- Final plan lives in the Plan-mode conversation. A single-file ExecPlan (`templates/exec-plan-template.md`) is written only for cross-session/host, multi-writer, irreversible, or audited work.
- `.reviews/` holds local delivery artifacts; never committed or shipped.
- `.specs/<slug>-assets/` holds frozen design-input artifacts (measurement HTML, PNG, preview.html) for strict Figma tasks; rebuilt only when the design input itself changes.

## Enforcement

1. The protected-branch script blocks direct edit tools on protected branches (main / master / dev), including apply_patch payloads. Claude installs it as a managed hook entry; Codex installs the script for the user to enable through `/hooks`.
2. `plan-first-delivery` defines the state machine, orthogonal gates, delegation, and failure routing; `post-change-verify` defines the verification ladder; source changes invalidate earlier evidence.
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
