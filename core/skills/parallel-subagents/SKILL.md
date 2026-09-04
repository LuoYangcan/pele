---
name: parallel-subagents
description: 将独立的只读调研或互斥写域并发交给 subagent。触发：用户显式要求并行，或 Root 判断并行能显著提速且任务边界已决策完整。写任务必须互不依赖、文件 ownership 不重叠。
---

# 并行 subagent

并行是执行策略，不是固定流程阶段。Root 始终负责用户交互、最终 plan、共享决策、主 worktree 集成和最终汇报。

## 何时并行

- 有两个以上相互独立、耗时的 repo/docs 调研问题：可并发 explorer。
- 实现决策已经完整，存在两个以上互不依赖的写域，且并发能明显缩短时间：可并发 worker。
- 用户显式指定并行或某个 subagent：按用户要求拆分，但仍校验安全边界。

以下情况串行：共享 API 仍在演化、一个任务消费另一个的新结果、会改同一文件、合并成本高于并发收益、单个 Root 足以快速完成。

## 分派前冻结

Root 在 prompt 中写清：

- 目标、可观察完成条件和相关约束；
- 独占文件或模块 ownership、禁止触达范围；
- 已冻结的共享接口和依赖；
- `plan-first-delivery` 冻结的 `validation_fallback_contract`；
- 必须读取的项目文档；
- 返回格式与允许执行的窄域检查。

每个 worker 都要知道：它不是仓库里唯一的 writer，不得回滚或覆盖他人改动；发现并发变化时应适配当前文件状态，冲突则停下报告。

分派写任务前还要冻结交接机制：共享 worktree 的互斥文件直接 fan-in，或独立 worktree 的 diff handoff。不能等 worker 写完才决定用 commit、patch 还是复制文件。

## 隔离与 ownership

- 只读 explorer 可共享 worktree，不写文件。
- host 能把独立 worktree 的未提交 diff 完整交回 Root 时，写 worker 优先使用独立 worktree；Root 记录其绝对路径和 `base_ref`。
- 共享 worktree 时，必须保证一文件一 owner；worker 直接写其 ownership，Root 不同时编辑这些文件。
- 共享清单、公共接口、canonical plan、项目级配置和最终合并文件只由 Root 写。
- 不为机械的 task 编号反复新建 fresh agent；只有真实并行边界或独立性要求才创建实例。

## Worker handoff

每个写 worker 返回：worktree 绝对路径、`base_ref`/当前 HEAD、`git status --short`、完整 changed/untracked paths、ownership 内的 diff、`validation_fallback_contract` 对账、窄域检查及结果、未解决项。不得自行 commit、merge、push 或开 PR。

- 共享 worktree：Root 复核当前文件与返回清单即可；任何越界路径先停下处理。
- 独立 worktree：优先用 host-native 未提交 diff handoff。共享本地磁盘时，Root 可从记录的 worktree 读取 `git diff --binary <base_ref> -- <owned paths>` 并单独核对 untracked/binary 文件，再应用到主 worktree。
- 若 host 只能靠 commit/cherry-pick 保真交接，必须先取得用户对该 Git mutation 的明确授权；未授权就不要选这种隔离方式。无法无损交接未跟踪或二进制文件时，改用共享 worktree 的互斥 ownership。
- Root 确认主 worktree 已完整集成后才能清理 worker worktree；不得先删唯一副本。

## 集成

1. Root 收集每个 handoff，核对 `base_ref`、changed paths、越界、冲突、共享契约和 `validation_fallback_contract` 对账。
2. Root 按冻结的机制把 diff 集成进主 worktree，逐项确认 untracked/binary 文件，并完成必要的集成修正。
3. 只对 fan-in 后的最终候选执行一次 `rules/post-change-verify.md` 中冻结的验证。
4. 最终源码变化会使对应验证和 review 失效；authoritative plan 或设计输入变化会使语义/UI review 失效。只重跑受影响 gate。

worker 可以执行为安全合并所需的窄域检查，但不替代最终集成验证，也不自行做广泛 review。
