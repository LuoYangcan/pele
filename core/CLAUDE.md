# 全局规则索引（渐进式披露）

下列规则是**按需加载**的指针，不预先注入正文。遇到匹配的触发信号时，用 Read 读取对应文件再应用；不匹配就不必读。

## Workflow 规则

- [dispatch-pipeline](rules/dispatch-pipeline.md) — **触发：用户提了写代码需求**（落地 Edit/Write/NotebookEdit）。主 agent 三段式调度：planner → 用户拍板 → generator → executor → PASS/FAIL；FAIL 自动重调 generator 最多 3 次。**主 agent 自己不写代码**，全部委派 subagent。不触发：纯问答 / 改 meta 配置（rule、memory、hook、settings）/ 用户明确 bypass。subagent 定义在 `~/.claude/agents/{planner,generator,executor}.md`。
- [use-worktree](rules/use-worktree.md) — 触发：用户切到新话题（「新任务/另一个/接下来做 X」）且要写代码；第一次 Edit 前基于最新 origin/dev 建 worktree。不触发：延续当前任务、已在 `.worktrees/` 里、纯问答。

  > 「写代码前先澄清」由 `UserPromptSubmit` hook 每轮注入提示兜底（见 `~/.claude/settings.json`），不再单独维护 rule 文件。
- [spec-before-code](rules/spec-before-code.md) — 触发：进了 `.worktrees/<slug>/` 准备落地 Edit/Write 但 `.specs/<slug>.md` 还不存在；先澄清 → 写 spec（模板 `~/.claude/templates/spec-template.md`）→ 再 Edit。PreToolUse hook 硬卡。在 dispatch-pipeline 流程下由 planner 阶段产出 spec；hook 同时为 generator 兜底（spec 不存在则 generator 也写不动）。Bypass：`touch .specs/<slug>.skip`。
- [iteration-checkpoint](rules/iteration-checkpoint.md) — 触发：同一需求连续对话 >3 回合用户仍不满 → 停下问清；>7 回合 → 从头对齐方向。
- [reuse-first](skills/reuse-first/SKILL.md) — **形态：skill（不是 rule 文件）**，用 `Skill(reuse-first)` 加载，不要 Read。触发：准备引入新抽象（helper / utility / extension / 组件 / Service / Manager / 新 SDK / 新 module）或 review 含此类新增的 diff；尤其跨 package 复用决策。不触发：bug fix / 格式调整 / 在已有逻辑里做窄域追加。和内置 `simplify` skill 正交：reuse-first 管事**前**预防（不写代码），simplify 管改完后清理（会写代码）。
- [parallel-subagents](rules/parallel-subagents.md) — 触发：用户显式说「拆开并行跑」「派 subagent 改 B」「同时跑」时。不自主判断是否并行。
- [post-change-verify](rules/post-change-verify.md) — 触发：代码改完收尾验证；只跑编译，不主动跑项目的 lint / test / format-fix 命令（由 CI 和 PreToolUse hook 兜底）。
- [commit-message](rules/commit-message.md) — 触发：写 commit message；conventional commits 单行简短，不加 Co-Authored-By 尾巴。

## 语言/栈规则

- [swift-formatting](rules/swift-formatting.md) — 触发：改 Swift 代码；遵守 SwiftLint / SwiftFormat，冲突时以项目的 lint-fix 命令为准。

## 加载约定

- 每条规则首行描述已列出**触发信号 / 不触发场景**。本轮匹配时再 Read 正文，别一次性全读。
- 规则之间正交，读一条不必读其他条。若多条同时匹配，按相关度顺序读。
- 不确定是否适用时，优先 Read + 自行判断，而不是按索引描述推断。
