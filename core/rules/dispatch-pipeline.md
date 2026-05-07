# 三段式调度（主 agent 不写代码）

收到**写代码需求**时（新功能 / 修 bug / 改 UI / 重构 / 加 feature 等会落地 Edit / Write / NotebookEdit 的任务），主 agent 不亲自落地。**唯一动作是调度 Agent 工具下三个 subagent**：

```
用户需求
  ↓
主 agent: 判断 + 建 worktree（如需要）
  ↓
[planner subagent] —— 独立 context、写 .specs/<slug>.md
  ↓
主 agent: 把 spec 路径告诉用户、AskUserQuestion 问「是否开始实现」
  ↓ 用户拍板「开始」
[generator subagent] —— 独立 context、按 spec 写代码 + 跑编译
  ↓
主 agent: 报告 generator 改动 + AskUserQuestion 问「是否进入 executor 验收」
  ↓ 用户拍板「验收」
[executor subagent] —— 独立 context、只读 review + 验收
  ↓
PASS → 主 agent 报告用户 + AskUserQuestion 问「是否总结+更新文档」 → 按用户选择执行 → 等下一步指令
FAIL → 主 agent 把 issues 整理给 generator 重写（最多 3 次）
3 次都失败 → 报给用户拍板
```

## 触发

满足**任一**条件即按本 rule 走：

- 用户提了写代码需求（含修 bug / 改 UI / 重构 / 加 feature / 加测试）
- 用户的需求会落地 Edit / Write / NotebookEdit

**不触发**（主 agent 仍按默认行为做）：

- 纯问答 / 解释代码 / 找文件 / 查状态
- 改 rule / 改 memory / 改 hook / 改 settings.json（这些是 meta 配置，主 agent 自己改）
- 改 spec 文件本身（这是 planner 的活，主 agent 直接调 planner，不走 generator）
- `/openpr` / `/review` / `/pr-review` 等 slash command 内部流程
- 用户**明确**说「这个简单的你直接改」「跳过 planner」「不用 executor」—— 必须用户**显式**说才能跳；主 agent 不能自己判断「这个简单」

## 主 agent 的具体调度动作

### 阶段 0: 前置

- 收到需求 → 判断是否新话题 → 如需要按 `~/.claude/rules/use-worktree.md` 建 worktree
- 已经在 worktree 里 → 跳过

### 阶段 1: 调 planner

```
Agent({
  description: "<需求一句话> — 规划 spec",
  subagent_type: "planner",
  prompt: """
    用户原始需求（原话）：
    <贴用户原话>

    Worktree slug: <当前 slug>
    Worktree 绝对路径: <pwd>

    按 ~/.claude/agents/planner.md 的 SOP 工作，最终产出 .specs/<slug>.md。
  """
})
```

planner 返回后：

1. Read 一下 `.specs/<slug>.md` 自己看一眼（确认 planner 没写空 / 没写错路径）
2. 把 **spec 文件路径** + **planner 返回的关键摘要**展示给用户
3. 用 AskUserQuestion 问「这份 spec 看完没问题就开始实现，要改方向就告诉我」

**不要自动进入阶段 2** —— 这是用户闸口。

### 阶段 2: 调 generator（用户说「开始」之后）

```
Agent({
  description: "<需求一句话> — 实现",
  subagent_type: "generator",
  prompt: """
    Worktree slug: <slug>
    Worktree 绝对路径: <pwd>
    要执行的子任务范围: <全部 | 子任务 ID 列表>

    .specs/<slug>.md 是你的需求圣经。
    按 ~/.claude/agents/generator.md 的 SOP 工作。
  """
})
```

generator 返回有两种情况：

- **正常完成** → 主 agent **不要直接进入阶段 3**，先报告 + 等用户拍板：
  1. 把 generator 的改动文件清单 + 编译/build 结果 + spec 第 8 节 DONE 的子任务列表展示给用户
  2. 用 AskUserQuestion 问「让 executor 开始验收，还是先看下代码 / 手动改方向 / 撤回重做？」给 3-4 个明确选项（典型：「让 executor 验收」/「我先看一下代码再决定」/「先调一下方向，generator 重写部分子任务」/「撤回这轮 generator 改动」）
  3. 用户说「让 executor 验收」→ 进入阶段 3；用户选其他 → 等用户进一步指令，**不要**自己启动 executor
- **带「需要 planner 更新 spec」标注** → 主 agent：
  1. 重新调 planner（传入 generator 的反馈）让 planner 更新 spec
  2. planner 改完 spec → 主 agent 再问用户「spec 更新了，要看一眼再继续吗？」
  3. 用户同意 → 重新调 generator 继续

### 阶段 3: 调 executor

```
Agent({
  description: "<需求一句话> — 验收",
  subagent_type: "executor",
  prompt: """
    Worktree slug: <slug>
    Worktree 绝对路径: <pwd>
    Generator 改动文件清单: <generator 返回的清单>
    本轮重试次数: <1 | 2 | 3>

    按 ~/.claude/agents/executor.md 的 SOP 工作。
  """
})
```

executor 返回结构化结论：

- **verdict == PASS** → 主 agent 报告用户：「executor 通过了 + ui_smoke_required 提示（如有）+ warning 列表（如有）+ ui_screenshots_dir 路径（如有）」。
  
  **接着用 AskUserQuestion 问「要不要现在总结这次工作 + 更新项目文档？」**，给 3 个选项：
  
  - **总结 + 更新文档（推荐）**：主 agent 自己复盘本轮改动里**对未来 agent 行为有持续影响**的部分（新工作流 / 改了项目结构 / 改了模块边界 / 引入新工具链 / 新约定）→ 列出建议更新的具体文档路径 + 每处改动大纲（CLAUDE.md / AGENTS.md / docs/*.md / rules / skills 都可能）→ 用户拍板大方向后 agent Edit 落地 → 让用户 review diff → 满意就 commit
  - **跳过文档**：本次改动只是常规业务代码 / UI / bug fix，对 agent 没新约束，直接进入下一步
  - **稍后再说**：留着这次改动，先做别的；后续 `/openpr` 时仍会再问一遍（见 `commands/openpr.md`「文档同步检查」）
  
  **不要默认跳过 —— 必须问**。问完按用户的选择执行；用户选完后再告诉用户「可以 `/openpr` 或继续做下一个需求」。
- **verdict == FAIL** → 进入阶段 4

**iOS UI 专项的 `ui_verified` 字段路由**（不是 verdict 本身，但影响主 agent 怎么报告）：

- `ui_verified: pass` —— UI 验收通过，把 `ui_screenshots_dir` 路径告诉用户
- `ui_verified: fail` —— issues 列表里会有 `spec_section: 4` 的 blocking 项，verdict 一定是 FAIL；走阶段 4 重试
- `ui_verified: degraded` —— **environment 问题，不是 generator 的错**。verdict 仍可能 PASS（如果其他都通过）；主 agent 把 `ui_smoke_required: true` 和 `ui_degradation_reason` 提示给用户，让用户跑 UI 冒烟 / 修环境（如装 iOS Simulator runtime）。**不要**因为 `ui_verified: degraded` 重调 generator
- `ui_verified: not_applicable` —— spec 没 iOS UI 改动专项，正常不影响

### 阶段 4: 失败循环（最多 3 次）

```
i = 1
while i <= 3:
    调 generator，prompt 里追加：
      - executor 上轮的 issues 列表
      - 本轮是第 i 次重试 / 共 3 次
      - 显式说「请按 issues 修复，不要扩大改动范围」
    generator 返回 → 调 executor (retry_count = i)
    if executor.verdict == PASS: break
    i += 1

if i > 3:
    停止重试。报给用户：
      "3 次重试仍未通过 executor 验收。
       最近一轮的 blocking issues:
       <列表>
       
       建议下一步：
       (1) 改 spec —— 验收标准/硬约束可能不合理，调 planner 改
       (2) 用户介入 —— 直接看代码、自己改或指导 generator 怎么改
       (3) 暂停这个需求 —— 留 worktree 等以后回来"
```

**不要超过 3 次**自动重试 —— 一直失败说明问题不在代码、是规划或理解层面，需要人介入。

## 主 agent **绝对不能**做的事

- ❌ Edit / Write / NotebookEdit 任何代码文件 —— 一律走 generator
- ❌ Edit / Write `.specs/<slug>.md` —— 一律走 planner
- ❌ 跑项目的 build / lint / test 命令来「自己验证一下」—— 那是 generator / executor 的事
- ❌ 跳过 planner 直接调 generator（除非用户**显式**说「跳过 planner」）
- ❌ 跳过 executor 直接告诉用户「我做完了」（除非用户**显式**说「不用 executor」）
- ❌ 在 generator 失败时自己出手改代码 —— 走重试循环；3 次后交给用户
- ❌ 自己脑补「这个简单不用走流程」—— 只有用户显式 bypass 才跳

## 主 agent **可以**做的事

- ✅ 用 Bash 跑 `git status` / `git log` / `pwd` / `ls` 等只读命令了解状态
- ✅ Read 任何文件来回答用户的问答类问题
- ✅ AskUserQuestion 澄清需求 / 让用户在 planner 后拍板 / 报告 executor 失败
- ✅ 建 worktree、改全局 rule / settings / memory（meta 配置类操作不在本 rule 约束内）
- ✅ 调 `/openpr` / `/review` / `/pr-review` 等 slash command（这些 command 内部的流程不受本 rule 约束）

## Bypass

用户**明确**说以下任一种话时，本轮跳过对应阶段：

- 「你直接改」「不用 planner」「跳过 spec」 → 跳 planner，主 agent 直接调 generator（generator 仍要遵守自己的 SOP）
- 「不用 executor」「我自己 review」 → 跳 executor，generator 完成后直接报用户
- 「全部你自己来」「这一行你直接改」 → 三段式整体 bypass，主 agent 回到默认行为可以自己 Edit

bypass 必须**用户主动说**。主 agent **不能**自己判断「这个简单不用走流程」。

## 与现有 rule 的关系

- `use-worktree.md`：本 rule 的阶段 0 仍按它执行
- `spec-before-code.md`：本 rule 的阶段 1 (planner) 是它的具体执行者；现有 PreToolUse hook 卡 generator 的 Edit（generator 阶段如果 spec 不存在仍会被 hook 拦下）
- `iteration-checkpoint.md`：planner 的 AskUserQuestion 是它的具体落地；generator 的「不确定流程」也是
- `parallel-subagents.md`：和本 rule 不冲突 —— 本 rule 是串行三段；用户说「拆开并行跑」时本 rule bypass，走 parallel-subagents
- `post-change-verify.md`：generator 阶段遵守（只跑 build）；executor 阶段额外跑 lint
- `reuse-first` skill：generator 阶段必 invoke；executor 阶段做 review 时再 invoke 一次

## Why

1. **职责清晰**：planner 规划、generator 实现、executor 验收 —— 三个独立 context 杜绝「一边规划一边脑补实现」「一边写代码一边给自己开绿灯」
2. **用户作为闸口**：planner 后用户拍板「方向对不对」、executor 失败 3 次后用户拍板「方向是不是要变」 —— 把不可逆决策留给人
3. **失败循环上限 = 3**：超过 3 次说明根因不在代码层，强制升级避免 token 烧穿
4. **主 agent 不写代码**：避免「主 agent 顺手改了一行 → executor 不知道有这一行 → 验收漏了」的链路错配；也避免主 agent 在调度过程中污染 subagent 的工作产物
5. **三个 subagent 独立 context**：每个 subagent 看不到其他 agent 的对话过程 —— 通信只能通过文件（spec、代码）和主 agent 中转的结构化 message。这是设计而不是限制 —— 强制 spec 成为单一真相源、强制每个阶段产出明确的「交接物」
