---
name: exec-plan
description: 把原生 Plan mode 或同线程 planning 结果持久化成单文件 ExecPlan。跨会话/host、长期 Goal、多个 implementation writer/worktree、不可逆迁移、审计/交接或用户明确要求计划文件时必须使用；同一 Root 同一任务一次可完成、短小直接修改、纯问答或 meta 配置不触发。
---

# ExecPlan

ExecPlan 是跨 context 的执行交接，不是每个代码任务的前置门禁。

## 何时写

满足任一条件时，在离开 Plan mode、进入 Default 后，第一次源码写入前写：

- 另一个任务、host、长期 Goal 或未来 session 将继续实现；
- 多个 implementation writer/worktree 需要共享完整决策；
- migration/rollback 或其他不可逆步骤需要持久化操作顺序；
- 用户要求 spec、执行计划或审计工件。

短时 explorer、同一 Root 的普通实现、单个自包含 worker prompt 不触发。

执行中任一上述条件由假变真（发现将跨 session/host、出现第二个 writer/worktree、步骤变为不可逆、用户要求工件），或执行期已积累用户实质决策且存在跨 session 中断风险（预计本 session 无法收尾、用户明示改天/换环境继续）时，立即补写当前最终 plan 快照并按更新规则维护，不受「第一次源码写入前」时点限制。

## 路径与格式

默认写到当前 worktree：

```text
.specs/<worktree-slug>.md
```

使用 `~/.claude/templates/exec-plan-template.md`。保持计划本身为单文件；不要创建 task/risk/amendment/decisions 子树，不维护双份 status。Figma 等二进制/测量输入可放在同级 `.specs/<slug>-assets/`，不把它当计划状态树。

必填内容：

1. 目标与可观察完成态；
2. scope、non-goals 和硬约束；
3. 已定关键决策、接口/数据流、受影响面；
4. milestones、依赖与 writer ownership；
5. 验证、mandatory/optional review、即时授权边界、风险与 rollback；
6. 当前已知事实和未完成工作。

## 更新规则

- Root 是 canonical ExecPlan 的唯一 writer；worker 只读。
- 行为、scope、架构、约束或验收变化时重写对应 canonical 段，并递增 `revision`；不要 append 相互冲突的历史正文。
- reviewer 输入用绝对路径、当前 `revision` 和文件 SHA-256 绑定本计划；任何更新都使旧语义/UI review 失效。
- 实现进度用 host 的 checklist/Todo；ExecPlan 只记录跨 context 必须知道的 milestone 状态。
- 用户取消或替换目标时保留已有源码，不自行销毁；在 ExecPlan 顶部标记 superseded 并链接替代 plan。
- ship 前可清理 `.specs/`；其中仍有长期项目知识时，先迁入项目 AGENTS/CLAUDE 或 trigger-on-touch docs。

## 交接输入

给 worker/reviewer 的 prompt 同时包含 ExecPlan 绝对路径、分配 scope、文件 ownership、base ref 和验收命令。不要只发一句“按计划做”。
