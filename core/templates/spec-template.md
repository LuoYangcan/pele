# Spec: <短标题>

> 创建于 `<YYYY-MM-DD>` · worktree slug: `<slug>` · 分支: `<type/scope-slug>`

> **结构**：本文件是**主索引**。§1/3/4/5/6 内联（每轮都要 hot-load 的 permanent reference）；§2/7/8/9 是索引行表、详情拆到 `.specs/<slug>/{tasks,risks,amendments}/<id>.md` 子文件。子文件是 scratchpad，完成态项目（DONE task / RESOLVED risk / DONE AMD）的详情不需要每轮 hot-load。iOS UI 改动触发时 planner 还会在 `.specs/<slug>/assets/` 冻结 figma 设计稿 PNG（generator / ui-reviewer 直接 Read，不再调 figma MCP）。
>
> **审计文件**：`.specs/<slug>/decisions.md` 是 planner / generator 在每次跑（含 iter 重试）时**追加**的审计日志，装「自作主张细节 / 存疑点（想问但没问的）/ 对 spec 的隐含偏差 / 借鉴的现有 pattern」四类，让用户审 spec / 收尾时一次性回看。**追加专用**，已有章节绝不修改 / 删除。模板见本文件末尾「decisions.md 模板」段。

---

## 1. 用户原始需求

> 把用户最初的原话保留在这里，不要复述、不要"翻译"。后续回看时这是单一真相源。

```
<用户原话粘贴在这里>
```

## 2. 需求拆分（索引）

按"做完哪些子任务，整体需求就达成"来拆。每条要可以独立验证、**必须列出涉及的文件/模块** —— 这是并行分组判断的依据。

**详情拆到** `.specs/<slug>/tasks/task-N.md`（planner 写 spec 时一次性建好每个 task 的子文件骨架；generator 干这个 task 时把 scratchpad / 进度注记写到子文件、不污染主索引）。

### 子任务索引表

| ID | 标题 | 涉及文件 / 模块 | 详情 |
| --- | --- | --- | --- |
| task-1 | <具体动作一句话> | `src/foo.ext, src/bar.ext` | [详情](.specs/<slug>/tasks/task-1.md) |
| task-2 | ... | ... | [详情](.specs/<slug>/tasks/task-2.md) |

### 并行分组（≥3 子任务时由 planner 填；<3 写"全部串行"）

判断规则：
- **可并行**（标 `parallel-N`，N=1, 2, ...）：子任务文件边界**完全不重叠** + 不互相依赖类型 / API
- **必须串行**（标 `serial`）：共享文件 / A 是 B 的依赖 / 改同一个 enum / 改同一个 dependency manifest（如 `Package.swift` / `package.json` / `Cargo.toml` / `requirements.txt`）
- 至少有一个 `serial` 组兜底（哪怕只装 1 个 task）
- ⚠️ 误判代价：把有依赖的标成 parallel → generator 并行撞文件 / 后跑的拿不到前一个的 API → 整组失败。**宁严不松**，拿不准就归 serial。

| 组 ID | 包含子任务 | 类型 | 隔离/串行依据 |
| ---- | ---------- | ---- | ------------- |
| parallel-1 | [task-1] | 并行 | <为什么独立——文件边界 / 模块边界> |
| parallel-2 | [task-2] | 并行 | <为什么独立> |
| serial | [task-3 → task-4] | 串行 | <为什么必须按顺序——共享文件 / API 依赖> |

或：

> **全部串行**（子任务 <3）

子任务数 ≥3 但 planner 评估后发现确实没有可并行的子任务（全部互相依赖）→ 仍按"全部串行"写，并在判断规则下方加一行说明原因（如"本需求所有子任务都触及 `FooViewModel` 单一类型，无法并行"）。

## 3. 分工角色

谁做哪一块，分清楚才不会撞车。

| 角色 | 负责的子任务 | 备注 |
| ---- | ------------ | ---- |
| 主 agent（Claude）| #1, #2 | |
| subagent | #3（独立模块，无依赖）| 用 `parallel-subagents.md` |
| 用户确认 | UX 文案 / 配色 | |

如果整个需求都主 agent 自己做，写一行"全部主 agent 做"即可，不用画表。

## 4. 测试用例

**这一节不能含糊带过**——三类（Golden Path / 边界 / 回归）每类**至少列 1 条具体场景**。**禁止**写 "TBD" / "待补" / "看情况" / 占位符不删；如果某一类真的不需要，**删掉那一小节并写一行说明原因**。

每条格式：`<操作 / 触发条件> → <期望结果>`，可勾选。

### Golden Path（主流程必须通 · 口语也叫"冒烟"）

> 严格意义上 Golden Path（happy path）≠ 冒烟测试：Golden Path 是"主流程从头到尾完整跑通"，冒烟是"系统起得来 / 不崩"。这一节按 **Golden Path** 来写——更深、更覆盖业务逻辑。日常说"测一下冒烟"通常也是这个意思。

主流程从开始到完成的最小可验证路径——产品核心功能"在用对了"的判断依据。

- [ ] <场景 1，例：在 onboarding 第一页点"继续" → 跳到第二页且进度条 50%>
- [ ] <场景 2，例：完成 onboarding → 落到 Home tab 且看到欢迎卡片>
- [ ] ...

**iOS UI 改动专项**（触发信号：改了 SwiftUI/UIKit view、改了图片资源、改了样式/布局/颜色、需求里出现 UI 字眼。任一命中则**必填**至少 1 条；不触发则删掉本小节）：

**Figma 设计稿引用**（触发条件同上 iOS UI 专项；用户提供了 Figma URL 才填，没有写「无 Figma 设计稿，按 §1 用户原话和下面 mobile-mcp 冒烟条目实现」）：

**参考稿列表**（每行一个 figma node；冒烟用例 >1 条且各对应不同 node 时「对应用例」列填 `case-N` 绑定，只有 1 条用例或单 node 通用时填 `*`。`<nodeId-safe>` = nodeId 把 `:` 替换成 `-`）：

| 对应用例 | Figma URL | 节点 ID | 页面 / 屏幕名 | 本地设计快照（planner 抓） |
| --- | --- | --- | --- | --- |
| `*` | `<https://figma.com/design/<fileKey>/<fileName>?node-id=<X-Y>>` | `<X:Y>` | <例如「Composer / Empty State / Dark」> | `.specs/<slug>/assets/figma-<nodeId-safe>.png` |

**设计契约快照**（planner 抓 figma 后填，generator / ui-reviewer 视觉对照的真相源）：

> planner 调用 figma MCP `get_design_context` + `get_variable_defs` 后整理；generator Step 4.5 / ui-reviewer 不再调 figma MCP，直接 Read 本节 + 上面「本地设计快照」列下的 PNG 视觉对照 mobile-mcp 实拍图。

- **Frame 尺寸**：<例 375 × 200 pt>
- **关键 spacing**：<例 外 padding 16pt / VStack spacing 12pt / icon-text gap 8pt>
- **关键 typography**：<例 标题 SF Pro Display semibold 17pt / 正文 SF Pro Text regular 14pt 行高 20pt>
- **关键 colors（设计 token 名优先）**：<例 background → `<DesignSystemPackage>.Color.surface` / accent → `<DesignSystemPackage>.Color.primary`>
- **图层结构**：<一段简短描述 z-order 与对齐：例「VStack { HStack { 24×24 icon + 17pt title }, 14pt body text, 44pt height button }；全部左对齐、外层 16pt padding」>
- **设计 variables**（`get_variable_defs` 拿到的关键 token 列表）：<例 `spacing/sm = 8 / spacing/md = 16 / color/primary` 等>

抓 figma 失败时本段写：`figma 抓取失败：<原因>；generator 实现前需 planner 重抓 / 用户手动补 .specs/<slug>/assets/figma-*.png`，并在 §7 加 OPEN risk。

- **设计稿覆盖范围**：<列出本次实现要对齐的关键面：**图标大小 / 间距 (padding, margin, gap) / 控件样式 (圆角, 描边, 阴影) / 颜色 / 字号 / 行高 / 字重 / 图层结构 / 对齐 (左/中/右/baseline)**；不在 scope 的视觉调整明确踢出>
- **对齐严格度**（默认 `strict`，除非用户在 §6 硬约束里明确写降级）：
  - `strict`：图标大小、间距、控件样式、颜色、字号**全部 1:1 还原**，肉眼 diff 即视为不通过；generator 不允许凭感觉调一两个 pt，要改必须 §9 AMD 显式记下并附原因
  - `loose`：只对齐版式骨架（哪个元素在哪一行哪一列）+ 颜色 token，间距 / 字号允许 ±2pt 误差，需在本字段写明降级原因
- **generator 使用方式**：Read `.specs/<slug>/assets/figma-*.png` 设计快照（planner 已冻结）+ 上方「设计契约快照」段 → 用 mobile-mcp 拉实拍截图视觉对照；token 名核对走「设计 variables」字段。generator 不调 figma MCP —— 设计更新走 planner 重抓快照 + AMD
- **ui-reviewer 视觉验收**：见 `~/.claude/skills/review-mobile-ui/SKILL.md` Step 5.b 视觉层 —— ui-reviewer 跑每条用例时 Read「本地设计快照」列下的 PNG 与 mobile-mcp 实拍图对比；按「对齐严格度」字段判定（`strict` 下视觉层不符 → blocking `ui-figma-mismatch`；`loose` 只看版式骨架 + 颜色 token）。assets/ 下设计快照缺失 → warning（不阻断整体 verdict），全部缺失 → `ui_verified: degraded`

**mobile-mcp 冒烟用例**：

- [ ] **mobile-mcp 冒烟**：<scheme + 进入哪个页面 + 做什么操作 + 看什么视觉/行为结果>
  - 例：`<YourApp>iOS-Dev` → 打开「设置」tab → 点"主题" → 看到新加的卡片在最顶部、深色模式下背景色正确、点击有 push 动画
- [ ] ...

> 不要写「打开模拟器跑一下」这种空话；要具体到页面、操作、可观测结果。macOS UI 改动不强制本项。

### 边界 / 异常

不正常输入 / 非典型场景 / 失败路径——**review 时最容易抓 bug 的地方**，尽量穷举。常见思考维度：

- **数据**：空 / 极长 / 极短 / 0 / 负数 / 特殊字符 / Unicode / Emoji
- **网络**：断网 / 慢网 / 超时 / 401 / 5xx / 重试
- **权限**：被拒 / `.limited` / 撤销 / 首次申请
- **系统**：低内存 / 后台杀进程 / 锁屏 / 来电 / 系统弹窗打断
- **交互**：多次点击 / 快速连点 / 双指 / 拖拽中断 / 横竖屏切换
- **时序 / 并发**：先 A 后 B vs 先 B 后 A、动画进行中操作
- **设备 / 版本**：iOS 18 vs iOS 26 / iPhone SE vs iPad / Mac Catalyst

每条例：

- [ ] <例：用户拒绝相册权限 → 弹"去设置"引导；返回后授权状态自动刷新>
- [ ] <例：拉取超时 30s → 显示"加载失败 + 重试"按钮，不无限转圈>
- [ ] <例：连续点 5 次"提交" → 只发 1 个请求，按钮立即 disable>
- [ ] ...

### 回归（不能破坏的旧功能）

跟本需求**有交叉**的现有功能——本次改完要手动跑一遍确认没碰坏：

- [ ] <旧功能 1>：<快速验证方式>
- [ ] <旧功能 2>：...

如果确实没有相关旧功能，写一行 "无相关旧功能" 即可。

## 5. 验收标准（Done Definition）

明确"做完是什么样"。下面这几条是基础项，按需增减：

- [ ] 编译通过：跑项目的 build 命令（按平台 / 子项目）
- [ ] 第 4 节列出的 golden path 全部肉眼/手测验证过
- [ ] 第 4 节列出的边界场景至少快速过一遍
- [ ] 没有引入新的 lint / format 警告
- [ ] **iOS UI 改动专项**（触发条件同第 4 节，命中则必勾；macOS UI 改动不强制）：mobile-mcp 跑通 golden path 无 crash + 视觉符合预期
- [ ] **Figma 设计稿还原**（仅当第 4 节列了 Figma URL + planner 抓快照成功时勾；无 Figma / 抓失败则跳过本项 + §7 留 OPEN risk）：generator 在 Step 4.5 Read `.specs/<slug>/assets/figma-*.png` 设计快照 + §4「设计契约快照」段，用 mobile-mcp 拉实拍截图视觉对照；按 §4「对齐严格度」字段验收 —— `strict` 模式下图标大小 / 间距 / 控件样式 / 颜色 / 字号 / 字重 / 行高 **全部 1:1** 对齐，肉眼 diff 不通过即视为 FAIL；diff 截图存到 `.reviews/<slug>-figma-diff-*.png`
- [ ] <项目特定>：...

## 6. 硬约束

落地位置 / 不能动的东西 / 必须遵守的接口。

- **落地位置**：<具体到 app / package / 模块 / 文件>
- **不能动的接口/文件**：<列出 freeze 的部分>
- **必须遵守的现有规范**：<比如某个 Manager / Registry / Service 协议>
- **不在本次 scope 的事**：<明确踢出去，避免顺手扩 scope>

## 7. 风险 / 边界 / 存疑点（索引）

写下"我（Claude）当前不确定"的部分。这些是 7 回合 checkpoint 时优先回顾的项。

**详情拆到** `.specs/<slug>/risks/risk-N.md`（planner 第一次列 risk 时建文件；用户/讨论后拍板了就把对应 risk-N.md 的 status 改 `RESOLVED` + 在子文件追加「解决」段——主索引这里 status 同步刷新即可）。

### 风险索引表

| 状态 | ID | 类型 | 摘要 | 详情 |
| --- | --- | --- | --- | --- |
| OPEN | risk-1 | ❓ 存疑 | <一句话> | [详情](.specs/<slug>/risks/risk-1.md) |
| OPEN | risk-2 | ⚠️ 风险 | <一句话> | [详情](.specs/<slug>/risks/risk-2.md) |
| RESOLVED | risk-3 | 🚧 边界 | <一句话> | [详情](.specs/<slug>/risks/risk-3.md) |

如果完全确定无疑问，写一行 "无明显存疑点" + 删表 / 跳过子目录。

类型字段取值：`❓ 存疑点` / `⚠️ 风险` / `🚧 边界`。

## 8. 进度状态（索引）

> §8 是 generator 维护的状态视图，**§2 是真相源**。冲突时 generator 按 §2 自救校准 §8 后继续，不要停手等指令。完整规则见 `~/.claude/rules/dispatch-pipeline.md` 「§8 进度状态写权限边界」段。

每完成一个子任务：(1) 改子文件 `tasks/task-N.md` 的 `**状态**` 字段；(2) 同步刷新本表对应行 status。

### 进度索引表

| 状态 | ID | 摘要 | 详情 |
| --- | --- | --- | --- |
| TODO | task-1 | <一句话> | [详情](.specs/<slug>/tasks/task-1.md) |
| DOING | task-2 | <一句话> | [详情](.specs/<slug>/tasks/task-2.md) |
| DONE | task-3 | <一句话> | [详情](.specs/<slug>/tasks/task-3.md) |

状态字段取值：`TODO` / `DOING` / `DONE`。每条 task 同时出现在 §2 索引表和 §8 索引表——§2 列文件范围 + 并行分组，§8 列实时 status。

## 9. Amendments（索引）

> **用途**：实现阶段用户追加的具体指令（bug fix / review-fix 挑出的修复项 / 临时新增的具体要求）一律**追加**到此处，**不修改 §1-7**——保持原始需求快照纯净，方便回溯"最初想要什么"。
>
> **详情拆到** `.specs/<slug>/amendments/AMD-N.md`（planner / generator 追加 AMD 时新建子文件 + 在本表加一行索引；本表行内不写指令正文，只放摘要 + 链接）。

> **写权限（与 §8 同为共写域，与 §1-7 的 planner-only 不同）**：
>
> - **planner** 在二次调用时追加：场景 A 用户决策是实现层指令（bug fix / 微调）→ Write 新建 `amendments/AMD-N.md` + Edit 本表加索引行；场景 A 用户决策是真改硬约束 / 拆任务 → 仍 Edit §1-7（不走 amendment）
> - **generator** 在迭代中追加：用户在主对话里直接提具体指令（bug fix / 改某处效果） → Write 新建 `amendments/AMD-N.md` + Edit 本表加索引行 → 再动手实现
> - 双方都**只追加、不修改、不删除**已有 AMD 子文件的「触发」/「指令」/「影响范围」字段（保留审计痕迹）；状态字段 TODO ↔ DONE 由当事 agent 推进时改子文件 + 本表行
>
> **executor 验收**：
>
> - status=**DONE** 的 amendment 与 §1-7 等价、**必须验收**；Read 对应 `amendments/AMD-N.md` 子文件、核对「指令」/「影响范围」是否真满足；不满足 → issues 里标 `amendment_ref: AMD-N`
> - status=**TODO** 的 amendment **跳过本轮验收 + 跳过 Read 子文件**（视为"下一轮 generator 的范围"，与 §8 TODO 子任务同处理）

### Amendment 索引表

| 状态 | ID | 作者 | 时间 | 摘要 | 详情 |
| --- | --- | --- | --- | --- | --- |
| TODO | AMD-1 | [planner 写] | YYYY-MM-DD HH:MM | <一句话指令摘要> | [详情](.specs/<slug>/amendments/AMD-1.md) |
| DONE | AMD-2 | [generator 写] | YYYY-MM-DD HH:MM | <一句话指令摘要> | [详情](.specs/<slug>/amendments/AMD-2.md) |

状态字段取值：`TODO` / `DONE`（用户撤销某条时改成 `~~CANCELLED~~` + 在子文件追加原因）。作者字段：`[planner 写]` / `[generator 写]`。N 编号全局自增（不分作者）。

### 初始状态

> 暂无 amendments。

## 10. Review 流程（仅说明，不需填写）

> 本节是给用户 / generator / executor / 主 agent 看的元说明，**spec 编写者不用填**任何内容。完整定义见 `~/.claude/agents/executor.md` Step 6.5 + `~/.claude/rules/dispatch-pipeline.md` 阶段 3A PASS 后流程。
>
> **时机**：executor verdict==PASS 后**自动**跑一次外部 reviewer subagent（Opus 4.7 extended thinking，~5-10 分钟）。review 与 verdict 解耦——report 中的 findings **不影响** PASS/FAIL、**不进** executor 的 issues list、**不进** retry 循环。
>
> **报告位置**：`.reviews/<branch>-<ts>-executor.md`（gitignored；`/openpr` 推 PR 前会自动清理）。后缀 `-executor` 与主动 `/review` 跑的报告区分。
>
> **review issues 处理路径**：
>
> 1. 主 agent 拿到 verdict==PASS + review 报告元信息 → 展示给用户（review_verdict / 各类 findings 计数 / 一句话摘要 / 报告绝对路径）
> 2. AskUserQuestion 问「review 怎么处理」，选项含「全部采纳修」/「只修 must-fix」/「自己挑」/「跳过」
> 3. 用户挑修 → 主 agent 调 generator → generator 按 §9 Step 2.1 把要修的项 append 成 AMD（`[generator 写]`）→ 实现 → 改 AMD 状态 DONE
> 4. retry executor（主 agent 显式传 `run_review_subagent: false`，**不重跑 review**） → verdict==PASS 后直接进「文档同步问询」环节，不再回到 review 闸口
>
> **bypass**：
>
> - 用户在主对话里**显式说**「跳过 review」 → 主 agent 调 executor 时显式传 `run_review_subagent: false`
> - 用户主动跑 `/review` 或 `/codex:review` slash command 永远可用（任何时候都可以），但产物落在 `.reviews/<branch>-<ts>.md`（无 `-executor` 后缀）
>
> **review 在哪种场景不跑**：
>
> | 场景 | review 跑不跑 |
> | --- | --- |
> | 第一次 executor，verdict==PASS | ✅ 跑 |
> | 第一次 executor，verdict==FAIL（编译/lint/spec 任一失败） | ❌ 不跑（fast-fail，retry 期间不浪费时间） |
> | 阶段 4 retry，verdict 仍 FAIL | ❌ 不跑 |
> | 阶段 4 retry，verdict==PASS | ✅ 跑（终态 review） |
> | 阶段 3A PASS 后 review-fix 引起的 retry | ❌ 不跑（review 已采纳） |
> | 并行模式 3B 各组单独验收 | ❌ 不跑（留给阶段 5 整体跑） |
> | 并行模式阶段 5 最终验收 | ✅ 跑 |

---

# 子文件模板

> 下方是 `.specs/<slug>/{tasks,risks,amendments}/` 三类子文件的模板。planner / generator 按需 Write 新建子文件时复制对应段。

## tasks/task-N.md 模板

```markdown
# task-N: <一句话标题>

**状态**: TODO | DOING | DONE
**涉及文件 / 模块**: `<files>`
**并行分组**: parallel-N | serial

## 详情

<task 的完整描述、本 task 的验收子条件（如果细于 spec §5 的整体 done definition）>

## 进度注记（scratchpad，generator 维护）

<generator 干这个 task 时的过程笔记：碰到的问题 / 选的方案 / 备忘 / 关键代码位置链接。task DONE 后这部分会随主索引 status 一起从 hot context 退出>

> 初始内容为空——planner 创建子文件时只填上面 §状态/涉及文件/并行分组 + §详情，进度注记由 generator 推进时追加。
```

## risks/risk-N.md 模板

```markdown
# risk-N: <一句话标题>

**状态**: OPEN | RESOLVED
**类型**: ❓ 存疑点 | ⚠️ 风险 | 🚧 边界

## 详情

<完整描述：是什么 / 为什么不确定 / 可能的几种解释或缓解思路>

## 解决（status=RESOLVED 时填）

YYYY-MM-DD —— <用户/讨论后的拍板内容；保留原话或一句话总结>
```

## amendments/AMD-N.md 模板

```markdown
# AMD-N: <一句话指令摘要>

**状态**: TODO | DONE
**作者**: [planner 写] | [generator 写]
**追加时间**: YYYY-MM-DD HH:MM

## 触发

<场景一句话；例："用户在阶段 2.5 review-fix 里挑的" / "用户决策同步阶段提的" / "用户对话直接说 X">

## 指令

<具体要做什么、改哪里、达到什么效果。一段或多段，按需要详细写>

## 影响范围

<涉及的文件 / 模块；如新增子任务，主索引 §2 / §8 也要加对应索引行>
```

## decisions.md 模板

```markdown
# Decisions Log: <slug>

> planner / generator 每次跑（含 iter 重试 / 二次调用）都**追加**一节；不修改、不删除已有章节。
> 用户在 planner 返回、generator 完成、review-fix 后任意时刻 Read 本文件做审计。
> 已经 append AMD 子文件 / 在 spec 里改了 §1-7 内容的事项**不再**重复写本文件 —— decisions.md 专门装那些**没**触发 AMD / 没改 spec 但 agent 自己做了判断的事。

---

## <planner | generator> / iter-N / YYYY-MM-DD HH:MM

**触发**: <一句话，例「初次写 spec」/「实现 task-1, task-3, AMD-2」/「按 review 报告修复 lint + nits」>

### 自作主张

<没问用户但做出的实现细节判断；例「按 UIKit extension 切片拆 5 个文件」/「task 拆成 3 个因为 X」/「按钮颜色用 design token X 而不是 hex」。无 → 写 `- 无`>

### 存疑（想问但没问）

<边界 ambiguity，没用 AskUserQuestion 但记下来供用户事后审；例「按钮点击是否要 haptic feedback，我先没加」/「reply 引用的图标是否要 tint，先按 default」。无 → 写 `- 无`>

### 对 spec 的隐含偏差

<spec §1-6 写 A、实现成了 A'，原因 X；planner 初次写一般无、二次调用 / generator 实现时可能有。无 → 写 `- 无`>

### 借鉴的现有 pattern

<参考的代码位置 / 项目惯例；例「沿用 <ProfileModule>.AvatarEditVC 的 modal 接入路径」/「按 docs/composer/voice.md §1 longPressOverlay 段写 passthroughTester」。无 → 写 `- 无`>

---
```

> 章节命名：`<作者> / iter-N / 时间`。N 在文件内全局自增（不分 planner / generator）。每次 append 一节都在最末尾，旧节不动。四个子段固定写全，无内容写 `- 无`（让用户一眼看出 agent 确认过这一项、不是漏写）。

---

> 完成所有 DONE、走 `/openpr` 推 PR 之前，把整个 `.specs/<slug>.md` 主索引文件**和** `.specs/<slug>/` 子目录一起删掉。
> 
> 如果发现这个需求不需要 spec（比如 1-2 行小修），可以创建空文件 `.specs/<slug>.skip` 跳过本流程。
