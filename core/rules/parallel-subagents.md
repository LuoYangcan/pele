# 并行 subagent：拆开独立任务同时跑

主 agent 可以用 `Agent` 工具派 subagent 并发执行独立子任务，但**入口受限**——只有以下两种情况可触发：

1. **用户显式发令**：「拆开并行跑 / 你改 A，派 subagent 改 B / 同时跑」这类切话题
2. **dispatch-pipeline 并行模式**：planner 在 `.specs/<slug>.md` 第 2 节「并行分组」表里标注了**多个 `parallel-N` 组**，且用户在阶段 1 末尾审 spec 时**未删除**该分组 → 视同用户已过审拆分方案，主 agent 按 `dispatch-pipeline.md` 阶段 2B / 3B / 3C / 5 跑

**不允许的入口**：主 agent 自主判断「这俩任务好像独立、并行一下」。判断权要么在用户、要么在 planner。

## 触发前：先拆分方案过审

收到"并行跑"指令后，**不要直接派 subagent**。先给用户拆分方案让他过审：

- 哪些子任务可以并行、依据是什么（物理文件边界 / 模块边界 / 平台边界）
- 哪些必须串行
- 各 subagent 的 prompt 概要（目标 / 约束 / 验收标准）
- 共享的接口 / 类型 / 数据模型：**先在主 agent 里定稿**，再派发 subagent

用户点头后再派。

## 三条硬约束

### 1. 任务必须互不依赖

两个 subagent 改的**文件不能重叠**、**类型不能相互依赖**。

**适合**：

- iOS 端 vs macOS 端同名功能
- 实现 vs 测试（测试基于已冻结的 API）
- UI 还原度调整 vs 无关的 lint 清理
- 多个互相独立的 feature 组件

**不适合**：

- 共享数据模型还在演化
- A 要消费 B 新定义的 API
- 都要改同一个 ViewController / Service

### 2. subagent 的 prompt 必须自包含

subagent 有独立 context，**拿不到**当前对话、TodoList、memory、plan，不能反问主 agent。主 agent 的 prompt 必须一次性写清：

- 需求目标 + 验收标准
- 具体的文件路径（别让它猜）
- 硬约束（能改哪些不能改哪些）
- 项目约定里和这个任务相关的部分

### 3. 工作区物理隔离

用 `Agent(isolation: "worktree")` 让 subagent 在独立 worktree 跑。`run_in_background: true` 让 subagent 后台跑，主 agent 继续做另一半；完成时系统通知。

## 集成联调

所有 subagent 完成后：

1. 合并 subagent 的改动回主工作区（merge 它们的分支 / cherry-pick）
2. 跑**编译**验证整体能不能过（按 `.claude/rules/post-change-verify.md`）
3. 冒烟级 review：检查跨任务的交互点（被 freeze 的接口是不是双方对齐使用）
4. **不做**深度 code review —— 那走 `/review` 的 Sonnet subagent

## 不做什么

- ❌ agent 自主决定是否并行
- ❌ 把并行 subagent 用于有依赖的任务（A 的结果喂给 B 用）
- ❌ 用集成阶段的冒烟 review 替代 `/review`
