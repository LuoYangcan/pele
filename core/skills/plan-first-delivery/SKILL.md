---
name: plan-first-delivery
description: Default mode 的写代码交付主流程。收到会落地 Edit / Write / NotebookEdit 的请求、执行同一任务里原生 Plan mode 已完成的最终 plan、修 bug、重构、加测试或实现 UI 时使用。Root（规划档强模型）负责 plan、决策、集成与客观验证，非平凡实现默认委派 `implementer`（实现档模型）；subagent 另用于独立调研与最终独立验收。不在原生 Plan mode、纯问答、只读诊断、查状态、meta 配置或 slash command 内触发。
---

# Plan-first delivery

原生 Plan mode 负责把需求变成 decision-complete plan；Default mode 的同一 Root 承接交付，两者之间不再增加第二份计划、文件存在性 checkpoint 或固定角色流水线。模型分层：Root 以规划档强模型运行（Claude host: `/model fable`），负责 plan、共享决策、diff review、集成与验证；代码写入默认委派实现档模型的 `implementer`（模型见 `agents/implementer.md`）。

## 入口路由

| 当前状态 | 处理 |
| --- | --- |
| 原生 Plan mode | 不执行本 skill；保持只读，最终 plan 是同一任务的需求真相源 |
| Default，用户明确要求执行同一任务的最终 plan | 直接进入执行；不重新规划、不复制成第二份计划文件 |
| Default，目标窄且无会改变结果的决策 | 仅限微改动：单文件或少量行、无新可观察行为、实现唯一明确，或用户指令已具体到实现唯一确定且不引入新的可观察行为。只读确认入口和影响面；多步任务用 `update_plan`，随后实现。新功能、多文件改动、存在多种合理实现或行为变化，以及无法确定是否存在下一行任一类决策时，按下一行处理 |
| Default，仍有产品行为、scope、架构、硬约束或验收决策 | 先用 `ToolSearch` 确认 `EnterPlanMode` 是否存在——它常是 deferred tool，不出现在已加载工具列表里，缺席不等于 host 不支持。存在则 Root 立即主动调用切入 Plan mode（用户拒绝后按只读 planning turn 处理），不要以「等用户手动切换」代替调用；确认不存在才由同一 Root 做只读 planning turn 并等明确执行授权 |
| 用户明确要求 implementation worker | 把它视为实现委派；Root 仍负责边界、集成和最终验证 |

纯问答、只读诊断、状态查询、修改全局 rule / skill / hook / settings，以及 `/ship`、`/review`、`/pr-review` 的内部流程不触发。

`update_plan` 只显示执行进度，不是 Plan mode，也不承载需求真相。

## 状态机

```text
DISCOVER (Plan/read-only)
  ├─ material decision → WAIT_INPUT → DISCOVER
  └─ decision complete → PLAN_READY
PLAN_READY + explicit execute request
  → EXECUTE
EXECUTE + next action needs fresh authority
  → AWAIT_ACTION_APPROVAL
  ├─ exact approval → EXECUTE (perform that action once)
  └─ denied/changed → DISCOVER or COMPLETE (blocked/cancelled)
EXECUTE + local implementation complete
  → INTEGRATE → VERIFY
  → [INDEPENDENT_REVIEW] [UI_REVIEW]
  → COMPLETE
```

Root 始终拥有用户交互、最终 plan、共享决策、主工作区集成、失败路由和最终汇报。

## 开始实现前

1. 确认用户已授权当前实现；Plan mode 的最终 plan 只有在用户切回 Default 并要求执行后才算本地、可逆源码改动的实施授权。
2. 要落地 Edit/Write 且当前不在隔离 worktree 时，先加载 `use-worktree`；已在 worktree 内延续当前任务时跳过。meta 配置按 AGENTS 的独立 branch/worktree 路由处理。
3. 记录 `base_ref="$(git rev-parse HEAD)"`，检查 dirty tree，保护用户已有改动。
4. 项目 AGENTS/CLAUDE 已在 context 时直接检查 trigger 标记，否则读取；存在 trigger-on-touch 标记时加载 `scan-trigger-docs`。
5. 加载本次真正命中的架构、语言、Figma、文档或平台 skill。项目规则、precedent 或 authoritative final plan 已明确结构时不再加载 `architecture-first`；仅实施中出现未决的 material boundary surprise 时回到 discovery/Plan 决策。
6. 非平凡代码写入，以及任意规模但拟新增或扩大 validation/error handling/fallback 的写入，都须在首次 Edit 前加载 `lean-diff` 并冻结 prompt 字段 `validation_fallback_contract`；只有已确认不触及这些语义的微改动可跳过。默认值为 `NONE`；新 validation 只有能由用户/最终 plan、项目规则、权威外部契约或复现证据证明必要时才能列入。fallback 还必须由用户/最终 plan、项目规则或权威产品契约明确授权；失败 trace 只能证明故障，不能授权降级。每项写 `site/kind`、`evidence`、`invariant_owner`；fallback 另写 `degraded_result` 与 `recovery_or_failure_owner`。只有故障证据而无授权时，停在首次 Edit 前，由 Root 向用户展示 `fallback_proposal`：触发证据、不兜底的结果、拟议降级、数据/语义损失、恢复或失败 owner；默认建议不加，只有用户明确选择才能更新合同，未回复不算授权。该字段不是新计划或落盘工件。
7. 只有命中 `exec-plan` 的持久化边界时才写单文件 ExecPlan；同一 Root、同一任务、一次可完成的实现不落计划文件。

## 正交 gates

分别判断以下 gate；一个任务可命中零个或多个：

| Gate | 触发 |
| --- | --- |
| `needs_worktree` | 要落地源码写入且当前不在隔离 worktree |
| `needs_durable_plan` | 跨会话/host、多个 writer/worktree、不可逆迁移、长期 Goal、审计或用户要求计划文件 |
| `needs_parallel_write` | 至少两个写域互斥的实现单元，并行能明显缩短关键路径 |
| `needs_independent_review` | 用户要求独立/完整验收；或最终 diff 涉及认证权限、PII/安全、支付、持久化/schema/迁移、公共 API/跨模块契约、并发/缓存一致性、大范围架构边界；多个 writer 合并后也触发 |
| `needs_ui_review` | Figma handoff、动画、复杂 UI、主观视觉判断或用户明确要求 UI 验收 |
| `needs_explicit_approval` | 删除/覆盖数据、不可逆迁移、外部发布/消息/写入等需要新增权限的动作 |

需求歧义在 Plan mode 已解决后，不因“曾经有歧义”自动触发独立 review。Figma 只自动触发 UI gate；除非同时命中语义风险，不再启动另一套完整流水线。

### 独立 review 的强度

- `mandatory-risk`：认证/权限、PII/安全、支付、schema/持久化/迁移、公共 API/跨模块契约、并发/缓存一致性、大范围架构边界，以及多个 writer 的 fan-in。客观验证 PASS 后必须由 fresh、read-only verifier 验收；没有该能力时阻塞完成，Root 自审不能替代。
- `optional-requested`：任务本身没有上述风险，只因用户主动要求独立/完整验收而启用。用户随后可明确撤销。
- “不用 review / 我自己看”只撤销 `optional-requested`。若用户要豁免 `mandatory-risk`，Root 必须先列出具体未独立验收的风险并取得针对该风险的明确接受；更高层安全规则不允许豁免时仍阻塞。

### 实施授权与动作授权

Plan 接受、切回 Default 或“Implement”只授权当前 scope 内的本地、可逆源码/文档修改和计划内验证，不授权真实数据迁移、删除/覆盖数据、生产发布、外部消息或其他不可逆/外部写入。

每个 `needs_explicit_approval` 动作必须在执行前即时停在 `AWAIT_ACTION_APPROVAL`：解析准确目标，说明影响、备份/恢复或 rollback、是否可 dry-run，并请求该动作的明确授权。授权只覆盖所述目标、参数和当时状态的一次执行；目标、影响或动作变化后重新确认。没有授权时不得先做副作用再补问。

## 执行与委派

### 默认：委派 implementer 实现

1. 多步任务用 `update_plan` 维护 2–6 个结果导向步骤；单步改动不用计划 UI。
2. decision-complete 的实现默认交给 `implementer`：prompt 写清目标与完成条件、独占 ownership 与禁止触达范围、已冻结共享接口、`validation_fallback_contract`、必读项目文档、返回格式和允许的窄域检查（同 `parallel-subagents` 分派前冻结）。
3. Root 直接写的例外：单文件、无决策的微改动，集成级修正，验证失败的窄修，以及 host 无 subagent（此时 Root 串行实现）。Root 直接写也受同一 `validation_fallback_contract` 约束；共享清单、公共接口和最终合并文件始终由 Root 写。
4. worker 返回后，Root 检查实际 diff、越界写入、共享接口、用户已有改动，以及新增 validation/fallback 与合同逐项一致；未列入的本任务新增代码必须移除，或带证据回到 discovery，Root 不得事后自行补授权。完成必要集成修正后再进入统一验证；worker 的局部检查不能替代最终集成验证。
5. 用户追加局部实现细节时更新 execution checklist 后继续；不创建 amendment/status 文件。
6. 用户改变可观察行为、scope、架构、硬约束或验收标准时，暂停 writer，保留当前 diff，回到 DISCOVER/PLAN_READY 产出替代 plan；不要擅自回滚用户改动。替代 plan 必须完整复述此前已积累的用户实质决策，不能只写增量；已有 ExecPlan 时按 `exec-plan` 更新规则同步。

### 并行委派

命中 `needs_parallel_write` 时加载 `parallel-subagents`，把互斥写域交给多个 `implementer` 实例；每个 worker 必须知道其他 writer 同时存在，不得回退或覆盖他人改动。返回处理同上第 4 条。

### 增量 commit

- 每完成一个可独立验证的功能单元（实现完成且该单元的窄域检查通过）后，Root 即在任务 worktree 内按 `rules/commit-message.md` commit 一次，不把多个功能攒到任务收尾。
- 只 stage 本单元的明确路径；不卷入用户已有改动，`.reviews/`、`.specs/` 工件不提交。worker 仍不 commit，其 diff 由 Root 集成检查后提交。
- 中间态或验证失败不 commit；最终统一验证后的修复以后续 commit 落盘。push 和 PR 仍只在用户要求或 `/ship` 时发生。

## 轻量自作主张审计

`<repo-or-worktree>/.reviews/自作主张.md` 是本地、append-only 的实现判断日志，不是需求真相源，也不能代替用户授权。

- 用户、最终 plan、项目规则或直接 precedent 未决定，且存在两个以上合理实现时，Root 先判断该选择是否 material。改变可观察行为、scope、架构、硬约束或验收标准，以及新增会改变语义或丢数据的 fallback、默认值、转换、跳过或丢弃，都必须停下询问用户或回到 Plan；不得记一笔后继续。拿不准是否 material 时按 material 处理。
- 非 material、可逆且不改变业务语义的实现判断可以继续，但须在完成前追加一条（在派发 review 前或 review 返回后写，不在冻结窗口内写）；没有这类判断时不创建文件。机械命名、格式和已有规则唯一确定的实现不记录。
- 每条只写 `决定`、`依据`、`影响与回滚`，标题使用 `## YYYY-MM-DD HH:MM — <task>`；旧条目不得修改或删除。
- 日志只由 Root 写。worker 返回需要 Root 拍板的候选判断，不能直接写共享日志。

`.reviews/` 属于本地交付工件，`/ship` 不得暂存或提交。最终回复没有条目时明确写“自作主张：无”；有条目时汇总决定并给出日志绝对路径。

项目 AGENTS 指定了等价本地审计载体（如迭代日志）时，用项目路径替代默认文件；三字段与 append-only 约定不变。

## 文档影响

最终验证前检查实际 diff 是否改变 agent 需要长期知道的工作流、模块边界、项目结构、工具链、公共契约或反直觉约束。命中时加载 `agent-readable-docs` 更新对应项目文档；普通产品/UI/局部 bugfix 不为“留痕”强行写文档。

最终汇报的文档处置二选一：`NONE + 具体依据`（说明 diff 为何不含长期约束变化）或 `UPDATED + 路径列表`（路径须出现在 `git diff --name-only $base_ref` 或 untracked 清单中）。

## 验证

按 `rules/post-change-verify.md` 对最终候选源码执行一次相关验证。Root 可直接运行；命令很长、日志很大或只需机械结果时交给 `command-runner`（host 无此 agent 时由 Root 直接执行）。客观命令无需另起独立验证角色。

验证失败时：

- 实现问题：Root 直接窄修，大范围返工带失败证据重派 `implementer`；失效重跑细则见 `rules/post-change-verify.md` 失败路由；
- 环境/依赖问题：先做安全诊断，不能把它伪装成代码失败或交给新 writer 重写；
- 相同诊断连续两次没有进展：停止盲修，回到 Plan 或询问用户；回 Plan 后恢复执行仍需用户明确执行授权。同一 required gate 累计 FAIL 达 4 次（无论诊断是否更换）必须询问用户。

## 条件式验收路由

`needs_independent_review` 或 `needs_ui_review` 命中时，在客观验证 PASS 后先全文读取 [references/review-binding.md](references/review-binding.md)（候选身份冻结、fingerprint 绑定、verifier / UI reviewer 启动与失效规则），再启动对应验收。mandatory-risk 不可由 Root 自审替代；豁免须按「独立 review 的强度」逐项风险取得用户明确接受。

## Host fallback

- Codex / Claude 有原生 Plan：使用原生模式和原生提问工具；不要用 `update_plan` 冒充 Plan mode。
- 无原生 Plan：同一 Root 只读探索、给出 final plan，等用户明确 GO 后再写。
- 无 subagent：Root 串行执行；若独立 review 是硬门且没有 fresh reviewer 能力，明确报告阻塞，不能把自审标成独立验收。
- 非交互/无人值守 session：到达 WAIT_INPUT、PLAN_READY、AWAIT_ACTION_APPROVAL 或 mandatory-risk 阻塞，且本 session 无法取得用户输入时，输出最终 plan/待批动作清单并以 blocked 状态结束；不得自行视为已授权。
- 工具名差异只影响 adapter，不改变状态机和 gate。

## 用户覆盖

- “直接改 / 不用 Plan” → 在 Default mode 且目标足够明确时直接执行，验证不省略。
- “自己写 / 不用 worker” → Root 直接实现整段任务，集成与验证不变。
- “完整验收 / 独立验收” → 启用独立 verifier。
- “不用 review / 我自己看” → 只跳过 `optional-requested`；`mandatory-risk` 按上面的具体风险接受规则处理，动作权限确认始终独立。

## 完成条件

最终回复必须独立说明：完成的可观察行为、主要改动、实际运行的验证及结果、独立/UI 验收是否触发、自作主张审计、文档处置和未验证项/剩余风险。没有 PASS 证据时不要称为完成。

未触发或为空的项可合并为一行简报（如“独立/UI 验收：未触发；自作主张：无；文档：NONE（无长期约束变化）”）。单文件、行为符合用户显式要求，且 needs_independent_review / needs_ui_review / needs_durable_plan / needs_explicit_approval 均未命中、无自作主张条目、文档处置为 NONE 的微改动：只须说明改动内容、实际运行的验证及结果、剩余风险，外加“自作主张：无”；其余项仅在触发时报告。
