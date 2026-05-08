---
name: reuse-first
description: Reuse-first decision checklist before writing or reviewing new code. Search the codebase and already-pulled-in dependencies, then prefer direct reuse → graceful extension of an existing API → creating new (last resort). Use when Claude is about to introduce a new abstraction (helper / utility / extension / component / Service / Manager / module / package), a new third-party SDK / dependency, or is reviewing a diff that introduces any of these — and especially when the decision crosses module / package boundaries where dependency-direction rules might apply. Skip for localized bug fixes, formatting / style tweaks, or narrow additions to clearly-existing logic with no plausible alternative — in those cases the checklist adds overhead without changing the answer.
---

# reuse-first

写新代码前 / review 代码时，**先确认有没有现成的可以用**。这条 skill 不写代码——它给 Claude 一份「动手前 / 评审时」的复用决策 checklist，让结论是「先复用、再扩展、最后才造新轮子」。

## 什么时候触发这条 skill

**写代码前**（准备引入「新抽象」时触发）：

- 新建 helper / utility / extension（不是给现有类型加一个明显归属它的方法 overload）
- 新建 UI 组件 / Service / Manager / Repository / DataSource
- 跨 package 抄逻辑 / 跨 package 复用（哪怕只是几行）
- 引入新的第三方 SDK / 库
- 新建一整个 module / package

**Review 代码时**：

- 走 `/review` 或 PR review 流程
- 用户给一段 diff / commit / 文件让你提意见，且 diff 里有「新增的抽象 / 新增的依赖」
- 用户问「这段代码写得好不好 / 有没有更好的办法」

**不触发**（强烈建议跳过——硬走 checklist 反而拖时间）：

- 改单行 bug / typo
- 格式 / 代码风格调整 / rename
- **给已有逻辑做窄域追加**——比如在已存在的 manager 里加一个明显归属它的方法、给已有 if-else 加一个分支、修一个 nullable 处理。没有合理的「复用替代」可比时不需要走 checklist。
- 用户已经明确说「我知道有现成的，但故意要重写」
- 纯解释 / 问答 / 配置 / 文档

## 核心原则

复用的优先级，从高到低：

1. **直接复用**——现成 API 满足需求，直接调
2. **优雅扩展**——现成 API 差一点，加一个参数 / overload / extension 补齐
3. **下沉抽出**——两处类似的逻辑出现在不同模块，抽到更底层的共享层
4. **走中间件**——跨模块复用受依赖方向限制时，定义协议 + 运行时注入
5. **才造新轮子**——以上都不成立，且新建的成本和复杂度可控

每往下一档，都要在 checklist 里**显式给出走这一档的理由**——而不是直接跳到第 5 档。

## 动手前 Checklist（写代码场景）

按顺序勾，**勾不过的不要继续往下**。

> **快路径**：第 1 步搜代码时如果**直接命中**了现成实现（grep 一下就在同 package 或已依赖的 package 里、且语义吻合），可以**折叠**剩下几步，只写一行结论：「已有 `<X at file:line>`，直接用，不引新 dep」。Checklist 是为「答案不明显」的场景服务的，不是仪式——明显的复用案不要硬撑形式。

### 1) 我搜过现有实现了吗？

- [ ] 用 `grep` / `Grep` 搜过函数名 / 类名 / 关键词的若干变体
  - 例：要写「toast 提示」→ 搜 `toast` / `Toast` / `Notification` / `Banner` / `HUD`
  - 例：要写「hex → Color」→ 搜 `hex` / `init.*hex` / `UIColor.*hex`
- [ ] 翻过相关 package 的公开 API（`public` 类型 / `public` 函数）
- [ ] 看过项目说明文档（`AGENTS.md` / `CLAUDE.md` / `README.md` / `docs/*.md`）里点过名的「请走 X」的指引

如果项目有专属的资产入口（如统一 theme 管理类、统一 router、统一通知 manager），**先看入口暴露了什么**。

### 2) 我搜过现有依赖能否覆盖了吗？

- [ ] 翻过 `Package.swift` / `Package.resolved` / `package.json` / `requirements.txt` / `go.mod`，看已有依赖能不能直接用
- [ ] 看过同 repo 其他 package / 模块怎么解决类似问题的（同样的需求大概率有人写过）

**对第三方 SDK 尤其谨慎**：引一个新 SDK = 永久维护 + 升级风险 + 二进制体积。引之前必须能回答「现有 X SDK 为什么不够」。

### 3) 我考虑过「扩展」而不是「新建」了吗？

- [ ] 现有类型 / API 离需求差多少？只差一个参数 / 一个 overload？→ 扩展它
- [ ] 现有组件能不能加一个可选配置项支持新需求？
- [ ] 如果选择新建，新建出来的东西**是不是基本和现有的重复，只是名字不一样**？

### 4) 跨 package / 跨模块复用，是否符合依赖方向？

这条**特别**重要——不少「新建」的根因，是想复用但不能跨 package 直接引用。

**先看项目的依赖分层规则**（一般在 `AGENTS.md` 或 `docs/architecture.md`）。常见模式：

```
common  ← 最底层，跨平台共享
  ↑
platform-base / UI / Core  ← 平台基础层
  ↑
business / feature / app  ← 业务最上层
```

业务层之间通常**禁止互相依赖**。当复用需求跨业务模块时，按以下顺序处理：

- a) 复用对象本就属于更底层（common / 基础层）→ **直接加依赖** 即可
- b) 复用对象在另一个业务模块里、而你也是业务模块 → **下沉**到 common / 基础层后再依赖；**不要**让业务模块互相依赖
- c) 复用对象是「app 层独有的服务实现」（推送 token、登录态、特定 SDK 包装）、又必须在底层用到 → **走中间件**：在底层定义 protocol + 默认 no-op，app 启动时注入真实实现

走中间件不是逃避复用——它是**承认依赖方向不允许直连，但能力本身要复用**。比直接抄代码好得多。

### 5) 如果决定新建，这条结论我能写出来吗？

新建之前，能用一句话说清「为什么以上 1-4 都不成立，新建是更好的选择」：

- 「现有的 X 只支持 A 场景，要支持 B 场景需要改它的核心契约，扩展会污染单一职责」 ✅
- 「找不到任何相关现成实现」 ✅（前提是真的搜过）
- 「这是一个全新领域 / 全新功能，没有先例」 ✅
- 「我懒得搜 / 不想看现有代码」 ❌
- 「现有的写得不好，我想重写一份」 ❌（除非这就是任务本身）

## Review 场景 Checklist

收到 diff / PR 时，用这份 checklist 反向核查：

- [ ] **新增的函数 / 类型，是否在 repo 别处已经有了？**搜全名、搜关键词。
- [ ] **新增的扩展（`extension Foo`）**，扩展的目标类型在哪里？同一个 module 别处是不是已经扩展过类似方法？
- [ ] **新增的依赖**（`Package.swift` 加了一行 / `package.json` 加了 dep），README / 已有 deps 能不能覆盖？
- [ ] **新增的组件 / Service**，是不是基础层已经有更通用的版本？
- [ ] **跨 package 抄过来的代码**：原 package 在本 PR 里仍然保留这份代码吗？保留 = 重复实现；删了 = 应该改成依赖关系。
- [ ] **「再写一份是因为方便」的迹象**：参数命名风格突然不一致 / 文件名带 `XxxV2` / 注释里写「TODO: 后面统一」/ 同名类型在不同文件里出现。

发现重复时，review 意见格式（建议）：

```
🚨 重复实现：<新增的 symbol> 与 <已有的 symbol at file:line> 功能相同

建议：
- 删掉新增的
- 直接调用 <已有的>，或扩展它支持 <差异点>
- 如果跨 package 引用受限，走 <中间件方案 / 下沉到 X package>
```

## 常见反例（要警惕的"造轮子"信号）

- 给类型加 `extension` 之前没看现有 extension —— 同名扩展可能已存在
- "随手加个 helper" —— helpers 是重复实现的高发区，**先搜**
- "这个 SDK 我熟，加上吧" —— 现有 SDK 大概率能覆盖；先评估再引
- 在业务模块 A 写了一份和业务模块 B 一样的逻辑 —— 应该下沉或走中间件
- 复制粘贴一段代码改两个变量名 —— 抽函数 / 抽方法
- "新建一个 manager 来管这件事" —— 先看现有 manager 能不能扩

## 这条 skill 不做的事

- ❌ 不直接 Edit / Write 代码
- ❌ 不替代项目自己的 `AGENTS.md` / 架构文档——那是更具体的项目规范，本 skill 是通用决策框架
- ❌ 不替代 `/review` 的深度评审——本 skill 只关注「复用 / 重复」这一维度
- ❌ 不强制 100% 复用——有合理理由的新建是允许的，要求是**显式给出理由**
- ❌ 不替代 Claude Code 内置 `simplify` skill 的事后清理——两条 skill **正交**，时机不同：
  - **reuse-first**（本条）：动手**前** + review 中介入决策。**不写代码**，只产出 checklist 和「复用 / 扩展 / 新建」的判断。
  - **simplify**（内置）：改完代码**后** spawn 3 个并行 review subagent（复用 / 质量 / 效率），**自动 fix**。
  - 一次任务里两条可以串行用：开干前 reuse-first 把方向定对 → 迭代收尾时 simplify 扫尾 cleanup。前后顺序不冲突，不要让两条同一时刻都触发去做相同的事。

## Why

代码库里最难发现的债不是 bug，是**重复实现**：

- 两份功能相同但行为微妙不一致的工具函数
- 三个 toast 组件，新人不知道用哪个
- 两个 package 里各自有一份 hex → Color 的扩展
- 同一类配置散落在 4 个 manager 里

发现得越晚，统一成本越高。在写之前 / review 时多问自己一句"现成的有吗"，比合并后再做 dedup PR 便宜一个数量级。这就是为什么这条 skill 要在所有写代码 / review 任务上**默认触发**——它是预防型成本，不是事后清理。
