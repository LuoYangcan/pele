---
name: architecture-first
description: "Resolve durable architecture boundaries inside the current Root's Plan/discovery. Use only when the user explicitly asks to decide or revisit a material architecture boundary, or when work must choose/change an unresolved module/layer ownership or dependency direction, public/cross-module contract or multi-implementation seam, state source-of-truth/state machine/event flow, IO/side-effect boundary, or multi-responsibility split across those boundaries. Skip when project rules, precedent, or the authoritative final plan already determine structure and the user did not ask to revisit it. Skip work confined to one existing boundary—including private helpers/types/files, branches/flags, local error handling/tests, code smells, lint findings, and ordinary correctness review. Escalate review findings only when remediation requires a material boundary decision."
---

# Architecture-first

把本 skill 当作同一 Root 在 Plan/discovery 中按需使用的决策 lens。它不创建独立阶段、subagent、artifact、checklist 或确认回合。

## 入口判定

同时满足以下条件才进入架构选型：

1. 用户明确要求重新设计，或最终 Plan、项目规则和最近 precedent 尚未给出唯一结构；
2. 选择会长期改变至少一项契约：
   - 模块/层 ownership 或依赖方向；
   - public/跨模块 API、扩展点或多实现 seam；
   - state source-of-truth、状态机或事件流；
   - IO、副作用、持久化或外部系统边界；
   - 多职责组件的拆分会跨越上述边界。

不因 private helper/type、新文件、局部分支/flag、copy-paste、TODO、fallback、局部 error handling、测试 seam、代码行数或 lint warning 触发。此类局部质量问题由 `lean-diff`、`lint-repair-strategy` 或 Root 的根因诊断处理。

若结构已决，返回 `architecture_decision: not_needed — <project rule / precedent / final plan>` 后继续当前流程；不要为了证明“不需要复杂架构”再展开候选比较。

## 证据预算

只验证会改变当前选择的事实：

- 读取已命中的项目 invariant 或 final plan；
- 用 `rg` 查看 affected boundary 的直接 callers/callees 和一个最近 precedent；
- 仅在新增或替换 dependency 时读取 manifest；
- prompt 中不影响选择的文件、符号和依赖不做全量 reality-check。

发现用户描述与仓库不一致时，直接校准事实并继续。只有校准会改变可观察行为、scope、硬约束或验收时才询问用户。

## 决策轴

依次回答三问：

1. `variation`：真实变化轴是什么，确有多个实现或长期扩展点吗？
2. `state_ownership`：真相源、生命周期、并发与迁移由谁拥有？
3. `dependency_and_effects`：依赖应指向哪边，volatile seam、IO 和副作用落在哪层？

只在存在两个以上可行结构时按需读取一个 reference：

- 行为/对象模式边界：`references/pattern-boundaries.md`
- UI state/事件流边界：`references/ui-state-boundaries.md`
- 模块/系统/副作用边界：`references/system-boundaries.md`

项目既有 shape 已满足约束时优先沿用，不读取百科式资料，不按行数或分支数机械套模式。

## 产出

仅在存在 material choice 时把下面内容直接合入最终 Plan；无最终 Plan 时作为当前 Root 的内联决策，不另建文件：

```yaml
architecture_decision:
  decision: <选择与责任边界>
  evidence: [<2-3 条仓库事实>]
  rejected_nearest_alternative: <最近候选及拒绝原因>
  consequences:
    affected_boundaries: [<模块/契约>]
    migration: <迁移或兼容要求>
    verification: <应证明的行为/边界>
```

Plan 已包含该决策时，Default implementation 直接消费，不再次调用本 skill。实施中发现新的 material boundary surprise 时暂停 writer，回到 discovery/Plan 更新决策；普通 review 发现明确边界违规时直接报 finding，只有修法仍存在未决架构选择才调用本 skill。

## 不做的事

- 不直接写实现代码；
- 不接管 anti-patch、复用、lint 或通用 correctness review；
- 不新增批准点；只有选择改变用户行为、scope 或硬约束时沿主流程询问；
- 不为沿用项目既有架构生成仪式性理由。
