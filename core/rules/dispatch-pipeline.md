# 三段式调度（主 agent 不写代码）（已迁 skill）

正文已迁移到 `~/.claude/skills/dispatch-pipeline/SKILL.md`。触发时通过 `Skill(dispatch-pipeline)` 加载，不要 Read 此文件（无 Skill 工具的 subagent 如 generator/executor 按需 `Read` 该 SKILL.md）。

## 触发摘要

- **触发**：用户提了写代码需求（新功能 / 修 bug / 改 UI / 重构 / 加 feature / 加测试，会落地 Edit/Write/NotebookEdit）；主 agent 检测到后**第一动作**就 `Skill(dispatch-pipeline)` 加载 SOP，再调度 planner → 用户拍板 → generator → executor → PASS/FAIL（FAIL 自动重调 generator ≤3 次）。
- **不触发**：纯问答 / 解释代码 / 找文件 / 查状态 / 改 meta 配置（rule、memory、hook、settings）/ 用户明确 bypass。
- **核心约束**：主 agent 自己不写代码、不改 spec、不跑 build/lint/test，全部委派 subagent。
