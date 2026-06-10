# 新需求先写 Spec 再写代码（已迁 skill）

正文已迁移到 `~/.claude/skills/spec-before-code/SKILL.md`。触发时通过 `Skill(spec-before-code)` 加载（无 Skill 工具的 planner 按需 `Read` 该 SKILL.md）。

## 触发摘要

- **触发**：进了 `.worktrees/<slug>/` 准备落地 Edit/Write 但 `.specs/<slug>.md` 还不存在；先澄清 → 写 spec（模板 `~/.claude/templates/spec-template.md`）→ 再 Edit。PreToolUse hook 硬卡。dispatch-pipeline 流程下由 planner 阶段产出。
- **Bypass**：`touch .specs/<slug>.skip`。
- **不触发**：cwd 不在 `.worktrees/` 下 / spec 已存在 / 改 meta 配置。
