---
name: lean-diff
description: Single source of truth for the "don't be verbose / don't pile patches / don't write defensive crap" judgment, applied at two moments — write mode (generator self-checks before each Edit / Write) and review mode (executor / /review tags issues). Catalogs three families: comments (verbose-comment / task-bound-comment / removal-marker / stale-todo), patchwork bloat (patchwork-bloat / over-abstraction), and defensive code (silent-catch / defensive-unwrap / defensive-fallback). Skip for typo / format / rename diffs, comment-only doc edits, and lint-only fixes — those don't carry these failure modes.
---

# lean-diff

写代码 / 审代码时的**精简判断标准**：

1. 注释啰嗦
2. 堆 patch 不删旧 / 不复用现有
3. 过度防御性代码（吞错 / 多余 unwrap / 假 fallback）

generator 在写代码前用 **write 模式**自检；executor / `/review` 在审代码时用 **review 模式**列 issue。两边走同一份判断标准、同一套 issue_type 命名 —— 单一真相源避免漂移。

## 使用方式

### Write 模式（generator 在 Step 3 invoke）

每次 Edit / Write 前过一遍 §自检清单（write）。命中任何一条 → 改回去再落地。

### Review 模式（executor 在 Step 5 / `/review` subagent invoke）

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
| `task-bound-comment` | 引用当前任务 / fix 编号 / caller | `// 用于 X 流程`、`// 为修 #123` |
| `removal-marker` | 删除残留 | `// removed`、`// renamed from X` |
| `stale-todo` | 没截止 / 没责任人的 TODO | `// TODO: 之后优化` |

#### 例外（**不算 issue**）

- `// MARK: -`（Swift 章节切片，IDE 友好）
- `// PLANNER-FEEDBACK iter-N: 待澄清`（generator 留给 planner 的占位标记）
- 引用项目 doc / 引用第三方 issue 链接的 `// see docs/x.md` 类指针注释

#### Severity 规则

- 默认 **warning**
- 单文件命中 ≥ 5 处 → 升级为 **blocking**（说明这个文件整体在用注释当 commit message，必须打回）

### 2. 堆 patch 类

#### 写代码前先问 4 问

- 已有方法能扩参数达成吗？
- 已有类型加字段能达成吗？
- 已有 helper / extension 能复用吗？
- 三段相似分支能合成一段吗？（不要为 DRY 强行抽象，参考 architecture-first 的 premature abstraction 红线）

减 1 行比加 1 行优先。非加不可时，宁可在已有处加而不是新建。

#### Issue type

| issue_type | 触发 | severity |
|---|---|---|
| `patchwork-bloat` | 新建方法 / 类型 / 文件，但 grep 显示已有可复用入口；非 spec 第 6 节硬约束要求新建 | warning |
| `over-abstraction` | 引入新 protocol / Manager / Service / 配置参数 / feature flag / **单调用方包装类**，但 spec 没要求、当前调用方只有 1-2 处 | warning |

「单调用方包装类」识别要点：一个新类（常见命名 `XxxCoordinator` / `XxxService` / `XxxManager` / `XxxHelper`）只是把另一个已有 API 转一手 —— init 只存依赖、方法只 forward 调用、本身**没**额外逻辑（重试 / 状态转换 / 跨调用 state / 多依赖编排），且 grep 显示只一处调用方。这种包装层既不为单测带来 seam（因为反正只一处用），也不复用，纯增加跳转层 → over-abstraction。例：`VoiceMessageUploadCoordinator { init(service); upload(data) { try service.upload(data) } }` 在唯一调用点只是 `coord.upload(data)` 一次就丢 —— 直接 `service.upload(data)` 即可。

#### 例外

- spec 第 6 节硬约束**明确要求**新建（例：spec 写「在 X 模块新增 FooService 协议」）→ 跳过
- architecture-first skill 已经评估并选了「拆函数 / 引入新模式」→ 跳过（前置已有更高优先级判断）
- 包装类**有**额外逻辑（重试策略 / 状态机 / 跨调用 cache / 多个依赖的编排）→ 不是 over-abstraction，跳过

### 3. 过度防御代码类

#### 默认契约

- 内部代码互相调用、framework 给的 non-optional → **不验证、不 try/catch**
- 只在系统边界验证（user input / external API / file IO）
- 不为「这种情况不会发生」加分支

#### Issue type

| issue_type | 触发 | severity |
|---|---|---|
| `silent-catch` | `try?` / `catch { }` 静默吞错（除非 spec 明确要求容错） | **blocking** |
| `defensive-unwrap` | 验证不可能发生的情况（framework 保证 non-optional 还 `guard let` 早 return） | warning |
| `defensive-fallback` | 加 fallback / default 值掩盖错误根因（例：网络失败默默返回空数组而不是向上抛） | warning |

#### `silent-catch` 为何 blocking

吞错让 bug 隐身 —— 下次同一个根因以另一种症状出现，调试成本指数上升。如果 spec 明确要求「失败时静默 / 失败时降级」（例：埋点上报失败不影响主流程），generator 必须在代码处加注释说明出处（`// silent by spec §X`），否则 review 标 blocking。

#### 例外

- spec 第 6 节硬约束 / 第 4 节测试用例**显式要求**容错路径
- 框架钩子要求实现的 default 值（`Equatable.==` 之类的协议 witness）
- 注释里显式标了 `// silent by <出处>` —— 视为 generator 已经意识到、且有据可查

## §自检清单（write 模式）

generator 在 Edit / Write 前过一遍：

- [ ] 我加的注释属于「why 非显然」吗？还是在解释 what / 引用任务编号 / 留 stale TODO？
- [ ] 这段新代码对应的功能，能否扩 / 改已有方法 / 类型 / helper 达成？
- [ ] 我引入的抽象（protocol / Manager / Service / 配置参数 / flag）当前真有 ≥3 处调用方吗？还是为「未来扩展」准备？
- [ ] 我写的 `try?` / `catch { }` 是否吞错？spec 真要求静默吗？
- [ ] 我的 `guard let / else { return }` 是 framework 保证 non-optional 还硬验证？
- [ ] 我的 fallback / default 值是不是在掩盖错误根因？

任一项答「是」→ 改回去再落地。

## §issue 输出契约（review 模式）

executor / `/review` 把命中条目放进 `issues` 数组，每条按上方 §使用方式 的格式。**issue_type 严格用本 skill 表里的字段名** —— 主 agent 在 review-fix 阶段可以按 type 一键归类（「全部修注释类」/「只修 blocking 的 silent-catch」）。

## 与其他 skill / rule 的关系

- **architecture-first**：管「选模式 / 选边界」（不写代码）。本 skill 是 architecture-first 之后的一道补充判断 —— architecture-first 决定要不要新建抽象、本 skill 检查实际落地是否过度。两者正交。
- **simplify**（内置）：simplify 改完代码后跑 3 个 review subagent + 自动 fix。本 skill 只产判断 + issue 列表，不自动 fix。可以串：simplify 跑完后 executor 用本 skill 再扫一遍。
- **dead-code**：dead-code 管"无人调用"（孤儿符号）；本 skill 管"该不该写"（写之前 / 写之后的判断）。两者正交。
- **post-change-verify** rule：本 skill 不跑 build / lint。lint 工具能抓的格式问题（空格 / 缩进 / 行长）属于 swift-formatting 的领域，本 skill 重点放在工具抓不到的语义级问题。

## 不做的事

- ❌ 不写代码（review 模式只产 issue 列表；write 模式只产自检结论）
- ❌ 不替代 swift-formatting / SwiftLint 的格式检查
- ❌ 不替代 architecture-first 的模式选型决策
- ❌ 不在 spec 第 6 节硬约束有冲突时硬扛 —— spec 是法律，spec 显式要求的容错 / 防御 / 多余抽象不算 issue
- ❌ 不替主 agent 决定 review-fix 是否采纳 —— 那是用户挑

## Why

把这套判断标准下沉到 skill：

- **单一真相源**：generator 写时用、executor 审时用 —— 同一份 issue_type 表，不会一边漏判、一边错判
- **新增 issue type 改 1 处**：例如未来想加 `unnecessary-async`（无意义的 async 关键字），只在本 skill 加一条，generator / executor SOP 不动
- **跨 agent / `/review` / 别的 subagent 复用**：除了 generator + executor，未来 `/review` skill / `/codex:review` / 别的代码 review 工具都可以 invoke 本 skill，不必再各自抄判断标准
- **issue_type 命名一致**：主 agent 在 review-fix 阶段按 type 归类操作（「采纳全部 blocking」/「跳过 verbose-comment」），是基于 type 名一致才可行
