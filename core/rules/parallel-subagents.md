# 并行 subagent：拆开独立任务同时跑（已迁 skill）

正文已迁移到 `~/.claude/skills/parallel-subagents/SKILL.md`。触发时通过 `Skill(parallel-subagents)` 加载。

## 触发摘要

- **触发**：用户显式说「拆开并行跑 / 派 subagent 改 B / 同时跑」，或 dispatch-pipeline 的 Planner fan-out / 已过审实现并行模式。
- **不触发**：主 agent 自主判断是否并行（判断权在用户或 planner）。
- **核心约束**：实现并行要求文件边界不重叠、prompt 自包含、worktree 物理隔离；Planner fan-out 共享 worktree，但每个 worker 只能写自己的 draft/report/question。
