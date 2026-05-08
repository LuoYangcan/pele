---
name: architecture-first
description: Architecture-first decision framework for picking the right design pattern, UI architecture, or system architecture before writing or reviewing code. Maps the symptom you're hitting (≥3 if/else branches piling up, boolean flag explosion, copy-pasted similar logic across modules, state coupling, untestable side-effects, deep view-controller bloat, "where should this code live") to a specific catalog: GoF object patterns (Strategy / State / Factory / Observer / Decorator / Composite / etc.), UI architectures (MVC / MVP / MVVM / VIPER / unidirectional flow like Redux / TCA / Elm / Reducer), system architectures (Clean / Hexagonal / Ports & Adapters / Functional Core Imperative Shell), and anti-patterns (patchwork / copy-paste / symptom-only fixes / TODO debt). Use this skill whenever Claude is about to add a new abstraction, pick a UI layer architecture, decide where a piece of logic lives in a layered project, refactor a fat ViewController / Service / Manager, introduce state management, or review a diff that does any of the above. Skip for typos, single-line localized fixes, formatting / rename, or changes that have only one obviously-correct shape (no architectural choice involved).
---

# architecture-first

写新代码 / review 代码前**先选对模式**：现在这块逻辑该用哪一类设计模式（GoF）？UI 层用什么架构（MVC / MVP / MVVM / VIPER / 单向数据流）？这块代码该放在系统架构的哪个边界（Clean / Hexagonal / Functional Core）？

skill 的核心姿态：**问题特征驱动选型**——看你正在踩什么坑（if/else 累积 / 状态难追踪 / VC 1500 行 / 跨模块复用 / 难单测），从对应 references 拿候选模式，结合项目约束选一个，**显式给出选这个不选那个的理由**。

延伸资料按需 Read（看到主表格指引再去读）：

- `references/gof.md` — GoF 经典对象级模式（Strategy / State / Factory / Builder / Observer / Decorator / Adapter / Facade / Composite / Command / Chain of Responsibility / Visitor + Singleton 警告）
- `references/ui-architecture.md` — UI 层架构选型（MVC / MVP / MVVM / VIPER + 单向数据流 Redux / TCA / Elm / Reducer）
- `references/system-architecture.md` — 系统架构（Clean / Hexagonal / Ports & Adapters / Functional Core Imperative Shell）
- `references/anti-patterns.md` — 4 类「打补丁」反例 + 重构方向 + 技术债登记正反例

## 不触发场景

- typo / 单行 fix / format / rename
- 在已有逻辑里做窄域追加（明显归属现有类型 / 没有架构选型空间）
- 用户明确「这次别走流程」/「先这么打补丁，下个 sprint 再改」
- 纯解释 / 问答 / 配置 / 文档

## 三层决策（顺序就是优先级）

### 0. Reality-check 闸口（**强制门禁，必过**）

在做下面任何决策前，先 **grep / Read 验证 user 描述的现状**——不通过这一步就**禁止往下走**。

**强制 grep 清单**：

- user prompt / 题目里**点名的文件 / 类 / 函数 / 模块**——都用 `grep -rln` / `find` 验证存在
- user 描述的**症状链路**（"X 调 Y 调 Z"）——sample 验证 ≥1 处真有这个调用
- user 提到的**第三方库 / 框架**——查 `Package.swift` / `package.json` 等是否真的在依赖列表里

**reality-check 失败时（任一项不通过）的处理**：

> ⛔ **不要继续往 §III 选模式 / 给方案**。
>
> 1. **先反驳 user 假设**：「你说的 X / Y / Z 在代码里实际不存在 / 不是你描述的样子」（附 grep 结果 + file:line 引用）
> 2. **重新刻画真实症状**（基于代码现状，不是 user 描述）
> 3. **再判断是否真需要架构变更**——很多时候 user 描述的"架构问题"在 reality-check 后退化成具体 bug / 异步竞态 / 缺测试，根本不需要重构
> 4. 用户确认你的现状描述后，再回到 §I 走全局思维

**为什么这条是 §0 而不是 §I 的子项**：架构决策的 ROI 极高（影响代码图）也代价极高（改一片）。基于错误前提给出的"激进重构方案"= 最贵的反模式。skill 引导的是**模式选择**，不替你做**前提验证**——这条强制门禁就是把验证显式纳入 skill 流程。

### I. 全局思维（看清问题再选模式）

reality-check 通过后，问三件事：

- 这个改动会影响**哪些调用方 / 跨哪些模块**？grep 一下被改的函数 / 类型，看上下游
- 同样的问题**别的模块怎么解决**的？先看现状、再选模式
- 这个改动在**更大的代码图**里是什么角色：UI 层重构 / 业务层重构 / 跨层边界重新切？

**只看当前文件 / 当前函数就动手** = 局部最优、全局崩坏的高发区。Junior 套模式因为「看起来该用」，senior 选模式因为「问题就在这」。

### II. 反补丁（在选模式之前先识别坏味道）

下面 4 类都是「补丁式信号」，看到先停下，按 `references/anti-patterns.md` 选重构方向：

1. **在已有函数里加 `if/else` 特判 / boolean flag** —— 函数被强塑成多种联动语义。考虑 Strategy / State / 拆函数。
2. **复制粘贴改变量名 / 不看调用链只改当前文件** —— 缺全局视野；类似逻辑出现 ≥3 处 = 抽公共。
3. **看现象不查根因（顶 try/catch / default 值完事）** —— 让问题隐身不是修复；下次以另一种症状出现成本更高。先 5-Why 找根因。
4. **TODO / 「以后再优化」类遗留账** —— 明知反设计但不修。要么当下就修；要么**显式登记技术债**（commit 关联 ticket / 进 docs/tech-debt.md），不是埋在注释里。

> 关键：补丁式写法的危险不是它「现在不工作」，而是它**累积**。三五次同类补丁后，原模块的设计意图已经死了，重构成本指数上升。

### III. 模式选型（根据问题特征找候选）

下面这张表把**症状 → 候选模式 / 架构 → 必读 references** 写死。看到症状就 Read 对应文件再决定：

| 症状 | 候选 | 必读 |
|---|---|---|
| 函数 ≥3 个 `if/else` 准备加第 4 个 | Strategy / State / 拆函数 | `gof.md` Strategy + State |
| 函数签名带 ≥3 个 boolean / mode 参数 | Strategy / 拆函数 | `gof.md` Strategy |
| 行为差异**取决于对象当前状态** | State / 状态机 | `gof.md` State |
| 创建对象需要按条件选不同子类 | Factory / Abstract Factory / Builder | `gof.md` Factory |
| 构造参数 ≥5 个 + 有可选参数 | Builder | `gof.md` Builder |
| 一个事件**多处响应** + 来源 / 消费者解耦 | Observer / Pub-Sub | `gof.md` Observer |
| 想给对象**动态加能力**（log / 缓存 / 限流） | Decorator | `gof.md` Decorator |
| 老 API 接口不匹配新 API | Adapter | `gof.md` Adapter |
| 想给一组复杂子系统提供简单入口 | Facade | `gof.md` Facade |
| 多步独立串行处理 | Pipeline / Chain of Responsibility | `gof.md` Chain |
| 错误是**业务上的合法分支**（不是异常） | Result / sum type | `gof.md` Result section |
| 想新建 class 继承 base 只为加一个能力 | Composition over Inheritance | `gof.md` Composition |
| **VC / Service 1000+ 行，逻辑 / 视图 / 网络混在一起** | MVVM / VIPER / Reducer | `ui-architecture.md` 全文 |
| **state 散落在多处 / 难追踪状态变更** | 单向数据流（Redux / TCA / Elm） | `ui-architecture.md` 单向数据流 |
| **多端共用业务逻辑 / 难单测** | Clean / Hexagonal / Ports & Adapters | `system-architecture.md` 全文 |
| **副作用（IO / 网络 / db）跟核心逻辑混在一起** | Functional Core Imperative Shell | `system-architecture.md` Functional Core |
| **跨业务模块复用受依赖方向限制** | 中间件（protocol + 注入）+ Composition | `gof.md` Composition + 项目 `AGENTS.md` 依赖分层 |

### IV. 复用 vs 新建（架构选好后才到这里）

复用的优先级（每往下一档都要给走这一档的理由）：

1. 直接复用现成 API
2. 优雅扩展（加参数 / overload / extension）
3. **小重构 + 复用**（含设计模式 / 架构模式引入）
4. 下沉抽出到共享层
5. 走中间件（跨模块依赖方向受限时）
6. 才造新轮子

## Checklist（动手 / review 时按顺序勾）

> **快路径警告**：第 2 步 grep 直接命中现成实现且语义吻合 → 给一行结论收尾。但**不要**因为答案"看起来明显"就跳过深挖。Senior code review 的工作姿态是 grep 出 `file:line` 引用，不是套模板。

### 0) Reality-check（**强制门禁，不过禁止往下**）

- [ ] user 点名的**每个文件 / 类 / 函数**都已经 `grep -rln` / `find` 验证存在
- [ ] user 描述的**调用链路 / 依赖关系**至少 sample 验证 ≥1 处
- [ ] user 提到的**第三方库 / 框架**已经在 `Package.swift` / `package.json` 依赖列表里
- [ ] **任一项不通过** → 跳到「先反驳 user 假设 + 重新刻画真实症状」，**不要**继续往 §III 选模式

reality-check 失败的产出格式：

```
🚨 前提校准（reality-check 不通过）

user 描述的：<X 文件 / Y 类 / Z 调用链>
仓库实际：<grep 结果，file:line 引用，或「零命中」>

→ 真实症状（基于代码现状重新刻画）：<...>
→ 是否还需要架构变更：<可能不需要 / 仍需要但 scope 变了 / ...>
→ 请确认这个现状描述，再讨论方案
```

### 1) 任务边界（全局思维）

reality-check 通过后再走这一步。

- [ ] 改动会触达哪些文件 / 调用方 / 模块（grep 一下）
- [ ] 同 repo 类似需求的现有解法是什么
- [ ] 这个改动在更大代码图里的角色：bug fix / 新增能力 / 行为变更 / 架构调整

### 2) 搜过现有实现了吗

- [ ] grep 函数名 / 类名 / 关键词的多个变体
- [ ] 翻过相关 package 的公开 API + 项目说明（`AGENTS.md` / `CLAUDE.md` / `docs/*.md`）
- [ ] 翻过 `Package.swift` / `Package.resolved` 看已有依赖能不能直接用
- [ ] **第三方 SDK 尤其谨慎**：引一个 = 永久维护 + 升级 + 体积成本

### 3) 反补丁自检

任一命中就停下，按 `references/anti-patterns.md` 选替代方案：

- [ ] 在已有函数里加 `if/else` / boolean flag
- [ ] 复制别处代码改变量名
- [ ] `try/catch` 吞错 / default 值掩盖症状
- [ ] 写 `// TODO: 之后优化`

### 4) 模式 / 架构选型

对照 §III 的症状 → 候选表：

- [ ] 我的问题是不是表里的某条症状？
- [ ] 候选的 references 我读过了吗？（不读就不要选）
- [ ] 我能不能写下来「为什么选这个候选 不选那个候选」？

如果选不出来，说明你**问题特征还没看清** —— 回到 §I 重新分析，不要凭直觉选模式。

### 5) 跨 package 依赖方向（项目硬约束）

复用对象在哪一层、你在哪一层、依赖方向是否合法（参考项目 `AGENTS.md` 的依赖分层表）。Business 层之间通常**禁止**互依——需要复用就**下沉**到共享层或**走中间件**（protocol + 注入），不抄代码。

### 6) 决定新建 / 选了某个模式？写出理由

新建之前 / 选模式之后能用一句话说清「为什么这个比其他候选更好」：

- 「现有 X 只支持 A 场景，扩展会污染单一职责，所以走 Strategy」 ✅
- 「VC 已经 1500 行 + state 散布 + 测试覆盖率 0% → MVVM 比 MVC 边际收益更大」 ✅
- 「我懒得搜 / 我喜欢这个模式 / 别人都用」 ❌

## 与 simplify 的关系

- **architecture-first**（本条）：动手**前** + review 中介入**架构 / 模式选型**决策。**不写代码**，产出 checklist 和「该用哪个模式 / 该放哪一层 / 该不该重构」的判断。
- **simplify**（内置）：改完代码**后** spawn 3 个并行 review subagent（复用 / 质量 / 效率），**自动 fix**。
- 一次任务可串行：开干前 architecture-first 把方向 + 模式定对 → 迭代收尾时 simplify 扫尾。

## 不做的事

- ❌ 不直接 Edit / Write 代码
- ❌ 不替代项目自己的 `AGENTS.md` / 架构文档（那是项目特定规范，本 skill 是通用框架）
- ❌ 不替代 `/review` 的深度评审
- ❌ 不强制套模式——简单 if-else / 简单 MVC 是允许的，要求是**显式给出"为什么这次不需要更复杂模式"的理由**

## Why

junior 写代码靠**直觉 + 套模板**，senior 写代码靠**问题特征驱动选型**。模式 / 架构是工具，不是目的——硬塞 Clean Architecture 到一个 200 行的 hobby app 比直接写 MVC 更贵；该上 MVVM 的时候坚持 fat VC 也是一样的代价。

这条 skill 把「停下来想清楚」物化成 §III 的症状-候选-references 决策表，让 agent 不再是"看到 if/else 多就建议拆 Strategy"的反射，而是先识别问题特征 → 找对应 references → 选合适候选 → 写出选这个不选那个的理由。
