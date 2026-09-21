# Host capabilities and authorization

Load when a workflow needs Plan, questions, delegation, model selection, or a harness helper. Use the tools exposed by the current session.

| Capability | Claude | Codex |
| --- | --- | --- |
| Enter Plan | EnterPlanMode when available | Only an actual host mode-switch tool can change modes |
| Questions | AskUserQuestion | request_user_input / request_user_input_async when allowed in the current mode; otherwise a short text question |
| Delegation | Agent | collaboration.spawn_agent; reuse an agent with followup_task |
| Role models | agents/*.md | Generated agents/*.toml; see [model policy](../../docs/model-policy.md) |
| Progress | Host plan UI | update_plan when available, otherwise concise progress |

Inspect loaded tools first; use only the host's available discovery interface when necessary. ToolSearch, Skill and EnterPlanMode are not universal tool names.

- A clear local change request or instruction to execute the current proposal authorizes reversible implementation and validation within scope. Without a mode-switch tool, the same Root plans in the current task and continues; do not add a fixed GO turn. Ask about material unresolved behavior or scope. Native Plan mode writes no code or plan files; design-preview artifacts are generated and shown only per the host-permission and directory rules in [figma-precise-extract](../skills/figma-precise-extract/SKILL.md).
- Resolve existing user authorization and project rules before asking. Continue when the target, parameters and impact are already covered. Obtain missing authority for new external writes, irreversible actions, or scope changes.
- Local incremental commits follow the default authorization and project exceptions in [plan-first-delivery's incremental commit rule](../skills/plan-first-delivery/SKILL.md#incremental-commits); push, PR and publishing each check user authorization separately. Implementation permission does not imply them.
- Create the isolated worktree required by project policy without repeating confirmation because of stale summaries or missing mode-switch tools.
- A custom Codex role's explicit model/effort wins over spawn values. Regenerate roles after policy changes; new tasks/subagents use them. Select the current Root through the task UI or CLI launch arguments.
- Before a formal plan is finalized, dispatch an independent review per [plan-challenge](../skills/plan-challenge/SKILL.md); when the role is not exposed, the model is unavailable, or there is no independent agent, follow its gap routing. Existing implementation authorization does not skip the review.
- Without subagents, Root works serially. Report an independent-review coverage gap when a fresh reviewer is unavailable; do not label self-review independent.

## Installed paths

`HARNESS_ROOT` means the absolute Pele checkout containing `core/` and `scripts/`. Resolve it from the real path of the loaded skill, or run `scripts/harness-root.sh` from that installation. For example, a global Codex install exposes `${CODEX_HOME:-$HOME/.codex}/scripts/harness-root.sh`; project installs expose `<project>/.codex/scripts/harness-root.sh`.

Bind `HARNESS_ROOT` to that resolved absolute path in each shell invocation, or substitute the absolute path in the command. Do not assume shell variables survive separate tool calls. Pass the resolved root to delegates. Helpers live under `$HARNESS_ROOT/scripts`; skills, rules, agents and schemas live under `$HARNESS_ROOT/core`. No workflow requires another host's home directory.
