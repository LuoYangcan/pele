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
[executor subagent] —— 独立 context、跑硬验收（spec/build/lint/AMD/UI/硬约束）
  ↓ verdict==PASS
[executor 内嵌 Step 6.5] —— PASS 后跑一次外部 reviewer subagent（Opus 4.7 extended thinking，~5-10 分钟）
  ↓
主 agent: 报告 verdict==PASS + 展示 review 报告摘要 + AskUserQuestion 问「review 怎么处理」
  ↓
[review-fix 子循环（按需）] —— 用户挑修 → generator 按 Step 2.1 append AMD 再修 + 自己跑编译 → 直接进 P4（不再跑 executor，省 token）
  ↓
主 agent: AskUserQuestion 问「是否总结+更新文档」 → 按用户选择执行 → 等下一步指令

verdict==FAIL 路径：主 agent 把 issues 整理给 generator 重写（最多 3 次）
3 次都失败 → 报给用户拍板
```

> ⚡ **并行模式扩展**：spec 第 2 节并行分组里有**多个** `parallel-N` 组时，阶段 2 / 3 走「并行模式」—— 见下方 **2B / 3B / 3C / 阶段 5** 子节。串行模式（只有 `serial` 组 / 写「全部串行」）按上图原流程跑。判别由 planner 在 spec 里标注、用户在阶段 1 末尾审 spec 时拍板，主 agent 自己**不**判断是否并行。
>
> 🔁 **review 在并行模式下的处理**：3B 各组 executor 都传 `run_review_subagent: false`（单组不跑 review）；review 只在 3C 合并 + 阶段 5 最终 executor 跑一次。

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

> ⛔ **硬约束**：
>
> planner 返回后，主 agent 的**下一个 tool call** 只能是以下之一：
>
> - `Read`（读 spec 自检）
> - `AskUserQuestion`（向用户拍板）
> - `Bash`（只读命令，如 `git status` 看 worktree 状态）
>
> **绝对不能**是 `Agent(subagent_type="generator")`。哪怕 spec 看起来无懈可击、用户原始需求看起来已经 ready-to-code，也不准自动进入阶段 2。
>
> 用户回复必须是**明确同意词**才能调 generator：「开始 / 开 / ok 开始 / 干 / go / 实现吧 / 没问题开始」之类。
>
> 用户回复**模糊**（「嗯」「让我看看」「先放着」「再想想」）→ **继续等**，不要把模糊回复脑补成同意。

#### 阶段 1.5: 用户决策后必须调 planner 同步 spec（强制闸口）

> ⛔ **硬约束**：用户对 spec 给出**实质决策**后，主 agent 的下一个 tool call **必须**是 `Agent(subagent_type="planner")`，把决策传给 planner 写进 spec 文件。**不能**跳过直接调 generator。

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
  model: <见下方「模型选择」表>,
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

**模型选择**（`model` 参数 override planner.md frontmatter 默认 sonnet）：

| 用户回复类型 | model |
| --- | --- |
| 简单确认词（「开始 / 开 / ok 开始 / 干 / go / 实现吧 / 没问题开始 / 没问题 / 没意见」） | `haiku` |
| 实质决策（改硬约束 / 改 scope / 拆任务 / 改测试用例 / append AMD / 「跳过 generator」/ 带具体内容的指令） | 不传（默认 sonnet） |

拿不准 → sonnet。

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

### 阶段 2.5: review-fix 循环（并入 executor Step 6.5）

generator 完成后**直接**进阶段 3（executor）。代码 review 由 executor 在 verdict==PASS 后内嵌跑一次（详见 `~/.claude/agents/executor.md` Step 6.5）；review 与 verdict 解耦，retry 期间不重复 review。bypass：用户主动跑 `/review` 或 `/codex:review` slash command 任何时候都可以，不是默认流程的一部分。

**generator 完成后主 agent 进阶段 3 入口前要做的事**：

1. 把 generator 改动文件清单 + 编译结果 + spec §8 DONE 列表 + `dead_code_status` 字段展示给用户：
   - `clean` → 一句话过
   - `auto_cleaned` → 列出 generator 顺手删了哪些
   - `needs_user_review` → **高亮**列出待用户判断的 dead-code 候选；用户可在阶段 3 PASS 后的 review-fix 子循环里挑修
   - `skipped:<reason>` → 一句话说明
2. 不 AskUserQuestion 问「要不要 review」 → 直接进阶段 3 调 executor
3. 用户**显式说**「先 /review 再 executor」 → 跑 /review 后再进阶段 3；用户**显式说**「不用 executor」 → bypass executor

> **「按 review 修」prompt 模板**（阶段 3A PASS 后的 review-fix 子循环复用此模板）：
>
> ```
> Agent({
>   description: "<需求一句话> — 按 review 修",
>   subagent_type: "generator",
>   prompt: """
>     Worktree slug: <slug>
>     Worktree 绝对路径: <pwd>
>     本轮任务: 按 executor review 报告修复，不扩范围、不修 §1-7
>
>     Executor review 报告路径: <.reviews/<branch>-<ts>-executor.md 绝对路径>
>     采纳范围: <全部 | 只 must-fix | 用户挑出的具体条目（列出来）>
>
>     按 ~/.claude/agents/generator.md 的 SOP 工作，本轮重点：
>     - Read review 报告全文，把采纳的项按 Step 2.1 append 成 §9 AMD（[generator 写]），然后实现、改 DONE
>     - 只改 review 里被采纳的项
>     - 不修 spec §1-7、不扩任务范围
>     - 修完跑编译确认没引入新错
>   """
> })
> ```

### 阶段 3: 调 executor（+ ui-reviewer，按用户触发）

#### Step 0: 判断本轮是否触发 ui-reviewer

UI 验收**默认不跑**。主 agent 在调 executor 前判断 `ui_review_requested`：

- 用户在本轮（或本需求的早期对话）说过「跑下 UI / UI 走查 / UI 验收 / review UI / 看下 UI 对不对 / 跑下模拟器 / 跑下 mobile-mcp」等关键词 → `ui_review_requested = true`
- 没说 → `ui_review_requested = false`

> ⛔ **不要自主判定**：哪怕 spec §4 有「iOS UI 改动专项」用例、哪怕 generator 改了 view 文件，**不是**主 agent 自己决定要不要跑 ui-reviewer。**用户没明说就 = false**。spec §4 列了用例 + 用户没说 UI 验收时，主 agent 报告里提示「spec §4 有 UI 用例但本轮没跑 ui-reviewer，需要 UI 验收请明说」，让用户自己决定。

`ui_review_requested == true` 时主 agent 在调 executor 的**同一个 message** 里并行起一个 ui-reviewer（`run_in_background: true`）。两个 subagent 都 PASS 才算整体 PASS（详见下方分支）。

`ui_review_requested == false` 时本节后续所有 ui-reviewer 相关步骤跳过。

#### 3A: 串行模式（默认）

```
# ui_review_requested == false 时只调 executor；== true 时同 message 里两个 Agent call 都 run_in_background
Agent({
  description: "<需求一句话> — 验收",
  subagent_type: "executor",
  prompt: """
    Worktree slug: <slug>
    Worktree 绝对路径: <pwd>
    Generator 改动文件清单: <generator 返回的清单>
    本轮重试次数: <1 | 2 | 3>
    run_review_subagent: true   ← 默认值；review-fix 后的 retry 改成 false（见下方「3A PASS 后 review-fix 子循环」）

    按 ~/.claude/agents/executor.md 的 SOP 工作。
  """
})

# 仅 ui_review_requested == true 时同 message 里再发一个：
Agent({
  description: "<需求一句话> — UI 验收",
  subagent_type: "ui-reviewer",
  run_in_background: true,
  prompt: """
    Worktree slug: <slug>
    Worktree 绝对路径: <pwd>
    Generator 改动文件清单: <generator 返回的清单>
    本轮重试次数: <1 | 2 | 3>

    按 ~/.claude/agents/ui-reviewer.md 的 SOP 工作。
  """
})
```

两个 subagent 返回结构化结论后合并 verdict：

- **两个都 PASS**（或 ui_review_requested==false 时单 executor PASS）→ 进入「3A PASS 后流程」
- **任一 FAIL** → 进入阶段 4（详见阶段 4「`ui_review_requested == true` 时的双路径」段）

##### 3A PASS 后流程

`verdict == PASS` 时主 agent 顺序做下面三件事，**不要跳序**：

**Step P1: 报告 + amendment 提示**

把这些字段一次性报给用户：

- `executor 通过了`
- 如果 `ui_review_requested == true`：`ui-reviewer 通过了` + ui-reviewer 返回的字段（详见下方「ui-reviewer 字段路由」段）
- 如果 `ui_review_requested == false` 但 spec §4 有「iOS UI 改动专项」用例：提示「spec §4 有 UI 用例但本轮没跑 ui-reviewer，需要 UI 验收请明说『跑下 UI 验收』」
- `warning` 列表（如有）
- `amendments_verified` 三个 list（done_verified / done_failed 应为空 / todo_skipped）

**ui-reviewer 字段路由**（仅 `ui_review_requested == true` 时适用）：

- `ui_verified: pass` —— 把 `ui_screenshots_dir` 路径告诉用户。同时：
  - `ui_dynamic_cases_verified` 非空 → 透传给用户（让他知道 ui-reviewer 看了哪些动画 + 帧路径），允许用户 Read 帧自己复查；不强求他再跑 simulator
  - `ui_dynamic_cases_skipped` 非空（skill 失败的动态用例）→ 必须把列表展示给用户、提示「这几条 skill 验不了、要自己看动画」
- `ui_verified: fail` —— **静态间距用例**至少 1 条 frame/对齐与 spec 不符或动态 record skill verdict=fail。ui-reviewer verdict 一定是 FAIL；走阶段 4 重试
- `ui_verified: degraded` —— **不是 generator 的错**。两类原因：(a) environment 问题（build artifact / simulator / install/launch 失败）；(b) 全部用例都是动态、record skill 全部失败降级。ui-reviewer verdict 仍可能 PASS；主 agent 把 `ui_smoke_required: true` + `ui_degradation_reason` + `ui_dynamic_cases_skipped`（如有）报给用户。**不要**因为 `ui_verified: degraded` 重调 generator
- `ui_verified: not_applicable` —— spec 没 iOS UI 改动专项；如果 `ui_review_requested == true` 而 ui-reviewer 返回 not_applicable，提示用户「本需求没 UI 改动 / spec §4 没列 UI 用例，UI 验收无内容可跑」

**Step P2: 展示 review 报告 + AskUserQuestion 问「review 怎么处理」**

按 `review_subagent_status` 路由：

- `success` → 把 review 元信息展示给用户：
  - `review_subagent_verdict`（pass / pass-with-nits / fail）
  - `review_findings_count`（must_fix / suggestions / test_residue / dead_code / spec_deviations 各计数）
  - `review_summary`（一句话）
  - `review_file` 绝对路径 —— 让用户自己打开看细节，**不要**在 chat 里贴整份 review
  
  然后 AskUserQuestion 问「review 怎么处理」，给选项（**第一个标 Recommended**）：
  
  - **全部采纳，调 generator 修**（Recommended，当 review_subagent_verdict==fail 时）
  - **只采纳 must-fix，调 generator 修**（Recommended，当 review_subagent_verdict==pass-with-nits 时）
  - **打开 review 文件我自己挑** —— 等用户在主对话里列具体条目
  - **跳过 review，进入下一步** —— review 留着以后参考；当 review_subagent_verdict==pass 时这个是 Recommended
  
  用户挑「修」 → 进入「Step P3 review-fix 单轮子循环」；挑「跳过」 → 直接进 Step P4
  
- `failed` → 把 `review_subagent_error` 报给用户，AskUserQuestion 问「下一步」，给选项：
  - **跳过 review，进入下一步**（Recommended）
  - **主动跑一次 `/review` 重试** —— 走 commands/review.md 的 SOP
  - **暂停，等我下一步指令**
- `skipped:verdict_fail` —— 不该出现在 PASS 路径里（这个 status 只在 FAIL 时给）；如果误标了就当 warning 提示用户后忽略
- `skipped:flag_off` —— 这是 review-fix 子循环后的 retry executor 才会出现（主 agent 自己传了 false），跳过 Step P2 直接进 Step P3 / P4

**Step P3: review-fix（仅当用户挑「修」时）—— 不跑 retry executor**

1. 调 generator 按 review 修，prompt 用阶段 2.5 末尾的「按 review 修 prompt 模板」（带 `Executor review 报告路径` 字段）
2. generator 修完返回 → 主 agent **自己**做下面这套轻量验证（不调 executor）：
   - Read generator 返回的结构化结论，确认：编译通过 / 改动文件清单合理 / 没动 spec §1-7 / §9 AMD 状态推进了
   - 把改动文件清单 + 编译结果一句话报给用户
3. 直接进 **Step P4 文档同步**

**注意**：

- review-fix 期间 generator 可能改坏 §4-5 验收 / UI / 硬约束（前置假设：generator 遵守自己的 SOP——编译验证 / 不扩范围 / AMD append）；用户在 P4 时可显式说「再跑一次 executor」bypass
- **关键路径触发**（任一即触发；主 agent 在 Step P3 第 2 步轻量验证完后判一次）：
  1. **抽象层文件**：generator 改的文件名匹配 `*Protocol.swift` / `*Store.swift` / `*Reducer.swift` / `*Service.swift` / `*Manager.swift` / `*Coordinator.swift`（跨调用方的抽象层）
  2. **trigger-on-touch 命中**：改动命中项目根 `AGENTS.md` / `CLAUDE.md` 列的「改动以下任一范围前先读该文档」路径（用 `Skill(scan-trigger-docs)` 跑一次校验）
  3. **review issues 多**：`review_findings_count.must_fix >= 3`
  
  任一触发 → 主 agent 报给用户时加一句：「⚠️ 本轮 review-fix 触及关键路径（命中规则：<编号列表>），建议手动复核 / 或显式说『再跑一次 executor』」
- 阶段 4 失败循环默认仍跑 retry executor；两条跳过路径：(1) PASS 后的 review-fix（本 Step P3）；(2) 阶段 4 lint-only 快速路径（详见阶段 4 段）

**Step P4: 文档同步问询 + 收尾**

AskUserQuestion 问「要不要现在总结这次工作 + 更新项目文档？」，给 3 个选项：

- **总结 + 更新文档（推荐）**：主 agent 自己复盘本轮改动里**对未来 agent 行为有持续影响**的部分（新工作流 / 改了项目结构 / 改了模块边界 / 引入新工具链 / 新约定）→ 列出建议更新的具体文档路径 + 每处改动大纲（CLAUDE.md / AGENTS.md / docs/*.md / rules / skills 都可能）→ 用户拍板大方向后 agent Edit 落地 → 让用户 review diff → 满意就 commit
- **跳过文档**：本次改动只是常规业务代码 / UI / bug fix，对 agent 没新约束，直接进入下一步
- **稍后再说**：留着这次改动，先做别的；后续 `/openpr` 时仍会再问一遍（见 `commands/openpr.md`「文档同步检查」）

**不要默认跳过 —— 必须问**。问完按用户的选择执行；用户选完后再告诉用户「可以 `/openpr` 或继续做下一个需求」。

#### 3B: 并行模式（每组各自跑 executor，ui-reviewer 不进 3B）

> 并行模式下 ui-reviewer **不进 3B** —— 每组 sub-worktree 各自跑 executor 时，UI 验收（如果用户触发了）留到 3C 合并后或阶段 5 最终验收时**在主 worktree 跑一次**。

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
    run_review_subagent: false   ← 并行模式下单组验收不跑 review，review 留到阶段 5 最终验收时跑一次
    
    按 ~/.claude/agents/executor.md 的 SOP 工作。
    本轮验收范围**只看本组负责的子任务**对应的 spec 验收标准；
    spec 第 4 节里其他组的测试用例不要纳入本轮验收。
  """
})
Agent({...parallel-2 验收...}, run_in_background: true)
Agent({...serial 验收...}, run_in_background: true)
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

清理完后 → **进入阶段 5（最终 executor，含 review；如 `ui_review_requested == true` 同时跑 ui-reviewer）**。

### 阶段 4: 失败循环（最多 3 次）

```
i = 1
fast_path_used = false
while i <= 3:
    判断本轮入口模式：
    
    if (executor 上轮 lint_only_fail == true)
       and (ui-reviewer 上轮 PASS / not_applicable / 未触发)
       and (not fast_path_used):
        # 【lint-only 快速路径】—— 不调 retry executor
        调 generator，prompt 里追加：
          - executor review 文件路径: `.specs/<slug>-review.md`
          - 本轮是第 i 次重试 / 共 3 次
          - **显式说**「上轮 executor 仅 lint 失败、build / spec / AMD / 硬约束 / mock 等全过；
            本轮只修 review 文件里 issue_type=lint-error 的条目，不扩范围。
            修完跑项目的 lint 检查 + build 命令自验、把 build/lint 状态写进结构化结论；
            主 agent 本轮**不**再调 executor」
        generator 返回 → 主 agent **自己**做轻量验证（同 Step P3 review-fix）：
          - Read generator 结构化结论里 build / lint 状态字段
          - 改动文件清单合理（限于 review 列的 lint 修复范围）、没动 spec §1-7
          → build pass + lint pass + 改动范围合理 → 直接 break，进入 3A PASS 后流程
            （视同 executor 上轮 PASS；
          → build fail / lint 仍 fail / 改动越界 → fast_path_used = true，i += 1，
            下一轮回到常规路径重调 executor 拿完整 issues（fast path 只用一次、失败退化）
    
    else:
        # 【常规路径】（原流程）
        调 generator，prompt 里追加：
          - **executor review 文件路径**（仅 executor 上轮 FAIL 时）: `.specs/<slug>-review.md`
          - **ui-reviewer review 文件路径**（仅 ui-reviewer 上轮 FAIL 时）: `.specs/<slug>-ui-review.md`
          - 本轮是第 i 次重试 / 共 3 次
          - 显式说「请 Read 给到的 review 文件拿完整 issues + 上轮 status diff，按 issues 修复，不要扩大改动范围」
        generator 返回 → 按上轮哪个 FAIL 重调对应 subagent：
          - 只 executor FAIL → 重调 executor (retry_count = i)
          - 只 ui-reviewer FAIL → 重调 ui-reviewer (retry_count = i)
          - 两个都 FAIL → 同 message 并行重调 (run_in_background: true)
        本轮 FAIL 的全部 PASS（或单 executor 模式下 executor PASS）→ break
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

#### `ui_review_requested == true` 时的双路径

阶段 3A / 5 同时跑 executor + ui-reviewer 时，**两个都 PASS 才算整体 PASS**：

- 只 executor FAIL → generator 修代码后只重调 executor（ui-reviewer 上轮 PASS、不重跑）
- 只 ui-reviewer FAIL → generator 修代码后只重调 ui-reviewer（executor 上轮 PASS、不重跑）
- 两个都 FAIL → generator 修代码后同 message 并行重调两个

ui-reviewer 单独失败的 retry 也算 generator 的失败重试次数（计入 ≤3 次循环），因为根因是 generator 写的 UI 代码不对。**例外**：`ui_verified: degraded` 不算 generator 的错（environment 问题），主 agent 不重调 generator、直接走 PASS 路径报告给用户。

#### 并行模式下的 scope 限定

阶段 3B 的某组 executor FAIL → 进入本循环但 scope **只针对该组**：

- 重调 generator 的 prompt 里 worktree 绝对路径、spec 子任务 ID、本轮重试次数都限定到**该组**
- 其他已 PASS 的组的 sub-worktree **不动**、不重新 build、不重新 executor
- 该组 3 次重试仍 FAIL → 报给用户决定，已 PASS 组保留等待
- 用户决定的可能选项：放弃该组（接受其他组成果）/ 整体回滚 / 升级 spec 重划分组

### 阶段 5: 最终验收（仅并行模式）

并行模式下 3C 合并 + build 验证通过后**必须**再跑一次 executor —— **review 也在这一步跑**（3B 各组都没跑 review）：

```
# 总是调 executor
Agent({
  description: "<需求> — 最终验收",
  subagent_type: "executor",
  prompt: """
    Worktree slug: <主 slug>
    Worktree 绝对路径: <主 worktree 绝对路径>
    Generator 改动文件清单: <各组合并后的整体改动清单>
    本轮重试次数: 1
    最终验收模式: 是
    run_review_subagent: true   ← 并行模式 review 在此唯一一次入口
    
    按 ~/.claude/agents/executor.md 的 SOP 工作。
    验收范围：spec 第 4 / 5 / 6 节的整体（不分组）。
  """
})

# 仅 ui_review_requested == true 时同 message 里再发一个：
Agent({
  description: "<需求> — 最终 UI 验收",
  subagent_type: "ui-reviewer",
  run_in_background: true,
  prompt: """
    Worktree slug: <主 slug>
    Worktree 绝对路径: <主 worktree 绝对路径>
    Generator 改动文件清单: <各组合并后的整体改动清单>
    本轮重试次数: 1
    最终验收模式: 是
    
    按 ~/.claude/agents/ui-reviewer.md 的 SOP 工作。
    验收范围：spec 第 4 节 iOS UI 改动专项的整体（不分组）。
  """
})
```

- **全部 PASS**（executor + ui-reviewer 如有）→ 进入 3A PASS 后流程（Step P1 → P2 → P3 review-fix 子循环（按需）→ P4 文档同步）
- **任一 FAIL** → 走阶段 4 失败循环（**不分组**，整体重做改动；按上方「`ui_review_requested == true` 时的双路径」段路由），最多 3 次；阶段 4 retry 期间所有 executor 都传 `run_review_subagent: false`，直到下一次 PASS 才让 review 再跑（或如果首次 review 已经跑过、用户已经看过，retry 后的 PASS 也不重 review）

> 串行模式（2A）下不存在阶段 5 —— 阶段 3A 的 executor / ui-reviewer 已经在第一次 PASS 时跑过 review，不需要重复。

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

前两种是漂移、自救即可，**不要**写 feedback 文件停手；第三种才是真不确定。

## §9 Amendments 写权限边界（与 §8 并列、与 §1-7 不同）

§9 收录**实现阶段用户追加的具体指令**（bug fix / 微调 / review-fix 修复项 / 临时新增的具体效果要求）。**追加专用，不动 §1-7**——原始需求快照（§1-7）保持纯净，方便回溯"最初想要什么"。

### 写权限

- ✅ **planner**：场景 A 二次调用时，用户决策是实现层指令（不动硬约束 / scope 边界）→ append `### AMD-N [planner 写]` 到 §9（详见 `~/.claude/agents/planner.md`「场景 A 路由表」段）
- ✅ **generator**：迭代中收到用户具体指令（主对话里口头说 / review-fix 采纳项）→ Step 2.1 自己 append `### AMD-N [generator 写]` 到 §9（详见 `~/.claude/agents/generator.md` Step 2.1）
- ❌ **主 agent**：**绝不直接 Edit §9** —— append AMD 一律走 planner 或 generator
- ❌ **任何 agent**：**不准修改 / 删除已有 AMD 条目**的「触发」/「指令」/「影响范围」字段（保留审计痕迹）；若用户撤销某条，把状态改 `~~CANCELLED~~` + 注明原因

### 状态字段（与 §8 同口径）

每条 AMD 有 `**状态**: TODO | DONE` 字段。**推进该 AMD 的当事 agent 自己改**：

- planner append 的 AMD-N（[planner 写]）→ 通常 generator 后续推进时改 DONE
- generator append 的 AMD-N（[generator 写]）→ generator 实现完自己改 DONE
- executor 看到 `status=DONE` 的 AMD 才验收；`status=TODO` 跳过本轮（与 §8 TODO 子任务同处理）

### 决策路由（主 agent 在阶段 1.5 / 2 / 2.5 / 3 收到用户反馈时）

| 用户反馈类型 | 主 agent 走法 |
| ---- | ---- |
| 改硬约束 / 改 scope / 拆任务 / 改测试用例 | 调 planner → planner Edit §1-7 + 更新日志 |
| **bug fix / 微调 / "这里加 loading" / 阶段 2.5 review-fix 挑的修复项** | 调 generator（在 prompt 里说「请按 Step 2.1 自己 append §9 AMD 再修」）—— planner 不参与 |
| 用户决策同步阶段提的实现层指令（"开始实现之前先把 X bug 修掉"） | 调 planner → planner 走「场景 A 路由表」append AMD（[planner 写]） |

### Executor 验收 §9 的口径

- `status=DONE` 的 AMD：**与 §1-7 等价的验收基线**，逐条核对实现是否真满足；不满足 → blocking issue（`issue_type: amendment-not-fulfilled`、`amendment_ref: AMD-N`、`spec_section: 9`）
- `status=TODO` 的 AMD：跳过本轮（不影响 PASS/FAIL），在 notes 里提一句「§9 还有 N 条 amendment 处于 TODO」
- 结构化结论新增 `amendments_verified` 字段（`done_verified` / `done_failed` / `todo_skipped` 三个列表）；详见 `~/.claude/agents/executor.md` Step 7

### Amendments 在阶段 4 失败循环里的角色

阶段 4 retry 时 generator 看 `.specs/<slug>-review.md` 拿 issues，**同时**仍要 Read 整个 spec（§1-7 + §8 + §9）—— §9 是与 §1-7 等价的约束。executor 上一轮判 FAIL 时如果有 `amendment_ref: AMD-N` 的 issue（DONE 但实际没修对），下一轮 generator 要继续把那条 AMD 修对、状态保持 DONE。

## 主 agent **绝对不能**做的事

- ❌ Edit / Write / NotebookEdit 任何代码文件 —— 一律走 generator
- ❌ Edit / Write `.specs/<slug>.md` 的任何部分 —— §1-7 走 planner、§8 走 generator、§9 走 planner / generator（按上方「§9 写权限边界」决策路由）
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
- `review-mobile-ui` skill + `ui-reviewer` agent：UI 验收的独立路径；默认不跑、用户显式触发（关键词「跑下 UI / UI 走查 / UI 验收 / review UI / 看下 UI 对不对」）。验收 verdict blocking，UI fail 走阶段 4 重试；与 executor 平行、互不污染。详见 `~/.claude/skills/review-mobile-ui/SKILL.md` 和 `~/.claude/agents/ui-reviewer.md`

## Why（核心）

- 三个 subagent 独立 context；主 agent 不写代码、只调度 —— 通信走文件（spec / 代码）和主 agent 中转的结构化 message
- 失败循环上限 = 3 —— 超过说明问题不在代码层，强制升级让用户介入
- §9 Amendments 与 §1-7 分离 —— 原始需求快照纯净，实现阶段追加走 §9 + 给 executor 明确「DONE 必验 / TODO 跳过」口径
