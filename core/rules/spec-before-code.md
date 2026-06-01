# 新需求先写 Spec 再写代码

进了 worktree 准备落地 Edit/Write 前，**必须**在 worktree 根的 `.specs/<slug>.md` 写一份 spec，把需求对齐 + 拆解 + 验收标准 + 硬约束 + 测试用例都列清楚。PreToolUse hook 硬卡——没 spec 不让 Edit/Write/NotebookEdit。

## 触发信号

满足**全部**条件时触发：

1. 用户提的是**明显新话题**（"新任务 / 另一个 / 接下来做 X / 开始搞 Y / 下一个需求"），并已按 `use-worktree.md` 进了 `.worktrees/<slug>/`
2. 本轮会落地 Edit / Write / NotebookEdit

**不触发**（hook 会自动放行）：

- cwd **不在** `.worktrees/` 下（主仓库 / 改全局配置 / 改 rule / 改 memory）
- spec 文件已存在（延续同一需求的后续迭代不重复写）
- 用户明确说"这次不需要 spec" → `touch .specs/<slug>.skip` 显式跳过

## 标准流程

进 worktree 后、第一次 Edit 前：

### 第 1 步：澄清需求

用 `AskUserQuestion` 问清三个点（每轮的 `UserPromptSubmit` hook 也注入了同样提示）：

- 需求目标（最终想要的效果）
- 硬约束（落地位置 / 栈 / 不能动的东西）
- 自己没理解或存疑的部分

### 第 2 步：写 spec：主索引 + 子目录两层结构

`<slug>` 用 worktree 目录名。模板见 `~/.claude/templates/spec-template.md`。spec 不是单文件，是**主索引 + 子目录**两层（渐进式披露 —— 完成态项目的详情不必每轮 hot-load）：

```
.specs/<slug>.md                  ← 主索引
├── §1-6 内联（每轮 hot-load 的 permanent reference）
└── §7/§8/§9 索引行表（链接到子文件）

.specs/<slug>/
├── tasks/task-N.md       ← 每个 task 一个：详情 + status + scratchpad
├── risks/risk-N.md       ← 每个 risk 一个：详情 + status (OPEN/RESOLVED)
└── amendments/AMD-N.md   ← 每条 AMD 一个：详情 + status + 作者标记
```

**主索引 10 节必含**（参见模板）：

1. 用户原始需求（原话保留，**内联**）
2. 需求拆分索引表 + 并行分组（task 标题 / 文件范围内联，详情拆 `tasks/task-N.md`）
3. 分工角色（**内联**）
4. 测试用例（Golden Path / 边界 / 回归 三类，每类至少 1 条；禁止 TBD / 占位符；**内联**）
5. 验收标准（done definition + 跑哪些命令；**内联**）
6. 硬约束（落地位置 / 栈 / freeze 的接口或文件；**内联**）
7. 风险 / 边界 / 存疑点 **索引表**（详情拆 `risks/risk-N.md`）
8. 进度状态 **索引表**（status 视图，详情拆 `tasks/task-N.md`）
9. Amendments **索引表**（实现阶段追加指令，详情拆 `amendments/AMD-N.md`）
10. Review 流程（元说明，不填）

**写法**：先一次性 Write 主索引，再依次 Write 每个 `tasks/task-N.md` + `risks/risk-N.md` 骨架。amendments/ 初始为空目录（用户在实现阶段追加时 planner/generator 现造）。

#### iOS UI 改动专项要求

**触发信号**（任一即触发）：

- 改了 SwiftUI / UIKit view 文件（含 `View` / `ViewController` / `UIView` 子类 / SwiftUI `body`）
- 改了图片资源（新增/替换 `.imageset` / PDF / PNG / SVG 等）
- 改了样式 / 布局 / 颜色
- 用户描述里出现「UI / 页面 / 界面 / 视图 / 样式 / 布局 / 弹窗」等字眼

**spec 必须额外满足**：

1. 第 4 节 Golden Path 至少 1 条用 mobile-mcp 的冒烟步骤——明确写清楚：跑哪个 scheme、打开哪个页面、做什么操作、看什么视觉/行为结果
2. 第 5 节 Done Definition 加一条：`mobile-mcp 跑通 golden path 无 crash + 视觉符合预期`

仅 iOS 适用；macOS UI 改动不强制（按项目现状走 build + 手动 open）。

### 第 3 步：写完 spec 后停手等用户审核

spec 写完是显式 checkpoint。把 spec 路径告诉用户，等他读完 + 反馈（确认 / 改方向 / 改硬约束 / 补遗漏）后，**再**进入第 4 步开始落地。

例外：用户在原始需求里明确说"边写边干 / 不用等我 / 直接动手"。

### 第 4 步：迭代时维护进度状态

每完成一个子任务，更新 spec 第 8 节的状态。

### 第 5 步：PR 前清理

走 `/openpr` 推 PR 之前，从 worktree 删掉 `.specs/<slug>.md`（或整个 `.specs/` 目录）。主仓库 `.gitignore` 已把 `.specs/` 排除；显式 rm 是双保险。

## Bypass：`.skip`

下列场景直接 `touch .specs/<slug>.skip` 跳过：

- 改 1-2 行的简单 bug 或 typo
- 仅调整样式 / 颜色 / 文案，没逻辑变更
- 用户明确说"这次别写 spec，直接干"
- 用户说"接着上一个 spec 干"但 worktree slug 变了（也可直接复用同名 spec）

`.skip` 文件可空，也可写一行说明跳过原因。

## 与其他规则的关系

- `UserPromptSubmit` hook 注入的澄清提示：本 rule 是它的"沉淀"层 —— 澄清内容写进 spec
- `use-worktree.md`：进了 worktree 就要写 spec
- `iteration-checkpoint.md`：spec 的"进度状态"和"风险/存疑点"两节是 checkpoint 时回顾的依据
- `parallel-subagents.md`：spec 是 subagent 的 hand-off 文档，subagent prompt 里直接 `.specs/<slug>.md` 即可

## 与现有 hook 的关系

- 进受保护分支（main / dev）的 hook 先拦截 → 必须先有任务分支
- 任务分支建好、进了 worktree 之后，spec hook 接手：没 spec 不让 Edit
- 两层 hook 串行检查，先分支后 spec
