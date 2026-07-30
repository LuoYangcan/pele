# Planner fan-out / fan-in contract

本文件是 `dispatch-pipeline` 阶段 1P 的结构化契约。Lead Planner、`planner-worker`、`spec-integrator` 和主 agent 在进入并行规划前全部 Read。

## 1. 模式选择

Lead Planner 完成用户澄清、仓库全局扫描和 Figma 冻结后选择：

- `serial`：预计子任务 `<3`；或无法形成至少 2 个边界独立的 planning shard；或共享契约尚未明确。继续由 Planner 写正式 spec。
- `fanout`：预计子任务 `>=3`，且能形成 2–3 个只写独立 draft 的 shard。Lead 只写 planning manifest，不写正式 spec。

首版只允许一个 wave、2–3 个 shard。更大的需求由 Lead 合并成 2–3 个领域 shard；无法安全合并就走 `serial`。Lead/Integrator 返回后释放并发槽，主 agent 直接派叶子 worker。

首版 fan-out 的每个 shard 必须 `depends_on: []`；存在 planning 先后依赖就走 `serial`，不得把同 wave 当 pipeline。

## 2. 工件与单写者

```text
.specs/<slug>.md                              # spec-integrator 唯一初始发布者
.specs/<slug>/
  planning-manifest.yaml                     # Lead/回调 Planner/Integrator 串行写
  drafts/<shard-id>.md                       # 对应 planner-worker 单写
  reports/<shard-id>.yaml                    # 对应 planner-worker 单写的持久结果
  questions/Q-<shard-id>-N.yaml              # 对应 worker 单写、发布后不改
  questions/Q-integrator-N.yaml              # spec-integrator 单写、发布后不改
  tasks/task-N.md                            # spec-integrator 初始写
  risks/risk-N.md                            # spec-integrator 初始写
  decisions.md                               # spec-integrator 初始写
```

- 主 agent 不直接 Edit 上述文件，只调度和转发用户原话。
- Worker 不写 canonical spec、manifest、decisions、tasks、risks、amendments 或其他 shard；自己的 report 是 join 状态真相源。
- `spec-integrator` 发布 canonical spec 前，不存在 `.specs/<slug>.md` 是正常状态。
- Generator/Executor 只消费集成后的正式 spec；不读 drafts/questions。

## 3. planning-manifest schema

Lead 使用下面字段；不需要的可省略，字段语义不能改：

```yaml
schema_version: 1
revision: 1
phase: planning_fanout
planning_mode: fanout
slug: <slug>
worktree: <absolute-path>
user_request: |-
  <用户原话>
global_constraints:
  - <已确认硬约束>
required_context:
  - <绝对路径或 repo 相对路径>
shared_contracts:
  - id: contract-1
    statement: <已冻结的跨 shard 契约>
resolved_decisions: []
unresolved_questions: []
shards:
  - id: planner-domain
    wave: 1
    input_revision: 1
    status: PENDING
    goal: <该 shard 要回答的问题>
    repository_scope:
      - <目录 / 模块>
    owned_draft: <absolute-worktree-path>/.specs/<slug>/drafts/planner-domain.md
    depends_on: []
    contracts:
      consumes: []
      produces: [contract-1]
    forbidden_decisions:
      - <不得自行决定的公共语义>
    expected_output:
      - tasks
      - acceptance_cases
      - risks
integration:
  status: PENDING
  canonical_spec: null
```

Manifest 是当前状态快照，不是 append-only 日志：

- 顶层 `revision` 是 control-plane 版本；每次 callback 或 Integrator 更新 manifest 都加 1。
- `shards[].input_revision` 是该 shard 的有效输入版本；只在它的 scope、context、contract 或用户决定变化时加 1。共享 contract 的 affected 集合固定为 `source/producer shard ∪ 全部消费者`；global 变化为全部 shards。
- Worker 的 `expected_revision`、draft/report 的 `based_on_revision` 都指对应 shard 的 `input_revision`，不是顶层 `revision`。因此 callback 后只需重跑 affected shards。
- `slug` 与 shard ID 只允许 lowercase kebab-case；`owned_draft` 必须是规范化绝对路径，且精确等于 `<worktree>/.specs/<slug>/drafts/<shard-id>.md`。禁止 `..`、斜杠或符号链接逃逸写域。
- `depends_on` 在 schema 中为未来扩展保留；当前版本必须为空。

## 4. Worker draft schema

```markdown
# Planning shard: <shard-id>

- based_on_revision: <N>
- status: DONE | NEEDS_USER_INPUT | NEEDS_ESCALATION

## Repository evidence
- `<path>:<line>` — <事实>

## Proposed tasks
- <可独立验收的任务、涉及文件/模块、依赖>

## Acceptance cases
- Golden Path: ...
- 边界 / 异常: ...
- 回归: ...

## Risks
- ...

## Contracts
- consumes: ...
- produces: ...

## Assumptions
- ...

## Open questions
- <无则写“无”>
```

Worker 只能基于 repo 证据和 manifest 已冻结语义提议，不得把推测写成事实。

## 5. Question callback schema

Worker/Integrator 发现无法从 repo、manifest 或已冻结 contract 推导的真歧义时，写唯一 question 文件并返回 `NEEDS_USER_INPUT`：

```yaml
question_id: Q-<shard-id>-1
source: <shard-id>
based_on_revision: <该 shard input_revision；integrator 问题填 manifest 顶层 revision>
blocking: true
scope: local | global
question: <主 agent 可直接问用户的一句话>
reason: <为什么无法自行推导>
options:
  - label: <选项>
    impact: <影响>
recommended:
  label: <推荐选项>
  reason: <证据>
affected_shards:
  - <shard-id>
```

主 agent 的处理顺序：

1. 让其他不受影响的 worker 跑完。
2. Read 所有新 question 文件，按语义去重；同一决策只问用户一次。
3. question 文件都按 blocking 处理并询问用户；非阻塞事实写进 draft assumptions，不创建 question。
4. 调强模型 Planner 的 `parallel_callback_sync` 模式，把用户原话、question ID 和选择写入 manifest：以 `question_id` 幂等同步；相同答案重试 no-op，答案变化则替换快照条目；仅实质变化时顶层 `revision + 1`，且只增加重新计算出的 `affected_shards` 的 `input_revision`。
5. 只重启 `affected_shards`；新 worker 必须读取各自新的 `input_revision`。

用户问题对应的 `resolved_decisions` 条目至少包含：

```yaml
- question_id: Q-<shard-id>-1
  answer: <采用的明确结论>
  user_quote: <用户回复原话>
  affected_shards:
    - <shard-id>
  resolved_at_revision: <更新后的 manifest 顶层 revision>
```

并行规划回调最多 3 轮；仍无法收敛就停止 fan-out，交给用户选择强 Planner 串行重规划或暂停。

## 6. Worker result schema

```yaml
status: DONE | NEEDS_USER_INPUT | NEEDS_ESCALATION | STALE_CONTEXT | FAILED
shard_id: <id>
based_on_revision: <N>
draft_path: <absolute-path>
question_files: []
escalation: null
evidence_count: <N>
summary: <一句话>
```

- Worker 在返回 `DONE | NEEDS_USER_INPUT | NEEDS_ESCALATION | FAILED` 前，把同一 YAML Write 到 `.specs/<slug>/reports/<shard-id>.yaml`；`STALE_CONTEXT` 不落盘，避免覆盖可消费的旧 report。
- `NEEDS_ESCALATION` 时 `escalation` 改为 `{scope: local | shared | global, reason: <原因>, contract_ids: []}`。公共 API/schema、共享协议、架构、安全、迁移、并发、数据一致性、硬约束或 scope 决策都走强 Planner，不让 Worker 猜。
- `STALE_CONTEXT`：启动或返回前发现自己的 shard `input_revision` 与 `expected_revision` 不同；不发布 `DONE`。
- `FAILED`：输入缺失、路径越界或无法读取必要上下文；主 agent 不进入 Integrator。

强 Planner 的 `parallel_shard_rescue` 分流：

- 调用必须带 expected manifest revision 与目标 shard input revision；启动和每次写前任一失配都返回 `STALE_CONTEXT`。
- `local` 技术复杂度：在当前 input revision 下只写该 shard draft + DONE report，其他 DONE 保留。
- `shared/global` 技术契约：先更新 `shared_contracts`，向 `resolved_decisions` 追加带 `decision_id`、证据和 affected shards 的强 Planner 决策；shared 的 affected = source/producer shard ∪ 全部消费者，global 的 affected = 全部 shards；顶层 `revision + 1`、全部 affected 的 `input_revision + 1`。不在同次调用写 draft/report，返回 `REPLAN_REQUIRED`，由 Root 重跑全部 affected shards。
- 产品语义、scope 或硬约束无法从用户原话/repo 推导：写 `Q-lead-N.yaml`，返回 `NEEDS_USER_INPUT`，不自行决定。

`resolved_decisions` 中的技术决策条目：

```yaml
- decision_id: D-lead-1
  source: lead-planner
  decision: <冻结的技术结论>
  reason: <为什么>
  evidence:
    - <file:line>
  affected_shards:
    - <shard-id>
  resolved_at_revision: <更新后的 manifest 顶层 revision>
```

## 7. Integrator 规则

只有下列条件全部满足才调用 `spec-integrator`：

- 全部 shard 的 report 都是 `DONE`；
- 每个 shard 恰有一份预期路径 `reports/<shard-id>.yaml`，report 的 `shard_id` 匹配、`escalation: null`，且不消费额外 report/draft；
- report 的绝对 `draft_path` 与 manifest 的绝对 `owned_draft` 一致；
- 每份 report/draft 的 `based_on_revision` 等于对应 shard 的 `input_revision`；
- 每个 blocking question 文件都有对应 `resolved_decisions.question_id`，且 manifest 没有 unresolved blocking question；
- draft 路径与 manifest `owned_draft` 一致。

冲突优先级：

1. 用户原话、全局硬约束；
2. `resolved_decisions`、`shared_contracts`；
3. repo 证据；
4. shard 提议。

Integrator 可去重、重编号、修正依赖和并行分组，并把 draft ID → canonical task/risk ID 映射写入 `decisions.md`。不得多数投票、扩大 scope 或替用户决定产品语义。发现新语义冲突时写 `Q-integrator-N.yaml` 并返回 `NEEDS_USER_INPUT`，不发布半份 spec。

发布成功后：

- 按现有 `spec-template.md` 写完整 `.specs/<slug>.md`、tasks、risks、初始 decisions；
- 根据 reports 把已消费 shard status 写成 `DONE`，再更新 manifest：`phase: integrated`、`integration.status: DONE`、`integration.canonical_spec`、`revision + 1`；
- 返回 `INTEGRATED`，主 agent 才进入原阶段 1 spec 自检和用户拍板。

## 8. 角色降级

- `planner-worker` 或 `spec-integrator` 未被当前 host 加载：不试错循环，不做半套 fan-out；重新调用强 Planner，传 `force_serial: true`，走原串行规划。
- Terra Worker 触发 `NEEDS_ESCALATION`：局部技术问题只升级该 shard；共享契约重跑 source/producer + 全部消费者，global 契约重跑全部 shards。
- 任何并行规划工件异常都不影响旧串行模式。

<!-- Why 核心：并行只产独立提案，正式需求真相始终由强模型单写者发布。 -->
