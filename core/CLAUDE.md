# Global rule index (load on demand)

## General

- When a requirement, a term, or the behavior or intent of existing code is unclear or has several reasonable readings, investigate first; if that does not settle it, ask the user instead of guessing.
- On rule conflicts, user instructions and project-level AGENTS / CLAUDE outrank this file.

## Coding turn entry

- **Native Plan mode**: Root investigates, clarifies, and produces the final plan; it writes no code or plan files. The final plan is the source of truth for requirements in later implementation. For Figma UI, generate and show the H5 preview before finalizing, per [figma-precise-extract](skills/figma-precise-extract/SKILL.md).
- **Writing code in Default mode**: load [plan-first-delivery](skills/plan-first-delivery/SKILL.md) first. When the same task already has a final plan, continue from it without rewriting the plan or adding a fixed approval turn.
- **Code changes always in a worktree**: before the first Edit/Write, enter an isolated worktree per [use-worktree](skills/use-worktree/SKILL.md); never write in the main checkout. Do not switch the main checkout's branch or clean its dirty state; create the worktree from `origin/<base>`. Reuse the worktree when continuing on the same task branch. Pure Q&A and read-only diagnosis do not trigger this.
- **Major design review**: only for a new overall design, a major redesign, or an explicit user request, dispatch an independent review per [plan-challenge](skills/plan-challenge/SKILL.md); routine fixes and local changes do not trigger it.
- **Meta config** (rule / skill / agent / hook / settings): does not go through plan-first-delivery, but still respects protected branches, dirty trees, and external-write permissions. Repo-backed meta on main / master / dev moves to a task branch or worktree first; non-Git global config can be edited directly once the live target is confirmed. Check the real target of symlinks / hooks before writing; afterwards run JSON / TOML parse, `bash -n`, local link checks, and an installer dry-run as applicable. Do not run an app build for meta changes.

## Rules

Claude loads `rules/*.md` automatically; Codex reads them when the situation applies:

- [commit-message](rules/commit-message.md): when writing a commit message.
- [post-change-verify](rules/post-change-verify.md): verification of the final candidate.
- [iteration-checkpoint](rules/iteration-checkpoint.md): when the same request has gone more than 3 consecutive turns without converging.
- [ios-list-ui-container](rules/ios-list-ui-container.md): when writing or refactoring an iOS scrolling list.

## Writing agent-facing docs

When editing AGENTS / CLAUDE, rules, skills, agents, commands, or other Markdown that agents read:

- Fold new content into the matching section of the existing structure instead of appending it at the end; define each fact in one place and link to it elsewhere.
- Keep only triggers, steps, failure routing, and non-obvious causality that changes a decision; drop history, task traces, repeated emphasis, and general knowledge the model already has.
- UI sizes, spacing, and colors are defined by the code; project docs do not copy design-spec values.
- No meta commentary such as "newly added" or "as mentioned above".

## Tool conventions

- Use [visual-brief](skills/visual-brief/SKILL.md) only when the user asks for a diagram; plans and conclusions default to text and tables.
- Apple platform skills are exported from the local Xcode by `scripts/sync-xcode-skills.sh` into `skills/`; do not hand-edit their bodies. Rerun that script or `install.sh` after an Xcode upgrade.
- For device / simulator selection, screenshots, UI hierarchy, and touch interaction, use the official Xcode tools / MCP the host exposes first; fall back to another interaction tool only when those are unavailable, do not cover the operation, or fail, and state the gap before falling back. Builds, installs, and launches go through `open-sim` / `run-device`.
- Clean up worktrees and caches with `cleanup-and-exit` (`/clean-and-exit`).

## Installed paths

`HARNESS_ROOT` is the absolute Pele checkout that contains `core/` and `scripts/`. Resolve it from the real path of the loaded skill, or run `scripts/harness-root.sh` from the installation (a global Codex install exposes `${CODEX_HOME:-$HOME/.codex}/scripts/harness-root.sh`; a project install exposes `<project>/.codex/scripts/harness-root.sh`). Bind it in each shell invocation, or substitute the absolute path; shell variables do not survive separate tool calls. Pass the resolved root to delegates. Helpers live under `$HARNESS_ROOT/scripts`; skills, rules, and agents live under `$HARNESS_ROOT/core`.
