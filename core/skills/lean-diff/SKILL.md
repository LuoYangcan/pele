---
name: lean-diff
description: Lean-diff judgment standard covering comment noise, patchwork bloat, over-abstraction, speculative or duplicate validation, and defensive fallback. Use in write mode before edits and in review mode when tagging issues. This skill owns local copy/paste, TODO, validator, fallback, silent-catch, and premature-abstraction signals; they do not trigger architecture-first unless diagnosis requires an unresolved durable boundary change. Skip typo, format, rename, comment-only doc, and lint-only diffs.
---

# lean-diff

写代码 / 审代码时的**精简判断标准**：

1. 注释啰嗦
2. 堆 patch 不删旧 / 不复用现有
3. 过度防御性代码（吞错 / 多余 unwrap / 假 fallback）

implementation owner 在写代码前用 **write 模式**自检；verifier 或 `/review` 在审代码时用 **review 模式**列 issue。两边使用同一套 issue_type。

这些局部 anti-patch 信号由本 skill 直接处理，不因为出现分支、flag、copy/paste、fallback 或 TODO 自动升级成架构选型。

## 使用方式

### Write 模式

每次 Edit / Write 前过一遍 §自检清单（write）。命中任何一条 → 改回去再落地。

### Review 模式

扫被 review 的 diff，按 §issue_type 表给每个命中点产出结构化 issue：

```yaml
- severity: blocking | warning
  issue_type: <表里的 type 名>
  file: <path/to/file.swift>
  line: <如有>
  description: <一句话说清问题>
  suggested_fix: <如显然，给修复方向；不强求>
```

## 不触发

跳过的场景（这些 diff 不会触发本 skill 的判断标准）：

- typo / 单字符 fix / rename / 格式调整
- 仅改注释 / 文档（评论本身就是审查目标，不应再用本 skill 评注释）
- lint 工具自动修出来的改动（已经被工具兜底）
- 删除代码（本 skill 关注新增 / 修改的代码质量；删除天然符合「优先减少代码」）

## 三类判断标准

### 1. 注释类

#### 默认不写注释

好命名 + 类型已经说明 what。注释**只在 WHY 非显然时写** —— 隐藏约束、不变量、绕某个具体 bug、读者会困惑的行为。

#### 不该写的注释（看到要删 / 看到要标 issue）

| issue_type | 触发 | 例子 |
|---|---|---|
| `verbose-comment` | 解释 what（紧邻代码做的事） | `// 把 user 加进 list` 紧跟 `users.append(user)` |
| `task-bound-comment` | 引用当前任务、plan 章节、issue/fix 编号或临时 checklist | `// 为修 #123`、`// plan 要求...`、`// task-7` |
| `removal-marker` | 删除残留 | `// removed`、`// renamed from X` |
| `stale-todo` | 没截止 / 没责任人的 TODO | `// TODO: 之后优化` |

#### 例外（**不算 issue**）

- `// MARK: -`（Swift 章节切片，IDE 友好）
- 引用项目 doc / 引用第三方 issue 链接的 `// see docs/x.md` 类指针注释

#### 对照：写 why、不写 trace

`task-bound-comment` 禁的是“当时为什么动这行代码”的过程 trace。plan、task、PR 和 fix 编号会漂移或消失，注释应改写成长效因果。

但**why 注释是鼓励的**，前提是写**不随时间漂移的因果**：业务约束 / 系统行为 / 历史 bug / 性能取舍。判别：把这条注释拿给 1 年后、不知道当前任务存在的人看 —— 还能看懂吗？

| 禁止（trace，会死链） | 鼓励（why，长效） |
|---|---|
| `// plan 要求 UTC` | `// server 端按 UTC 存储，本地转换在 presenter 层做` |
| `// 本任务加的 retry` | `// iOS 17.4 NWConnection 首次握手有概率 ECONNRESET，retry 一次` |
| `// 为修 #1234 加的 guard` | `// pendingAttachments 在 dismiss 动画中可能被外部清空，nil check 不可省` |
| `// task-7 要求隐藏` | `// composer 在 picker 之上视觉错位，hide 由 caller-side scope 控制` |
| `// 用户在 review 里要求` | `// 主线程 layout 重入会触发 SnapKit 重算 → 必须 async` |

规则不是"少写注释"，是"删掉会死链的那部分、留住会长期帮人的那部分"。

#### Severity 规则

- 默认 **warning**
- 单文件命中 ≥ 5 处 → 升级为 **blocking**（说明这个文件整体在用注释当 commit message，必须打回）

### 2. 堆 patch 类

#### 写代码前先问 4 问

- 已有方法能扩参数达成吗？
- 已有类型加字段能达成吗？
- 已有 helper / extension 能复用吗？
- 三段相似分支能合成一段吗？不要为了 DRY 建没有真实变化轴的抽象。

减 1 行比加 1 行优先。非加不可时，宁可在已有处加而不是新建。

#### Issue type

| issue_type | 触发 | severity |
|---|---|---|
| `patchwork-bloat` | 新建方法 / 类型 / 文件，但 grep 显示已有可复用入口；用户/最终 plan 未要求新建 | warning |
| `over-abstraction` | 引入新 protocol / Manager / Service / 配置参数 / feature flag / **单调用方包装类**，但用户/最终 plan 没要求、当前调用方只有 1-2 处 | warning |

「单调用方包装类」识别要点：一个新类（常见命名 `XxxCoordinator` / `XxxService` / `XxxManager` / `XxxHelper`）只是把另一个已有 API 转一手 —— init 只存依赖、方法只 forward 调用、本身**没**额外逻辑（重试 / 状态转换 / 跨调用 state / 多依赖编排），且 grep 显示只一处调用方。这种包装层既不为单测带来 seam（因为反正只一处用），也不复用，纯增加跳转层 → over-abstraction。例：`VoiceMessageUploadCoordinator { init(service); upload(data) { try service.upload(data) } }` 在唯一调用点只是 `coord.upload(data)` 一次就丢 —— 直接 `service.upload(data)` 即可。

#### 例外

- 用户或最终 plan 的硬约束明确要求新建 → 跳过
- authoritative final plan 已批准 material architecture change，且当前抽象是该决策的必要落地 → 跳过
- 包装类**有**额外逻辑（重试策略 / 状态机 / 跨调用 cache / 多个依赖的编排）→ 不是 over-abstraction，跳过

### 3. 过度防御代码类

#### 默认契约

- 内部代码互相调用、framework 给的 non-optional → **不验证、不 try/catch**。
- 输入结构/字段语义只在不可信输入首次进入系统的 owner 边界验证（user input / external API / file IO），只验证构造可信内部值所必需的不变量；下游直接消费该可信类型。
- 一个不变量只有一个验证 owner：decoder/parser 管结构，domain constructor 管业务不变量，transport adapter 管 request/response 关联，状态机或消费侧管时序、session、authorization context。下游可以验证自己新增的上下文不变量，不得重复上游已经建立的同一不变量。
- 新 validation branch/helper/type 必须能指向用户/最终 plan 的要求、权威外部契约，或可复现的失败 fixture/trace。仅凭「可能出现」「更安全」不算证据。
- 错误默认上抛或显式失败。fallback 必须由用户/最终 plan、项目规则、权威产品契约或已冻结的行为测试明确授权，并写清降级结果与恢复或失败归属；失败 fixture/trace 只能证明故障，不能授权降级，实现者自述也不算。不为「这种情况不会发生」加分支。
- 有失败证据但没有 fallback 授权时，write mode 不落代码，向 Root 返回 `fallback_proposal`：`trigger/evidence`、`without_fallback`、`proposed_degraded_result`、`data_or_semantic_loss`、`recovery_or_failure_owner`。默认选择仍是不加 fallback；用户未回复不算授权。

#### Issue type

| issue_type | 触发 | severity |
|---|---|---|
| `silent-catch` | `try?` / `catch { }` 静默吞错，且不满足下方统一例外 | **blocking** |
| `speculative-validator` | 新 validation 无上述证据或无法说明唯一 owner；状态机/消费侧验证其自有时序/session/context 不变量不算 | **blocking** |
| `duplicate-validator` | 同一不变量在多个层重复验证；消费侧新增的时序/session/context 不变量不算重复 | **blocking** |
| `defensive-unwrap` | 验证不可能发生的情况（framework 保证 non-optional 还 `guard let` 早 return） | warning |
| `defensive-fallback` | 用 fallback/default/lossy decode/clamp/drop-invalid 把失败伪装成可用结果，但没有证据与明确产品降级契约 | **blocking** |

当 `try?`、空数组/空字符串默认值、lossy collection decode、跳过坏 item 或通用 unknown case 把失败/未知输入改成看似可用的结果时，属于 fallback；权威 schema 定义的语义默认值、保留原始值供上层判断的 unknown 表示，以及 owner 状态机拒绝不属于当前 session/时序的事件且不合成替代结果，都不算 fallback。

#### `silent-catch` 为何 blocking

吞错让根因以其他症状出现。如果需求明确要求失败静默或降级（如埋点失败不影响主流程），implementation owner 应写长效因果注释，而不是引用 plan 章节。

#### 统一例外

- 下列例外适用于本节全部 issue type。
- 用户、最终 plan、项目规则、权威外部契约或复现失败的测试用例显式要求 validation；fallback 仍须满足上面的产品授权条件
- 框架钩子要求实现的 default 值（`Equatable.==` 之类的协议 witness）
- 对允许静默的失败写明稳定业务原因和失败边界；注释本身不能替代上面的证据

## §自检清单（write 模式）

implementation owner 在写入前过一遍：

- [ ] 我加的注释属于非显然 why，还是在解释 what / 引用 plan、task、fix 编号 / 留 stale TODO？一年后还能看懂吗？
- [ ] 这段新代码对应的功能，能否扩 / 改已有方法 / 类型 / helper 达成？
- [ ] 我引入的抽象（protocol / Manager / Service / 配置参数 / flag）当前真有 ≥3 处调用方吗？还是为「未来扩展」准备？
- [ ] 每个新 validation branch/helper/type 能否指向用户/最终 plan、权威契约或复现 fixture/trace？它是否位于该不变量唯一的 owner 边界？
- [ ] 同一不变量是否已由上游 owner 建立，下游又验了一次？下游检查的是否真是自己新增的时序/session/context 不变量？
- [ ] 我写的 `try?` / `catch { }` 是否吞错？需求真要求静默吗？
- [ ] 我的 `guard let / else { return }` 是 framework 保证 non-optional 还硬验证？
- [ ] 我的 fallback/default/lossy decode/drop-invalid 是否既有外部证据，又有明确产品降级结果与恢复或失败归属语义，而不是掩盖错误根因？
- [ ] 只有故障证据、没有产品授权时，我是否停在 Edit 前并返回 `fallback_proposal`，而不是替用户决定？

任一违规项命中，或证据/owner/降级语义答不出来 → 不落地；review mode 标 blocking issue。

## §issue 输出契约（review 模式）

verifier 或 `/review` 把命中条目放进 `issues` 数组，每条按上方格式。`issue_type` 严格使用本 skill 表里的字段名，Root 可按 type 路由修复。

## 与其他 skill / rule 的关系

- **architecture-first**：只解决未决 durable boundary；本 skill 处理局部 anti-patch/reuse hygiene。代码坏味道本身不升级，只有诊断证明修复必须改变 boundary 时才进入架构决策。
- **cleanup backend**：Claude 用 `/simplify`；Codex 用 `codex-simplify`。cleanup 自动 fix；本 skill 只产判断和 issue 列表。
- **dead-code**：dead-code 管"无人调用"（孤儿符号）；本 skill 管"该不该写"（写之前 / 写之后的判断）。两者正交。
- **post-change-verify** rule：本 skill 不跑 build / lint。lint 工具能抓的格式问题（空格 / 缩进 / 行长）属于 swift-formatting 的领域，本 skill 重点放在工具抓不到的语义级问题。

## 不做的事

- ❌ 不写代码（review 模式只产 issue 列表；write 模式只产自检结论）
- ❌ 不替代 swift-formatting / SwiftLint 的格式检查
- ❌ 不替代真正的 material boundary 决策；局部坏味道仍由本 skill 收敛
- ❌ 不与用户或最终 plan 的硬约束冲突；显式要求的容错、防御或抽象不算 issue
- ❌ 不替主 agent 决定 review-fix 是否采纳 —— 那是用户挑

## Why（核心）

- implementation owner 与 reviewer 使用同一份 issue_type 表
- 新增 issue type 只改本 skill
- 跨 agent / `/review` 复用：未来别的 review 工具直接 invoke
- issue_type 命名一致：主 agent review-fix 按 type 归类操作可行
