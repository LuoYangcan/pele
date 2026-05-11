# Spec: <短标题>

> 创建于 `<YYYY-MM-DD>` · worktree slug: `<slug>` · 分支: `<type/scope-slug>`

---

## 1. 用户原始需求

> 把用户最初的原话保留在这里，不要复述、不要"翻译"。后续回看时这是单一真相源。

```
<用户原话粘贴在这里>
```

## 2. 需求拆分

按"做完哪些子任务，整体需求就达成"来拆。每条要可以独立验证、**必须列出涉及的文件/模块** —— 这是并行分组判断的依据。

### 子任务列表

- [ ] **task-1** — <具体动作>
  - 涉及文件 / 模块: `<src/foo.ext, src/bar.ext>` 或 `<src/features/your-module/>`
- [ ] **task-2** — ...
  - 涉及文件 / 模块: ...
- [ ] **task-3** — ...
  - 涉及文件 / 模块: ...

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

- [ ] **ios-simulator-mcp 冒烟**：<scheme + 进入哪个页面 + 做什么操作 + 看什么视觉/行为结果>
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
- [ ] **iOS UI 改动专项**（触发条件同第 4 节，命中则必勾；macOS UI 改动不强制）：ios-simulator-mcp 跑通 golden path 无 crash + 视觉符合预期
- [ ] <项目特定>：...

## 6. 硬约束

落地位置 / 不能动的东西 / 必须遵守的接口。

- **落地位置**：<具体到 app / package / 模块 / 文件>
- **不能动的接口/文件**：<列出 freeze 的部分>
- **必须遵守的现有规范**：<比如某个 Manager / Registry / Service 协议>
- **不在本次 scope 的事**：<明确踢出去，避免顺手扩 scope>

## 7. 风险 / 边界 / 存疑点

写下"我（Claude）当前不确定"的部分。这些是 7 回合 checkpoint 时优先回顾的项。

- ❓ <存疑点 1>：<具体疑问 + 可能的几种解释>
- ⚠️ <风险 1>：<可能踩的坑 + 缓解思路>
- 🚧 <边界 1>：<这个边界是否要处理，待定>

如果完全确定无疑问，写一行 "无明显存疑点"。

## 8. 进度状态

> §8 是 generator 维护的状态缓存视图，**§2 是真相源**。冲突时 generator 按 §2 自救校准 §8 后继续，不要停手等指令。完整规则见 `~/.claude/rules/dispatch-pipeline.md` 「§8 进度状态写权限边界」段。

每完成一个子任务，把对应行从 TODO 移到 DONE。

### TODO

- [ ] 子任务 1
- [ ] 子任务 2

### DOING

- [ ] <当前正在做的，最多 1-2 个>

### DONE

- [x] <已完成 + 一句话验证方式>

## 9. Amendments

> **用途**：实现阶段用户追加的具体指令（bug fix / review-fix 挑出的修复项 / 临时新增的具体要求）一律**追加**到此处，**不修改 §1-7**——保持原始需求快照纯净，方便回溯"最初想要什么"。
>
> **写权限（与 §8 同为共写域，与 §1-7 的 planner-only 不同）**：
>
> - **planner** 在二次调用时追加：场景 A 用户决策是实现层指令（bug fix / 微调）→ append AMD；场景 A 用户决策是真改硬约束 / 拆任务 → 仍 Edit §1-7（不走 amendment）
> - **generator** 在迭代中追加：用户在主对话里直接提具体指令（bug fix / 改某处效果） → generator 自己 Edit 把 `### AMD-N` append 到 §9 后再动手实现
> - 双方都**只追加、不修改、不删除**已有 AMD 条目（保留审计痕迹）；状态字段 TODO ↔ DONE 由当事 agent 推进时自己改
>
> **executor 验收**：
>
> - status=**DONE** 的 amendment 与 §1-7 等价、**必须验收**；不满足 → issues 里标 `amendment_ref: AMD-N`
> - status=**TODO** 的 amendment 跳过本轮验收（视为"下一轮 generator 的范围"，与 §8 TODO 子任务同处理）

### 模板（每条 amendment 按此格式追加，AMD-N 编号自增）

```markdown
### AMD-N (YYYY-MM-DD HH:MM) [planner 写 | generator 写] — [TODO | DONE]

- **触发**：<用户原话 / 反馈来源——例：用户在阶段 2.5 review-fix 里挑的 / 用户跟 generator 对话提的 bug / 用户决策同步阶段提的>
- **指令**：<具体要做什么、改哪里、达到什么效果>
- **影响范围**：<涉及的文件 / 模块；如新增子任务，在 §8 TODO 也加一行>
- **状态**：TODO | DONE
```

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

> 完成所有 DONE、走 `/openpr` 推 PR 之前，把这个 spec 文件删掉（或整个 `.specs/` 目录删掉）。
> 
> 如果发现这个需求不需要 spec（比如 1-2 行小修），可以创建空文件 `.specs/<slug>.skip` 跳过本流程。
