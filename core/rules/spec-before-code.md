# 新需求先写 Spec 再写代码

进了 worktree 准备落地 Edit/Write 前，**必须**在 worktree 根的 `.specs/<slug>.md` 写一份 spec，把需求对齐 + 拆解 + 验收标准 + 硬约束 + 测试用例都列清楚。这是 PreToolUse hook 硬卡的——没 spec 不让 Edit/Write/NotebookEdit。

## 触发信号

满足**全部**条件时触发：

1. 用户提的是**明显新话题**（"新任务 / 另一个 / 接下来做 X / 开始搞 Y / 下一个需求"），并已按 `use-worktree.md` 进了 `.worktrees/<slug>/`
2. 本轮会落地 Edit / Write / NotebookEdit

**不触发**的场景（hook 在这些场景会自动放行）：

- cwd **不在** `.worktrees/` 下（主仓库 / 改全局配置 / 改 rule / 改 memory）
- spec 文件已存在（延续同一需求的后续迭代不重复写）
- 用户明确说"这次不需要 spec"——`touch .specs/<slug>.skip` 显式跳过本规则

## 标准流程

进 worktree 后、第一次 Edit 前：

### 第 1 步：澄清需求（如果还没充分澄清）

用 `AskUserQuestion` 问清三个点（每轮的 `UserPromptSubmit` hook 里也注入了同样的提示）：

- 需求目标（最终想要的效果）
- 硬约束（落地位置 / 栈 / 不能动的东西）
- 自己没理解或存疑的部分

### 第 2 步：写 spec 到 `.specs/<slug>.md`

`<slug>` 用 worktree 目录名。模板见 `~/.claude/templates/spec-template.md`，**8 个字段必含**：

1. 用户原始需求（原话保留）
2. 需求拆分（子任务清单）
3. 分工角色（主 agent / subagent / 用户确认）
4. 测试用例（**Golden Path / 边界 / 回归 三类，每类至少 1 条具体场景**；禁止写 "TBD" / 占位符；某类真不需要则删掉小节 + 一行说明原因。Golden Path 口语也叫"冒烟"，但严格上 ≠ smoke test，这里按 Golden Path 颗粒度写）
5. 验收标准（明确的 done definition + 具体跑哪些命令）
6. 硬约束（落地位置 / 栈 / 不能动的接口或文件）
7. 风险 / 边界 / 存疑点
8. 进度状态（TODO / DOING / DONE 子任务清单）

写完一次性 Write 落地，不要分多次 Edit 拼出来。

#### iOS UI 改动专项要求

**触发信号**（任一即触发）：

- 改了 SwiftUI / UIKit view 文件（含 `View` / `ViewController` / `UIView` 子类 / SwiftUI `body`）
- 改了图片资源（新增/替换 `.imageset` / PDF / PNG / SVG 等）
- 改了样式 / 布局 / 颜色（不涉及交互逻辑的纯视觉调整）
- 用户描述里出现「UI / 页面 / 界面 / 视图 / 样式 / 布局 / 弹窗」等字眼

**spec 必须额外满足**：

1. 第 4 节 Golden Path 里**至少 1 条**用 mobile-mcp 的冒烟步骤——明确写清楚：跑哪个 scheme、打开哪个页面、做什么操作、看什么视觉/行为结果（避免「打开模拟器跑一下」这种空话）
2. 第 5 节 Done Definition 里加一条：`mobile-mcp 跑通 golden path 无 crash + 视觉符合预期`

**仅 iOS 适用**：mobile-mcp 虽然是 iOS+Android 跨平台 MCP，本规则只在 iOS UI 改动时触发；macOS UI 改动暂不强制（按项目现状走 build + 手动 open）。

### 第 3 步：写完 spec 后**停手等用户审核**（默认契约）

spec 写完是一个**显式 checkpoint**——不要顺手开干。把 spec 路径告诉用户，等他读完 + 反馈（确认 / 改方向 / 改硬约束 / 补遗漏）后，**再**进入第 4 步开始落地。

理由：

- spec 是和用户**对齐方向**的产物，不是"我已经决定要这么做"的预告。用户读 spec 时往往会发现"哦这块其实我想这样"——比对照代码改 PR 便宜得多。
- 把"写 spec"和"写代码"两件事分开成两轮对话，给用户一个干净的**审 spec 时刻**，而不是被滚动的代码 diff 淹没。
- 用户**已经明确说"只写 spec"** 时（比如本规则诞生那次的对话），更不能顺势开干。

例外：用户在原始需求里就明确说"边写边干 / 不用等我 / 直接动手"。除此之外，默认停。

### 第 4 步：迭代时维护进度状态

每完成一个子任务，更新 spec 第 8 节的状态。便于回合中追踪进度，也是 7 回合 checkpoint 时回顾的依据。

### 第 5 步：PR 前清理

走 `/openpr` 推 PR 之前，从 worktree 删掉 `.specs/<slug>.md`（或整个 `.specs/` 目录）。

主仓库的 `.gitignore` 已经把 `.specs/` 排除，理论上不会被 commit；但**显式 rm 是双保险**，避免 worktree push 时出意外。

## Bypass：什么时候用 `.skip`

下列场景没必要写 spec，直接 `touch .specs/<slug>.skip` 跳过：

- 改 1-2 行的简单 bug 或 typo
- 仅调整样式 / 颜色 / 文案，没逻辑变更
- 用户明确说"这次别写 spec，直接干"
- 用户说"接着上一个 spec 干"但 worktree slug 变了（这种场景也可以直接复用同名 spec 文件，更推荐）

`.skip` 文件可以为空，也可以写一行说明跳过原因。

## 与其他规则的关系

- `UserPromptSubmit` hook 注入的澄清提示（A/B/C 三段）：本 rule 是它的"沉淀"层 —— 澄清出来的内容写进 spec，避免下一轮 session / subagent 再问一遍
- `use-worktree.md`（新话题进 worktree 隔离）：本 rule 紧接它之后 —— 进了 worktree 就要写 spec
- `iteration-checkpoint.md`（3 / 7 回合 checkpoint）：spec 的"进度状态"和"风险/存疑点"两节是 checkpoint 时回顾的依据
- `parallel-subagents.md`（并行 subagent）：subagent 拿不到主 agent 的对话上下文，但**可以读 spec 文件** —— spec 是天然的 hand-off 文档，subagent prompt 里直接 `.specs/<slug>.md` 即可
- `commit-message.md`：spec 不进 git，commit message 不引用 spec 路径

## 与现有 hook 的关系

- 进受保护分支（main / dev）的 hook 仍然先拦截 —— 你必须先有任务分支
- 任务分支建好、进了 worktree 之后，spec hook 接手：没 spec 还是不让 Edit
- 两层 hook 串行检查，先分支后 spec

## Why

过去新需求开干前往往**澄清不充分 + 没拆解 + 没明确验收标准**，导致：

- 同一轮里反复问、反复改
- subagent 拿不到完整上下文，做出来跟主 agent 想的不一样
- 7 回合 checkpoint 时回头看不知道"原始需求是啥、当时为啥这么决定的"
- PR 描述要从对话里挖

写 spec 这个动作把"澄清 → 拆分 → 验收"的隐性思考显式化、文件化，**一次写一份持久化文档**，整个 worktree 周期里都能引用。和 `.gitignore` 配合保证它不污染历史；PR 前删干净。
