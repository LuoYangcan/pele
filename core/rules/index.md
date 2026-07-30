# Pele 规则索引

下列规则 / skill / agent 都是**按需加载**的指针，不预先注入正文。遇到匹配的触发信号时，用 Read 读取对应文件再应用；不匹配就不必读。

## Workflow 规则

- [dispatch-pipeline](.claude/skills/dispatch-pipeline/SKILL.md) — **触发：用户提了写代码需求**（落地 Edit/Write/NotebookEdit）。主 agent 调 Lead Planner；大需求可 fan-out 给 `planner-worker`，由 `spec-integrator` 发布正式 spec；用户拍板后再走 generator → executor。FAIL 自动重调 generator 最多 3 次。主 agent 不写代码。不触发：纯问答 / 改 meta 配置 / 用户明确 bypass。
- [use-worktree](.claude/skills/use-worktree/SKILL.md) — **形态：skill**，用 `Skill(use-worktree)` 加载。触发：用户切到新话题（「新任务/另一个/接下来做 X」）且本轮要写代码；第一次 Edit 前基于最新远端主分支建 worktree（用 `git symbolic-ref refs/remotes/origin/HEAD` 探测，兼容 main / master / dev / trunk）、跑项目初始化、cp gitignored 本地配置。不触发：延续当前任务、已在 `.worktrees/` 里、纯问答、改 meta 配置。
- [spec-before-code](.claude/rules/spec-before-code.md) — 触发：进了 `.worktrees/<slug>/` 准备落地 Edit/Write 但 `.specs/<slug>.md` 还不存在；先澄清 → 写 spec（模板 `.claude/templates/spec-template.md`）→ 再 Edit。PreToolUse hook 硬卡（global 模式）。在 dispatch-pipeline 流程下由 planner 阶段产出 spec。Bypass：`touch .specs/<slug>.skip`。
- [iteration-checkpoint](.claude/rules/iteration-checkpoint.md) — 触发：同一需求连续对话 >3 回合用户仍不满 → 停下问清；>7 回合 → 从头对齐方向。
- [architecture-first](.claude/skills/architecture-first/SKILL.md) — **形态：skill**，用 `Skill(architecture-first)` 加载。触发：选设计模式 / UI 架构 / 系统架构边界，或 review 含此类决策的 diff —— 包括引入新抽象、在已有函数里加 if-else / boolean flag、复制粘贴相似逻辑、用 try-catch / default 值掩盖症状、写 TODO 遗留账、重构 fat ViewController / Service / Manager、引入 state 管理。不触发：typo / 单行 fix / 格式调整 / rename / 在已有逻辑里做窄域追加。覆盖：GoF 模式 + UI 架构（MVC/MVP/MVVM/VIPER + 单向数据流）+ 系统架构（Clean/Hexagonal/Functional Core）+ 反补丁。
- [parallel-subagents](.claude/skills/parallel-subagents/SKILL.md) — 触发：用户显式说「拆开并行跑」「派 subagent 改 B」「同时跑」，或 dispatch-pipeline 的 planning fan-out / 已过审实现并行模式。不自主判断是否并行。
- [cleanup-and-exit](.claude/skills/cleanup-and-exit/SKILL.md) — 触发：用户调用 `/cleanup-and-exit` / `/clean-and-exit`，或要求退出前删除 / 保留任务 worktree。
- [post-change-verify](.claude/rules/post-change-verify.md) — 触发：代码改完收尾验证；只跑编译，不主动跑项目的 lint / test / format-fix 命令（由 CI 和 PreToolUse hook 兜底）。
- [agent-readable-docs](.claude/rules/agent-readable-docs.md) — 触发：写 / 改 `.claude/{rules,agents,skills,templates,commands}/*.md` 或项目 AGENTS.md / CLAUDE.md / docs/*.md（被 trigger-on-touch 引用的）。不触发：写 spec / 改代码注释 / commit message。原则：以 agent 为目标读者，删 Why 整段叙事 / 设计取舍 / 历史 / 类比 / 重复修辞 / 给文档维护者的元说明。

## Subagents

- [planner](.claude/agents/planner.md) — Lead Planner：小需求发布正式 spec；大需求冻结 planning manifest；处理用户决策同步与 generator 反馈。
- [planner-worker](.claude/agents/planner-worker.md) — 并行规划 shard；只写自己的 draft、report 和 question 文件。
- [spec-integrator](.claude/agents/spec-integrator.md) — 汇总全部有效 planning drafts，单写正式 spec 与初始 task/risk/decision 文件。
- [generator](.claude/agents/generator.md) — 按 spec 写代码 + 跑 build 自验。dispatch-pipeline 阶段 2 由主 agent 调用。
- [executor](.claude/agents/executor.md) — 跑硬验收（build / lint / spec / AMD / 硬约束 / mock 残留）+ PASS 后跑外部 reviewer subagent。dispatch-pipeline 阶段 3 由主 agent 调用。
- [ui-reviewer](.claude/agents/ui-reviewer.md) — 移动端 UI 验收（iOS / Android Simulator + `sim-use`）。**默认不跑**，用户显式触发（「跑下 UI / UI 验收」等关键词）才走。

## 常用 skills（按需 invoke）

- [scan-trigger-docs](.claude/skills/scan-trigger-docs/SKILL.md) — 扫项目 AGENTS.md / CLAUDE.md「触发即必读」段落，按本轮范围 Read 命中的 docs/*.md。planner / generator / executor 三个 subagent 都用。
- [lean-diff](.claude/skills/lean-diff/SKILL.md) — 「别写注释 / 别堆 patch / 别写防御性 try?」的判断真相源。generator 写 diff 前自检；executor / `/review` review diff 时挑 issue。
- [dead-code](.claude/skills/dead-code/SKILL.md) — 扫描本轮 diff 里没人调的孤儿符号（孤儿函数 / 类型 / 文件 / enum case）。通用主路径：LSP findReferences + grep；Swift 项目可额外用 Periphery。
- [review-mobile-ui](.claude/skills/review-mobile-ui/SKILL.md) — `sim-use` 静态 / 动态用例验收 SOP。由 ui-reviewer 调用；generator 的 Figma diff 自测不走本 skill。
- [record-ui-animation](.claude/skills/record-ui-animation/SKILL.md) — 录屏 + 抽帧用于看动画 / 过渡 / 飞行动画等单张截图看不出的运动。
- [figma-precise-extract](.claude/skills/figma-precise-extract/SKILL.md) — 把 Figma 结构、精确测量和 token 冻结成实现可读工件。
- [figma-asset-export](.claude/skills/figma-asset-export/SKILL.md) — 导出自定义图标、插画和 logo，并确定格式、render mode 与 tint。
- [open-sim](.claude/skills/open-sim/SKILL.md) — 编译、安装并在 worktree Simulator 启动 iOS app。
- [run-device](.claude/skills/run-device/SKILL.md) — 编译、安装并在已配对真机启动 iOS app。

## 语言 / 栈规则

- [swift-formatting](.claude/rules/swift-formatting.md) — 触发：改 Swift 代码；遵守项目 SwiftLint / SwiftFormat 配置。
- [ios-list-ui-container](.claude/rules/ios-list-ui-container.md) — 触发：写 / 重构 iOS 同类条目列表；默认使用虚拟化容器。

## 项目特定接入

- 项目根 `AGENTS.md` / `CLAUDE.md` 由 harness 自动注入 memory，但里面 `[docs/x.md](docs/x.md)` 这种 markdown 链接**不会**自动注入 —— 用 `Skill(scan-trigger-docs)` 扫一遍、按本轮范围 Read 命中的 doc。
