# 全局规则索引（渐进式披露）

下列规则是**按需加载**的指针，不预先注入正文。遇到匹配的触发信号时，用 Read 读取对应文件再应用；不匹配就不必读。

## 每轮自检（写代码请求适用）

收到会落地 Edit / Write / NotebookEdit 的请求时，按下面顺序自检：

A) **澄清**（请求已经够清楚就跳过）—— 用 AskUserQuestion 问清：① 目标 ② 硬约束（落地位置 / 栈 / 不能动什么）③ 任何自己没理解 / 存疑的点

B) **新话题进 worktree**（「新任务 / 另一个 / 接下来做 X」类信号）—— 第一次 Edit 前基于最新 origin/dev 建 worktree，**不要**用 `EnterWorktree(name=...)`（会继承当前 HEAD）：
  ```
  git fetch origin dev
  git worktree add .worktrees/<slug> -b <type/scope-slug> origin/dev
  EnterWorktree(path=.worktrees/<slug>)
  # 项目特定：跑 worktree 初始化（生成 xcodeproj / npm install / build 等）
  ```

C) **回合 checkpoint**：同一需求卡 >3 回合用户仍不满 → 停下用 AskUserQuestion 问清；>7 回合 → 从头对齐方向（不要自动抛弃现有代码）。

**不触发**：纯问答 / 读代码 / 查状态 / 改 meta 配置（rule、memory、hook、settings）。完整规则见下方索引、按需 Read。

## Workflow 规则

- [dispatch-pipeline](rules/dispatch-pipeline.md) — **触发：用户提了写代码需求**（落地 Edit/Write/NotebookEdit）。主 agent 三段式调度：planner → 用户拍板 → generator → executor → PASS/FAIL；FAIL 自动重调 generator 最多 3 次。**主 agent 自己不写代码**，全部委派 subagent。不触发：纯问答 / 改 meta 配置（rule、memory、hook、settings）/ 用户明确 bypass。subagent 定义在 `~/.claude/agents/{planner,generator,executor}.md`。
- [use-worktree](skills/use-worktree/SKILL.md) — **形态：skill（不是 rule 文件）**，用 `Skill(use-worktree)` 加载，不要 Read（`rules/use-worktree.md` 已变 stub 指针，仅给历史引用兜底）。触发：用户切到新话题（「新任务/另一个/接下来做 X」）且本轮要写代码；第一次 Edit 前基于最新 origin/dev 建 worktree、跑项目初始化、cp gitignored 本地配置。不触发：延续当前任务、已在 `.worktrees/` 里、纯问答、改 meta 配置（rule / memory / hook / settings）。
- [spec-before-code](rules/spec-before-code.md) — 触发：进了 `.worktrees/<slug>/` 准备落地 Edit/Write 但 `.specs/<slug>.md` 还不存在；先澄清 → 写 spec（模板 `~/.claude/templates/spec-template.md`）→ 再 Edit。PreToolUse hook 硬卡。在 dispatch-pipeline 流程下由 planner 阶段产出 spec；hook 同时为 generator 兜底（spec 不存在则 generator 也写不动）。Bypass：`touch .specs/<slug>.skip`。
- [iteration-checkpoint](rules/iteration-checkpoint.md) — 触发：同一需求连续对话 >3 回合用户仍不满 → 停下问清；>7 回合 → 从头对齐方向。
- [architecture-first](skills/architecture-first/SKILL.md) — **形态：skill（不是 rule 文件）**，用 `Skill(architecture-first)` 加载，不要 Read。触发：选设计模式 / UI 架构 / 系统架构边界，或 review 含此类决策的 diff —— 包括引入新抽象、在已有函数里加 if-else / boolean flag、复制粘贴相似逻辑、用 try-catch / default 值掩盖症状、写 TODO 遗留账、重构 fat ViewController / Service / Manager、引入 state 管理。不触发：typo / 单行 fix / 格式调整 / rename / 在已有逻辑里做窄域追加。覆盖范围：GoF 经典对象级模式 + UI 架构（MVC/MVP/MVVM/VIPER + 单向数据流 Redux/TCA/Elm/Reducer）+ 系统架构（Clean/Hexagonal/Functional Core）+ 反补丁。和内置 `simplify` skill 正交：architecture-first 管**选模式 / 选边界**（不写代码），simplify 管改完后清理（会写代码）。
- [parallel-subagents](rules/parallel-subagents.md) — 触发：用户显式说「拆开并行跑」「派 subagent 改 B」「同时跑」时。不自主判断是否并行。
- [post-change-verify](rules/post-change-verify.md) — 触发：代码改完收尾验证；只跑编译，不主动跑项目的 lint / test / format-fix 命令（由 CI 和 PreToolUse hook 兜底）。
- [commit-message](rules/commit-message.md) — 触发：写 commit message；conventional commits 单行简短，不加 Co-Authored-By 尾巴。
- [agent-readable-docs](rules/agent-readable-docs.md) — 触发：写 / 改 `~/.claude/{rules,agents,skills,templates,commands}/*.md` 或项目 AGENTS.md / CLAUDE.md / docs/*.md（被 trigger-on-touch 引用的）。不触发：写 spec / 改代码注释 / commit message。原则：以 agent 为目标读者，删 Why 整段叙事 / 设计取舍 / 历史 / 类比 / 重复修辞 / 给文档维护者的元说明；保留触发条件 / SOP / 路由表 / prompt 模板 / 字段定义 / 硬约束 / Why 核心一句。

## 语言/栈规则

- [swift-formatting](rules/swift-formatting.md) — 触发：改 Swift 代码；遵守 SwiftLint / SwiftFormat，冲突时以项目的 lint-fix 命令为准。

## 加载约定

- 每条规则首行描述已列出**触发信号 / 不触发场景**。本轮匹配时再 Read 正文，别一次性全读。
- 规则之间正交，读一条不必读其他条。若多条同时匹配，按相关度顺序读。
- 不确定是否适用时，优先 Read + 自行判断，而不是按索引描述推断。
