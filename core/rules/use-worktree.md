# 新话题进 git worktree 隔离（已迁 skill）

正文已迁移到 `~/.claude/skills/use-worktree/SKILL.md`。触发时通过 `Skill(use-worktree)` 加载完整 SOP，**不要 Read 此文件**。

保留这份 stub 是为了让既有的引用路径（`dispatch-pipeline.md` / `planner.md` / `cleanup-and-exit.md` / `spec-before-code.md`）继续可达，避免一次性大改动。后续这些引用可以择机改成「调 `Skill(use-worktree)`」。

## 触发摘要（详细 SOP 在 skill 里）

- **触发**：用户切到新话题（「新任务 / 另一个 / 接下来做 X / 开始搞 Y / 下一个需求 / 现在改 Z」等切话题信号）且本轮要写代码（会落地 Edit / Write / NotebookEdit），在第一次 Edit 前建 worktree
- **不触发**：延续当前任务（修 bug / 调样式 / 基于同一需求追加 / 来回迭代）/ 纯问答 / 读代码 / 查状态 / 改 meta 配置（rule / memory / hook / settings）/ 当前已经在 `.worktrees/` 里
- **核心约束**：必须基于最新 `origin/dev`，**不要**用 `EnterWorktree(name=...)`（会从当前 HEAD 起步、继承前一需求的 WIP）

完整 8 步流程、`<project-specific>` 钩子、生命周期、Why → 见 skill。
