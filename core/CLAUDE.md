# 全局规则索引（按需加载）

## 编码回合入口

- **原生 Plan mode**：由当前 Root 只读调研、澄清并产出最终 plan；不加载 `plan-first-delivery`，不写代码或计划文件。最终 plan 是同一任务后续实现的需求真相源。
- **Default mode 写代码**：第一步加载 `Skill(plan-first-delivery)`。同一任务已有最终 plan 时直接执行，不重写计划或增加固定 checkpoint；没有 plan 时按 skill 的入口路由处理。
- **代码改动一律 worktree**：任何要落地 Edit/Write 的编码任务，第一次写入前加载 `Skill(use-worktree)` 在仓库 `.worktrees/` 建隔离 worktree；编码任务不得在主仓 checkout 写入（meta 配置按下一条路由）。不主动切换主仓分支、不清理其 dirty 状态；主仓不在基线分支或不干净时保持原样，worktree 一律从 `origin/<基线>` 创建、不依赖主仓 HEAD。延续当前任务（worktree 内迭代）、已在 worktree、纯问答/只读诊断不触发。
- **Meta 配置**：rule / skill / agent / hook / settings 不走 `plan-first-delivery` 或 ExecPlan，但不豁免 protected-branch、dirty tree 和外部写入权限。repo-backed meta 在 main/master/dev 上先切任务分支或 worktree；非 Git 全局配置可在确认 live target 后直接改。写前检查 symlink/hook 实际目标，写后按触达类型运行 JSON/TOML parse、`bash -n`、Markdown/local-link check、installer dry-run/idempotency；除非配置直接影响 app，不跑 app build。
- **回合 checkpoint**：同一需求连续超过 3 回合仍未收敛时读 `rules/iteration-checkpoint.md`。

纯问答、读代码、查状态以及 meta 配置不走编码交付流程；仍执行上面的目标化安全与验证步骤。

## Workflow

- [plan-first-delivery](skills/plan-first-delivery/SKILL.md) — Default mode 的写代码主流程：Root（规划档强模型）规划、集成与统一验证，实现默认委派 implementer（实现档模型），按需记录轻量自作主张审计，独立 verifier / UI reviewer / 并行 worker 按正交 gate 触发。
- [exec-plan](skills/exec-plan/SKILL.md) — 仅跨会话、跨 host、多 writer、不可逆迁移或审计交接时，把最终 plan 持久化成单文件 ExecPlan。
- [use-worktree](skills/use-worktree/SKILL.md) — 代码改动一律从最新目标分支创建隔离 worktree（`scripts/worktree-bootstrap.sh` 一键创建+初始化，符合条件的旧 worktree 可复用），主仓 checkout 保持只读。
- [parallel-subagents](skills/parallel-subagents/SKILL.md) — 只读调研可并行；写任务仅在写域互斥且能明显提速时并行，Root 统一集成和最终验证。
- [post-change-verify](rules/post-change-verify.md) — 最终候选先跑相关 cheap lint/check，再 build，并按需求或风险跑 targeted tests；源码变化使旧证据失效。
- [agent-readable-docs](skills/agent-readable-docs/SKILL.md) — 创建或修改 agent-consumed operational Markdown 时内联压缩并保持语义合同；只读应用、普通人类文档和纯格式/链接修改不触发。
- [cleanup-and-exit](skills/cleanup-and-exit/SKILL.md) — 用户要求清理当前 worktree 或退出时使用。
- [commit-message](rules/commit-message.md) — 写 commit message 时使用 conventional commit 单行格式，并按仓库归属决定 trailer。

## 设计与代码质量

- [architecture-first](skills/architecture-first/SKILL.md) — 仅用户明确要求架构评审，或最终 plan/项目规则未解决的模块 ownership、依赖方向、公共契约、状态真相源或副作用边界决策触发；局部抽象、分支、坏味道和 lint 不触发。
- [scan-trigger-docs](skills/scan-trigger-docs/SKILL.md) — 改源码前扫描项目 AGENTS/CLAUDE 的 trigger-on-touch 文档并读取命中项。
- [lean-diff](skills/lean-diff/SKILL.md) — 非平凡代码写入前检查 patchwork、过度抽象、注释噪声和防御式膨胀。
- [lint-repair-strategy](skills/lint-repair-strategy/SKILL.md) — 修 lint 时按类别选结构性修法，不用无语义拆文件绕阈值。
- [swift-formatting](rules/swift-formatting.md) — 修改 Swift 时遵守项目 lint/format 约定。
- [ios-list-ui-container](rules/ios-list-ui-container.md) — 写或重构 iOS 同类滚动列表时选择虚拟化容器。

## 专用操作

- [open-sim](skills/open-sim/SKILL.md) — 用户要求编译并在 iOS Simulator 打开时使用。
- [run-device](skills/run-device/SKILL.md) — 用户要求安装或运行到真实 iPhone 时使用。
- [figma-precise-extract](skills/figma-precise-extract/SKILL.md) — Figma→code 需要精确尺寸、间距或 token 时使用。
- [figma-asset-export](skills/figma-asset-export/SKILL.md) — 从 Figma 导出自定义图标、插画或 logo 进 iOS 时使用。

## Apple 平台知识（Xcode 提供）

这组 skill 不随 Pele 发布：安装后运行 `scripts/sync-xcode-skills.sh` 从本机 Xcode 导出到 `skills/`（Xcode 升级后重跑该脚本或 `install.sh`，正文不手改）。导出的 skill 与 `xcode` MCP（build / run / test、crash 与 field performance 日志、String Catalog、target 与 build setting）同源，MCP 未注册时 device-interaction 不可用。典型包括 swiftui-specialist、swiftui-whats-new、uikit-app-modernization、app-intents-specialist、device-interaction、audit-xcode-security-settings、adopt-c-bounds-safety、modernize-tests 等，触发条件见各自 description。

## 加载约定

- 只加载本轮触发的正文；skill 引用的额外 reference 也只按路由读取。
- 用户点名 skill 时必须加载；不确定是否命中时，先读其 description 再判断。
- 规则冲突时，用户指令和项目级 AGENTS/CLAUDE 高于本全局索引。
