# 并行 subagent：拆开独立任务同时跑（已迁 skill）

正文已迁移到 `~/.claude/skills/parallel-subagents/SKILL.md`。触发时通过 `Skill(parallel-subagents)` 加载。

## 触发摘要

- **触发**：用户**显式**说「拆开并行跑 / 派 subagent 改 B / 同时跑」，或 dispatch-pipeline 并行模式（planner 在 spec 第 2 节标多个 `parallel-N` 组、用户审 spec 未删除）。
- **不触发**：主 agent 自主判断是否并行（判断权在用户或 planner）。
- **核心约束**：拆分方案先过审；三条硬约束（文件边界不重叠 / prompt 自包含 / worktree 物理隔离）；集成联调只跑编译冒烟、不替代 /review。
