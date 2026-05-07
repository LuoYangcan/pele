# 并行 subagent：拆开独立任务同时跑

主 agent 可以用 `Agent` 工具派 subagent 并发执行独立子任务，但**入口受限**——只有以下两种情况可触发：

1. **用户显式发令**：「拆开并行跑 / 你改 A，派 subagent 改 B / 同时跑」这类切话题
2. **dispatch-pipeline 并行模式**：planner 在 `.specs/<slug>.md` 第 2 节「并行分组」表里标注了**多个 `parallel-N` 组**，且用户在阶段 1 末尾审 spec 时**未删除**该分组 —— 视同用户已经过审了拆分方案，主 agent 按 `dispatch-pipeline.md` 阶段 2B / 3B / 3C / 5 跑

**不允许的入口**：主 agent 自主判断「这俩任务好像独立、并行一下」——误判依赖会烧掉 token 和时间比串行更慢。判断权要么在用户、要么在 planner（planner 出 spec 时是独立 context、专注规划，比临时判断准确得多；且仍要过用户在阶段 1 末尾的闸口）。

## 触发前：先拆分方案过审

收到"并行跑"的指令后，**不要直接派 subagent**。先给用户一份拆分方案让他过审：

- 哪些子任务可以并行、依据是什么（物理文件边界 / 模块边界 / 平台边界）
- 哪些必须串行，为什么
- 各 subagent 的 prompt 概要（目标 / 约束 / 验收标准）
- 共享的接口 / 类型 / 数据模型：**先在主 agent 里定稿**，再派发 subagent，否则做到一半接口变了

用户点头后再派。

## 三条硬约束

### 1. 任务必须互不依赖

两个 subagent 改的**文件不能重叠**、**类型不能相互依赖**。违反就会集成冲突。

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

subagent 有独立 context，**拿不到**当前对话、TodoList、memory、plan。它不能反问主 agent。主 agent 的 prompt 必须一次性写清：

- 需求目标 + 验收标准
- 具体的文件路径（别让它猜）
- 硬约束（能改哪些不能改哪些）
- 项目约定里和这个任务相关的部分（AGENTS.md 的相关章节，或把关键规则复述一遍）

### 3. 工作区物理隔离

用 `Agent(isolation: "worktree")` 让 subagent 在独立 worktree 跑——主 agent 和 subagent 的文件改动物理不踩踏。

`run_in_background: true` 让 subagent 后台跑，主 agent 继续做另一半；完成时系统通知。

## 集成联调（主 agent 的最后职责）

所有 subagent 完成后：

1. 合并 subagent 的改动回主工作区（通常是 merge 它们的分支，或 cherry-pick）
2. 跑**编译**验证整体能不能过（按 `.claude/rules/post-change-verify.md`）
3. 冒烟级 review：检查跨任务的交互点（被 freeze 的接口是不是真的被双方对齐使用）
4. **不做**深度 code review—— 那仍然走 `/review` 的 Sonnet subagent

## 不做什么

- ❌ agent 不自主决定是否并行——必须用户显式触发
- ❌ 不把并行 subagent 用于有依赖的任务（比如 A 的结果喂给 B 用）—— 那是串行 subagent 的场景
- ❌ 不用主 agent 集成阶段的冒烟 review 替代 `/review`

## Why

并行的收益只在"独立任务块 + 明确接口"时成立。主 agent 拆错（把依赖当独立）导致的浪费，通常比串行直接做还贵。所以门槛设高：用户显式触发 + 拆分方案过审 + worktree 隔离 —— 三道闸都过了再派。
