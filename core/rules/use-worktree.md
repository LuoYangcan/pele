# 新话题进 git worktree 隔离（已迁 skill）

正文已迁移到 `~/.claude/skills/use-worktree/SKILL.md`。触发时通过 `Skill(use-worktree)` 加载，不要 Read 此文件。

## 触发摘要

- **触发**：用户切到新话题（「新任务 / 另一个 / 接下来做 X / 开始搞 Y / 下一个需求 / 现在改 Z」等切话题信号）且本轮要写代码（会落地 Edit / Write / NotebookEdit），在第一次 Edit 前建 worktree
- **不触发**：延续当前任务 / 纯问答 / 读代码 / 查状态 / 改 meta 配置（rule / memory / hook / settings）/ 已在 `.worktrees/` 里
- **核心约束**：必须基于最新 `origin/dev`；不要用 `EnterWorktree(name=...)`（会继承当前 HEAD 的 WIP）
