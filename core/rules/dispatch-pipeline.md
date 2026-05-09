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
[阶段 2.5] 主 agent: 报告 + 默认跑 1 轮代码 review（/review 或 /codex:review）
              → 用户挑要修的项 → generator 按 review 修 → 不限轮循环（用户拍板停）
  ↓ 用户拍板「进 executor」
[executor subagent] —— 独立 context、只读 review + 验收
  ↓
PASS → 主 agent 报告用户 + AskUserQuestion 问「是否总结+更新文档」 → 按用户选择执行 → 等下一步指令
FAIL → 主 agent 把 issues 整理给 generator 重写（最多 3 次）
3 次都失败 → 报给用户拍板
```

> ⚡ **并行模式扩展**：spec 第 2 节并行分组里有**多个** `parallel-N` 组时，阶段 2 / 3 走「并行模式」—— 见下方 **2B / 3B / 3C / 阶段 5** 子节。串行模式（只有 `serial` 组 / 写「全部串行」）按上图原流程跑。判别由 planner 在 spec 里标注、用户在阶段 1 末尾审 spec 时拍板，主 agent 自己**不**判断是否并行。

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
3. 用 AskUserQuestion 停下问，至少给这几个选项：
   - 开始实现（调 generator）
   - 我先看 spec，等我说开始
   - 改 spec / 改方向（重新调 planner）
   - 不用 generator，我自己改 / 跳过

> ⛔ **硬约束（用户反复强调过的高优先级闸口）**：
>
> planner 返回后，主 agent 的**下一个 tool call** 只能是以下之一：
>
> - `Read`（读 spec 自检）
> - `AskUserQuestion`（向用户拍板）
> - `Bash`（只读命令，如 `git status` 看 worktree 状态）
>
> **绝对不能**是 `Agent(subagent_type="generator")`。哪怕 spec 看起来无懈可击、用户原始需求看起来已经 ready-to-code，也**不准**自动进入阶段 2。
>
> 用户回复必须是**明确同意词**才能调 generator：「开始 / 开 / ok 开始 / 干 / go / 实现吧 / 没问题开始」之类。
>
> 用户回复**模糊**（「嗯」「让我看看」「先放着」「再想想」）→ **继续等**，不要把模糊回复脑补成同意。
>
> 这条比「主 agent 主动推进流程」优先级**高**。宁可多问一轮，不要替用户拍板。

#### 阶段 1.5: 用户决策后必须调 planner 同步 spec（强制闸口）

> ⛔ **用户反复强调过的高优先级规则**：用户对 spec 给出**实质决策**后，主 agent 的下一个 tool call **必须**是 `Agent(subagent_type="planner")`，把决策传给 planner 让它写进 spec 文件。**不能**跳过这一步直接调 generator —— 否则 generator 看到的 spec 不包含用户最终确认 / 调整的内容，主 agent 中转的版本可能丢信息。

**触发**（任一即触发）：

- 用户回复明确同意词（「开始 / 开 / ok 开始 / 干 / go / 实现吧 / 没问题开始」）→ planner 把"用户已确认 spec、授权进入实现阶段"追加到更新日志
- 用户回复「改 spec / 改方向 / 加 / 减 X」→ planner 落地调整（这本来就要调 planner）
- 用户回复「不用 generator，我自己改 / 跳过」→ planner 把"用户决定跳过 generator 阶段"追加到更新日志，记下范围

**不触发**：

- 用户回复模糊（「嗯」「让我看看」「先放着」「再想想」）→ 继续等用户进一步指令，**不调** planner
- 用户回复「我先看 spec，等我说开始」→ 等用户后续给实质决策再调

调 planner 同步的 prompt 模板：

```
Agent({
  description: "<需求一句话> — 同步用户决策",
  subagent_type: "planner",
  prompt: """
    场景：用户决策同步（dispatch-pipeline 阶段 1.5）

    Worktree slug: <slug>
    Worktree 绝对路径: <pwd>
    Spec 文件绝对路径: <pwd>/.specs/<slug>.md

    用户在 AskUserQuestion 里挑的选项：<原选项标签>
    用户回复原话：<贴用户原话>
    决策含义（主 agent 摘要的一句话）：<例：用户确认 spec、授权进入实现阶段 / 用户要求把 X 加进硬约束 / 用户决定跳过 generator>

    按 ~/.claude/agents/planner.md 的"二次调用：用户决策同步"场景 SOP 工作。
  """
})
```

planner 同步完返回后，主 agent 再次 Read 一遍 `.specs/<slug>.md` 确认改动落地，**然后**才进入下一步（阶段 2 调 generator / 等用户进一步指令 / 其他分支）。

#### 自检 checklist（每次准备调 generator 前过一遍）

- [ ] 我的上一个 tool call 是 planner 返回？→ 如果是，下一步**绝不能**直接调 generator
- [ ] 我向用户展示了 spec 路径 + 摘要？
- [ ] 我用 AskUserQuestion 问过用户「是否开始实现」？
- [ ] 用户给了**明确同意词**？（不是「嗯」「ok」之外的模糊词）
- [ ] **我已经在用户决策后调 planner 同步进 spec、并 Read 确认了？**（阶段 1.5 强制闸口）
- [ ] 5 项全部 ✅ → 才能 invoke generator

### 阶段 2: 调 generator（用户说「开始」之后）

> 前提：阶段 1.5 已经跑过 —— 用户决策已经由 planner 同步进 `.specs/<slug>.md`。如果还没跑，**回去补**，不要继续往下。

#### Step 0: 选模式

主 agent 读 spec 第 2 节「并行分组」表：

- 表里有**多个** `parallel-N` 组 → 走 **2B 并行模式**
- 表里只有 `serial` 组 / 写「全部串行」 / 表为空 → 走 **2A 串行模式**

#### 2A: 串行模式（默认）

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

- **正常完成** → **进入阶段 2.5（review-fix 循环）**，不要直接进入阶段 3。
- **带「需要 planner 更新 spec」标注** → generator 返回的结构化结论里会有 `needs_planner_update: true` + `feedback_file`（指向 `.specs/<slug>-feedback.md`）+ `feedback_iter`（本轮 iter 编号）+ `feedback_summary`。主 agent：
  1. 用 `Read` 看一眼 `feedback_file` 自检（确认 generator 真的写了文件、文件里有对应 iter 章节、不是空 placeholder）
  2. 把 `feedback_summary` + feedback 文件路径展示给用户，让用户先有上下文（不要贴整份 feedback）
  3. 调 planner 走「场景 B：generator 反馈更新」，prompt 里**必须**带：feedback 文件绝对路径、本轮 iter 编号、spec 文件绝对路径。**不要**在 prompt 里复述 feedback 内容 —— planner 会自己 Read 文件
  4. planner 改完 spec → 主 agent Read 一下 spec 末尾「更新日志」确认改动落地 → 再问用户「spec 更新了，要看一眼再继续吗？」
  5. 用户同意 → 重新调 generator 继续（generator 下一轮启动会自己 Read spec 看 planner 改了什么）

**为什么走文件而不是 prompt 中转**：generator 和 planner 在不同 context，原来主 agent 把 generator 反馈以 prompt 文本中转给 planner，主 agent 容易漏信息（特别是 generator 列的"已经做完"/"已停手"/"placeholder 状态"三类细节）；feedback 文件让 generator 和 planner 直接通过文件对话，主 agent 只做路由。

#### 2B: 并行模式（spec 标注多个 parallel-N 组时）

对每个 `parallel-N` 组 + `serial` 组（如有）**各开一个 sub-worktree**，让 generator 在里面独立干活。`parallel-N` 组之间并行；`serial` 组内的子任务由该组的 generator 顺序串行跑。

##### Step 1: 给每组建 sub-worktree

```bash
cd <主 worktree 绝对路径>   # .worktrees/<slug>/
mkdir -p .subworktrees

# 每个 parallel-N 组 + serial 组（如非空）各建一个
# GROUPS 来自 spec 第 2 节并行分组表的「组 ID」列
for group in $GROUPS; do
  git worktree add .subworktrees/$group -b <type/scope-slug>--$group HEAD
done
```

每个 sub-worktree 还要按 `~/.claude/rules/use-worktree.md` 的 step 5-7 复制 `<project-specific>` 的 gitignored 本地配置 / 锁文件 / 跑初始化命令（例：`Local.xcconfig`、`.env.local`、`Package.resolved`、`yarn.lock`、生成 xcodeproj、`npm install` 等）—— 没这些 build 会失败。

**不要**在每个 sub-worktree 都打开 IDE / workspace —— 多开 N 个窗口浪费。sub-worktree 只跑命令行 build，主 worktree 的 IDE 窗口留给用户审改动。

##### Step 2: 同一个 message 里发起 N 个并行 generator

**关键**：所有 generator 调用必须放进**同一个 assistant message** 的多个 Agent tool calls 里 + 每个都带 `run_in_background: true`，否则会变串行（系统会一个跑完再跑下一个）。

```
Agent({
  description: "<需求> — parallel-1",
  subagent_type: "generator",
  run_in_background: true,
  prompt: """
    Worktree slug: <主 slug>--parallel-1
    Worktree 绝对路径: <主 worktree>/.subworktrees/parallel-1
    Spec 文件绝对路径: <主 worktree>/.specs/<slug>.md   ← 注意是主 worktree（.specs/ 是 .gitignore，sub-worktree 没有）
    要执行的子任务范围: <spec 第 2 节并行分组表里 parallel-1 组的 task ID 列表>
    并行模式: 是
    
    重要约束：
    - 你只改本组分配的子任务对应的文件 —— 其他 parallel-* 组同时在改别的文件，撞了就互相覆盖
    - 不改 spec 第 1-7 节
    - 不动主 worktree（你的 cwd 是 sub-worktree）
    
    按 ~/.claude/agents/generator.md 的 SOP 工作。
  """
})
Agent({...parallel-2...}, run_in_background: true)
Agent({...serial...}, run_in_background: true)
```

##### Step 3: 等所有组完成

主 agent 在所有并发 Agent call 都返回前**不要**继续往下 —— 后台 Agent 完成时系统会通知。等齐再进入阶段 3B。

##### 单组异常处理

任一组 generator 返回「需要 planner 更新 spec」标注（结构化结论里 `needs_planner_update: true`）：

1. 让其他正在跑的组**继续跑完**（结果暂存到 sub-worktree，不丢弃）
2. **该组的 feedback 文件**写在该组**自己的 sub-worktree** 下（路径形如 `<sub-worktree>/.specs/<sub-slug>-feedback.md`），不在主 worktree。Read 一下确认文件存在 + iter 章节落地
3. 调 planner，prompt 里带：feedback 文件绝对路径（在 sub-worktree 下）、本轮 iter 编号、**spec 文件绝对路径（在主 worktree 下，因为 .specs/ gitignored、sub-worktree 没有 spec）**。planner 改 spec 主文件、不修 sub-worktree 的 feedback 文件
4. spec 更新后 → 用户拍板 → 主 agent 决定下一步：
   - 该组单独重做（其他组结果保留；重做时 generator 在 sub-worktree 内继续读主 worktree 的 spec）
   - 整组重新分组（如果 planner 重划了）→ 清理所有 sub-worktree 重来

### 阶段 2.5: review-fix 循环

> **时机**：
> - 串行模式（2A）：阶段 2 完成后、阶段 3 前
> - 并行模式（2B）：挪到阶段 3C 后（合并到主 worktree 之后）—— 分散 review 没意义、整体 review 一次

generator 「正常完成」后默认跑 1 轮代码 review，让用户挑改、generator 修。循环不限轮、由用户拍板停。

**并行模式下 review-fix 期间的 generator 调用退化为串行**（在主 worktree 内调一次 generator 修整体 review issues）—— 合并验证已通过，没必要再分 sub-worktree。

#### Step 1: 报告 + 闸口（决定走 review 还是直接 executor）

主 agent：

1. 把 generator 的改动文件清单 + 编译/build 结果 + spec 第 8 节 DONE 的子任务列表展示给用户。**还要展示 generator 返回结构化结论里的 `dead_code_status` 字段**（见 `agents/generator.md` Step 4.5）：
   - `clean` → 一句话过：「dead-code 自检 0 candidates」
   - `auto_cleaned` → 把 `dead_code_auto_cleaned` 列表贴出来，让用户知道 generator 顺手删了哪些本轮自产的孤儿（透明度，不打扰）
   - `needs_user_review` → **必须高亮**：把 `dead_code_pending_review` 列表完整贴出来，提示用户 generator 自动清不掉、需要你判断；这些项可能在阶段 2.5 review-fix 循环里被采纳删除
   - `skipped:<reason>` → 一句话说明跳过原因（`no-swift-changes` / `no-periphery` / `spec-opt-out`），让用户知道这一步没跑过
2. 用 AskUserQuestion 问「下一步」，给选项（**第一个标 Recommended**）：
   - **跑 /review**（Recommended）—— pele 自带的 deep code review（见 `~/.claude/commands/review.md`），结果落 `.reviews/<branch>-<ts>.md`
   - **跑 /codex:review**（仅当装了 OpenAI Codex CLI 插件时可选）—— Codex 外部视角 review，作为 cross-check
   - **跳过 review，直接进 executor** —— 改动很小、或用户已经看过代码
   - **暂停，等我下一步指令** —— 用户想自己看代码 / 改方向 / 撤回 / 让 generator 改某些子任务
3. 用户选 review → 进入 Step 2；选「跳过 review」→ 跳到阶段 3 入口；选「暂停」→ 等用户进一步指令，**不要**自动推进

#### Step 2: 触发 review

按用户选择执行：

- **/review**：复刻 `~/.claude/commands/review.md` 的 SOP（git diff 拿改动 → Agent 派发 review subagent → 写 `.reviews/<branch>-<ts>.md`）。**不要**走 Skill 工具尝试 invoke slash command —— 直接按 review.md 步骤手动跑，确定性高
- **/codex:review**：按 codex 插件提供的 review.md SOP（通过 Bash 调 codex-companion；默认 background 模式，让用户决定 wait / background）。**用户没装 codex 插件时本选项在 Step 1 闸口不出现**

review 完成后回到主 agent。

#### Step 3: 摘要 review，让用户挑

主 agent：

1. **不要**贴整份 review；从 review 文件里提取关键信息：
   - issues 总数 + 按严重度分布（blocking / warning / nit / suggestion）
   - 3-5 条最值得关注的 highlight（一句话 + 文件:行）
   - review 文件**绝对路径**给用户，让他自己打开看细节
2. AskUserQuestion 问「review 怎么处理？」给 4-5 个选项：
   - **全部采纳，调 generator 修**
   - **只采纳 blocking 级，调 generator 修**（review 里的 nitpick 跳过）
   - **打开 review 文件我自己挑** —— 等用户在主对话里告诉我具体修哪些条目
   - **再跑另一个 review**（刚跑了 /review 就跑 /codex:review，反之亦然）—— cross-validate
   - **跳过这次 review，进 executor** —— review 留着以后参考、本轮不修

#### Step 4: 调 generator 按 review 修

```
Agent({
  description: "<需求一句话> — 按 review 修",
  subagent_type: "generator",
  prompt: """
    Worktree slug: <slug>
    Worktree 绝对路径: <pwd>
    本轮任务: 按代码 review 修复，不扩范围、不修 spec

    Review 文件: <绝对路径>
    采纳范围: <全部 | 只 blocking | 用户挑出的具体条目（列出来）>

    按 ~/.claude/agents/generator.md 的 SOP 工作，但本轮重点：
    - 只改 review 里被采纳的项
    - 不修 spec 第 1-7 节、不扩任务范围
    - 修完跑编译确认没引入新错
  """
})
```

generator 修完返回 → **回到 Step 1**（重新展示改动 + 4 个闸口选项）。这一轮的 review-fix 算一次迭代结束、由用户决定下一轮还是停。

#### 循环规则

- **循环不限轮**：每轮 fix 后必须重新走 Step 1 的闸口让用户拍板。主 agent **不**自己判断「review 应该够了」自动进 executor
- **用户拍板停**：用户选「跳过 review，进 executor」或「暂停」即终止本阶段
- **review 失败 / Codex 不可用 / Bash 错**：主 agent 把错误告诉用户、AskUserQuestion 问「换另一个 review / 跳过 review 进 executor / 暂停」，**不要**自己重试 5 次也不要硬塞默认行为

### 阶段 3: 调 executor

#### 3A: 串行模式（默认）

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

- **verdict == PASS** → 主 agent 报告用户：「executor 通过了 + ui_smoke_required 提示（如有）+ warning 列表（如有）+ ui_screenshots_dir 路径（如有）+ **ui_dynamic_cases_skipped 列表**（如有，**必须把每条 case_number + spec_description 完整列出来，提示用户「下面这几条是动态/动画类用例，executor 没用 mcp 验，请自己跑一下看效果」**）」。
  
  **接着用 AskUserQuestion 问「要不要现在总结这次工作 + 更新项目文档？」**，给 3 个选项：
  
  - **总结 + 更新文档（推荐）**：主 agent 自己复盘本轮改动里**对未来 agent 行为有持续影响**的部分（新工作流 / 改了项目结构 / 改了模块边界 / 引入新工具链 / 新约定）→ 列出建议更新的具体文档路径 + 每处改动大纲（CLAUDE.md / AGENTS.md / docs/*.md / rules / skills 都可能）→ 用户拍板大方向后 agent Edit 落地 → 让用户 review diff → 满意就 commit
  - **跳过文档**：本次改动只是常规业务代码 / UI / bug fix，对 agent 没新约束，直接进入下一步
  - **稍后再说**：留着这次改动，先做别的；后续 `/openpr` 时仍会再问一遍（见 `commands/openpr.md`「文档同步检查」）
  
  **不要默认跳过 —— 必须问**。问完按用户的选择执行；用户选完后再告诉用户「可以 `/openpr` 或继续做下一个需求」。
- **verdict == FAIL** → 进入阶段 4

**iOS UI 专项的 `ui_verified` 字段路由**（不是 verdict 本身，但影响主 agent 怎么报告）：

- `ui_verified: pass` —— **静态间距用例**全部通过，把 `ui_screenshots_dir` 路径告诉用户。如果同时有 `ui_dynamic_cases_skipped` 非空（动画 / 过渡 / 输入流类用例由 executor 主动降级），主 agent 必须把那个列表也展示给用户、提示他「这几条要自己看动画」
- `ui_verified: fail` —— **静态间距用例**至少 1 条 frame/对齐与 spec 不符，issues 列表里会有 `spec_section: 4` 的 blocking 项，verdict 一定是 FAIL；走阶段 4 重试
- `ui_verified: degraded` —— **不是 generator 的错**。两类原因：(a) environment 问题（build artifact / simulator / install/launch 失败）；(b) **全部用例都是动态降级**，无静态可验。verdict 仍可能 PASS（如果其他都通过）；主 agent 把 `ui_smoke_required: true` + `ui_degradation_reason` + `ui_dynamic_cases_skipped`（如有）一起报给用户，让他自己跑 UI 验证。**不要**因为 `ui_verified: degraded` 重调 generator
- `ui_verified: not_applicable` —— spec 没 iOS UI 改动专项，正常不影响

#### 3B: 并行模式（每组各自跑 executor）

##### Step 0: 预分配 simulator / 模拟环境 pool（仅当 spec 第 4 节有 UI 冒烟用例 + 该 UI 验收依赖共享单实例时）

并行 executor 都跑 UI 冒烟时如果共享单一 simulator / emulator / 测试环境实例（默认 `get_booted_sim_id` 拿到同一台）会互相抢交互。主 agent 在调 executor 前**预分配**每组专属的实例 ID：

`<project-specific>` iOS 项目示例（用最新可用 iOS runtime 起一组 simulator）：

```bash
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c "
import json,sys
data=json.load(sys.stdin)
ios=[r for r in data['runtimes'] if r['platform']=='iOS' and r.get('isAvailable')]
ios.sort(key=lambda r: tuple(int(x) for x in r['version'].split('.')), reverse=True)
print(ios[0]['identifier']) if ios else print('')
")
[[ -n "$RUNTIME" ]] || { echo "NO_IOS_RUNTIME_AVAILABLE"; exit 1; }

declare -A SIM_POOL
for group in $GROUPS; do
  UDID=$(xcrun simctl create "exec-${SLUG}-${group}" "iPhone 16 Pro" "$RUNTIME")
  xcrun simctl boot "$UDID" 2>/dev/null || true
  SIM_POOL[$group]="$UDID"
done
```

其他生态（Android emulator pool / 浏览器 Playwright pool / Docker container pool / 数据库测试 schema pool 等）按本机命令对应处理。

**资源 cap**（每实例占的内存按生态评估，iOS sim ~2-3GB、Android emu ~1-2GB、Playwright headless 浏览器 ~300-500MB）：主 agent 调度前估算 N 个并行组 × 单实例占用是否超过本机可用内存的 70%。超出 → 主 agent **不**自动决策，先警告用户：「spec 标了 N 个并行组超过本机可承载实例数，建议：(1) 在 spec 里把部分 parallel 组合并 (2) 接受降级到 flock 互斥 (3) 强行跑（机器可能 swap）」让用户拍板。

##### Step 1: 调 executor

阶段 2B 的所有 generator 都返回后，**对每组各自调 executor**。仍可以并行（每组在自己 sub-worktree 内独立跑），同一个 message 多个 Agent call + `run_in_background: true`：

```
Agent({
  description: "<需求> — parallel-1 验收",
  subagent_type: "executor",
  run_in_background: true,
  prompt: """
    Worktree slug: <主 slug>--parallel-1
    Worktree 绝对路径: <主 worktree>/.subworktrees/parallel-1
    Spec 文件绝对路径: <主 worktree>/.specs/<slug>.md
    Generator 改动文件清单: <该组 generator 返回的清单>
    本轮重试次数: <1 | 2 | 3>
    并行模式: 是
    本组负责的子任务: <task ID 列表>
    Simulator UDID / 模拟环境 ID: <SIM_POOL[parallel-1]>   ← 仅 UI 验收用，串行模式 / 无 UI 验收时省略
    
    按 ~/.claude/agents/executor.md 的 SOP 工作。
    本轮验收范围**只看本组负责的子任务**对应的 spec 验收标准；
    spec 第 4 节里其他组的测试用例不要纳入本轮验收。
    所有 simulator / emulator / 测试环境工具调用都显式传 ID 参数（不要拿 booted 默认值，会抢到别组的实例）。
  """
})
Agent({...parallel-2 验收, Simulator UDID: <SIM_POOL[parallel-2]>...}, run_in_background: true)
Agent({...serial 验收, Simulator UDID: <SIM_POOL[serial]>...}, run_in_background: true)
```

每组 verdict 独立追踪：

- **该组 PASS** → 关闭，不再循环
- **该组 FAIL** → 走阶段 4 失败循环**只针对该组**（≤3 次，重试时仍在该 sub-worktree 内重调 generator）。其他已 PASS 的组**不动**
- **全部组 PASS** → 进入 **3C 合并验证**
- **任一组 3 次重试仍 FAIL** → 整体停下报用户（参考阶段 4 末尾），其他已 PASS 组保持不动等用户决定（用户可能选「保留这部分、放弃失败的组」「整体回滚」「升级 spec 重新拆」）

#### 3C: 合并验证（仅并行模式）

所有 sub-worktree 的 executor 都 PASS 后，主 agent 把各组提交合并回主 worktree 的主分支：

```bash
cd <主 worktree 绝对路径>

# 按 spec 第 2 节并行分组表里的顺序 merge（serial 组优先 merge，parallel-N 按编号）
# 用 --no-ff 保留并行分支拓扑，方便后续审查
for group in serial parallel-1 parallel-2 ...; do
  if git rev-parse --verify "<type/scope-slug>--$group" >/dev/null 2>&1; then
    git merge --no-ff "<type/scope-slug>--$group" -m "merge: $group into <type/scope-slug>"
  fi
done
```

##### 合并冲突处理

任一 merge 报冲突 → **直接报用户人工介入**，不要自己解。冲突说明：

- planner 在阶段 1 误判了文件边界（标了 parallel 但其实有重叠）
- 或 generator 越界改了不该改的文件

主 agent 给用户两个选项：

- **回滚 merge + 调 planner 重划分组**（`git merge --abort` 撤销当前 merge，sub-worktree 还在）
- **手动解冲突**（用户在主 worktree 里自己改）

##### Merge 后跑 build 验证

跑项目的 build 命令（按 spec 第 5 节验收标准），验证合并没破环境。

build 失败 → 报用户（合并触发的隐性冲突，例如类型签名不一致），**不**自动调 generator 修。

build 通过 → 清理 sub-worktree：

```bash
cd <主 worktree 绝对路径>
for group in serial parallel-1 parallel-2 ...; do
  git worktree remove .subworktrees/$group
  git branch -d "<type/scope-slug>--$group"   # 已 merge，安全删除
done
rmdir .subworktrees 2>/dev/null || true
```

清理 simulator / 模拟环境 pool（仅当 3B Step 0 创建了的话，按生态对应处理）：

```bash
# `<project-specific>` iOS 示例
for udid in "${SIM_POOL[@]}"; do
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  xcrun simctl delete "$udid" 2>/dev/null || true
done
# Android: adb -s <emu-id> emu kill；Playwright: 关 browser context；Docker: docker rm -f $POOL
```

清理完后 → **进入阶段 2.5（review-fix 循环）**，对整体改动做 review。

### 阶段 4: 失败循环（最多 3 次）

```
i = 1
while i <= 3:
    调 generator，prompt 里追加：
      - **review 文件绝对路径**: `.specs/<slug>-review.md`（executor 在 FAIL 时已写，含完整 issues + 多 iter 累积视图）
      - 本轮是第 i 次重试 / 共 3 次
      - 显式说「请 Read review 文件拿完整 issues + 上轮 status diff，按 issues 修复，不要扩大改动范围」
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

> **为什么 generator prompt 里指 review 文件路径而不是中转 issues 文本**：和阶段 2 generator → planner feedback 文件同理 —— 多 iter 累积、主 agent 不漏字段。详见 `~/.claude/agents/executor.md` Step 8。

#### 并行模式下的 scope 限定

阶段 3B 的某组 executor FAIL → 进入本循环但 scope **只针对该组**：

- 重调 generator 的 prompt 里 worktree 绝对路径、spec 子任务 ID、本轮重试次数都限定到**该组**
- 其他已 PASS 的组的 sub-worktree **不动**、不重新 build、不重新 executor
- 该组 3 次重试仍 FAIL → 报给用户决定，已 PASS 组保留等待
- 用户决定的可能选项：放弃该组（接受其他组成果）/ 整体回滚 / 升级 spec 重划分组

### 阶段 5: 最终 executor（仅并行模式）

并行模式下 review-fix（阶段 2.5，时机已挪到阶段 3C 后）退出后**必须**再跑一次 executor —— review-fix 期间 generator 可能改了代码，那部分改动还没经过 executor 验收：

```
Agent({
  description: "<需求> — 最终验收",
  subagent_type: "executor",
  prompt: """
    Worktree slug: <主 slug>
    Worktree 绝对路径: <主 worktree 绝对路径>
    Generator 改动文件清单: <review-fix 期间的整体改动清单（包含所有组合并 + review 修改）>
    本轮重试次数: 1
    最终验收模式: 是
    
    按 ~/.claude/agents/executor.md 的 SOP 工作。
    验收范围：spec 第 4 / 5 / 6 节的整体（不分组）。
  """
})
```

- **PASS** → 进入串行流程末尾的「报告用户 + 文档同步问询」逻辑（同 3A 的 PASS 路径）
- **FAIL** → 走阶段 4 失败循环（**不分组**，整体重做 review-fix 改动），最多 3 次

> 串行模式（2A）下不存在阶段 5 —— 阶段 3A 的 executor 已经在 review-fix 后跑过（见阶段 2.5 时机说明），不需要重复。

## 主 agent / planner / generator 在 §8 进度状态上的写权限边界

§8（TODO/DOING/DONE）**默认**是 generator 的写权限：

- ✅ generator: 每完成一个 task，把对应行从 TODO 移到 DONE。这是日常完成度迁移
- ❌ planner: 默认不动 §8（避免 planner 与 generator 在同一节互相覆盖）
- ❌ 主 agent: 默认不动 §8（按本 rule「主 agent 绝对不能做的事」第 2 条）

但下面两种场景下，**planner 必须改 §8**（这是**计划性结构改动**、不是完成度迁移、不算抢 generator 写权限）：

### 场景 A: 用户决策导致已 DONE task 范围扩大（task 拆分）

**触发**：用户在阶段 1.5 / 2 / 2.5 / 3 给的决策让一个**已 DONE** 的 task 范围扩大（例：原 task-5 = "POST 阶段失败"，用户决策 B 后扩成 "POST + commit 时机 + sidecar"，但 task-5 已经在 §8 标了 DONE）。

planner 必须做：

1. §2 把原 task 拆成 task-Na（已 DONE 子范围）+ task-Nb（待做新增子范围）
2. §8 同步：task-N 行 → 删除；新增 task-Na 标 DONE、task-Nb 标 TODO
3. 在 §8 段头加一行校准说明：`§8 校准说明（YYYY-MM-DD iter-N 处理）：本节由 planner 因 task 拆分破例修改一次。日常完成度迁移仍由 generator 自己写。`

### 场景 B: 旧 task 被用户决策完全移出 scope（task 删除）

**触发**：用户决策让某 task 完全不再做。

planner 必须做：

1. §2 给该 task 行加删除线 + 一句说明（保留审计痕迹）
2. §8 同步：从 TODO/DOING/DONE 任一段把该 task 行**删掉**（不留删除线 —— §8 是状态视图、删除线行是噪声）

### 主 agent 调 planner 时的 checklist

调 planner 走场景 A / B 时，prompt 里**必须显式**点出：

- 触发场景（用户决策 / generator 反馈）+ 用户原话
- 受影响的 task ID 列表
- 期望 planner 做的 §8 改动（拆 / 删 / 状态调整）+ 明确写「主 agent 与用户特批 planner 改 §8」

不要让 planner 自己猜「这次能不能改 §8」—— 主 agent 显式授权 planner 才动。

### Generator 启动前 §8 漂移自救（不停手等指令）

generator 启动前发现 §8 ↔ §2 / §7 不一致时，**§2 是真相源**，按下面处理（详见 `~/.claude/agents/generator.md` Step 1.5）：

- §2 列了 task 但 §8 缺 → 自己加进 §8 TODO 继续干
- §8 标 DONE 但 §7 进度记录说"未完成" → 自己退回 DOING 继续干
- §8 有 task 但 §2 没列 → 这是真冲突 → 跑 Step 4 不确定流程（让 planner 处理）

前两种是漂移、自救即可，**不要**写 feedback 文件停手；第三种才是真不确定。这条是为避免 planner / generator 双方退守 SOP 边界 → §8 漂移没人改 → 死锁。

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
- `parallel-subagents.md`：本 rule 的并行模式（阶段 2B / 3B / 3C / 5）是 parallel-subagents 的具体执行路径之一 —— planner 在 spec 第 2 节标注多个 `parallel-N` 组、用户审 spec 未删除即视同「拆分方案过审」。用户也可以**显式发令**「拆开并行跑」直接 bypass 三段式走 parallel-subagents。两条入口共用 parallel-subagents 的核心约束（文件边界严格不重叠 / sub-worktree 隔离 / 主 agent 集成验证）。
- `post-change-verify.md`：generator 阶段遵守（只跑 build）；executor 阶段额外跑 lint
- `architecture-first` skill：generator 阶段必 invoke；executor 阶段做 review 时再 invoke 一次

## Why

1. **职责清晰**：planner 规划、generator 实现、executor 验收 —— 三个独立 context 杜绝「一边规划一边脑补实现」「一边写代码一边给自己开绿灯」
2. **用户作为闸口**：planner 后用户拍板「方向对不对」、executor 失败 3 次后用户拍板「方向是不是要变」 —— 把不可逆决策留给人
3. **失败循环上限 = 3**：超过 3 次说明根因不在代码层，强制升级避免 token 烧穿
4. **主 agent 不写代码**：避免「主 agent 顺手改了一行 → executor 不知道有这一行 → 验收漏了」的链路错配；也避免主 agent 在调度过程中污染 subagent 的工作产物
5. **三个 subagent 独立 context**：每个 subagent 看不到其他 agent 的对话过程 —— 通信只能通过文件（spec、代码）和主 agent 中转的结构化 message。这是设计而不是限制 —— 强制 spec 成为单一真相源、强制每个阶段产出明确的「交接物」
