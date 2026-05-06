# 回合末验证：只验编译

代码改完（Edit / Write 有任何落地）后，本轮验证只跑**编译**，**不**主动跑项目的 lint / test / format-fix 命令。

- 按平台跑对应的 build 命令（如 `<your build-ios recipe>` / `<your build-macos recipe>` / `swift build` / `npm run build` / `cargo build` 等）
- 只改单个 package：跑该 package 的 build

> 项目级 AGENTS.md 里如果有"每次迭代跑全套 lint + test"的默认做法，本规则覆盖它。

## Why

完整的 lint / test 套件耗时长，并且已经在两处兜底：

1. `.claude/settings.json` 的 PreToolUse hook 在 `git push` / `gh pr create` 前自动跑 lint check（如果你配置了）
2. CI 上跑完整 check + test

每轮都跑拖慢迭代节奏，除非用户明确要求、或这次改的就是测试/lint 相关代码。

## How to apply

- 代码改完 → 跑 build 验证编译 → 按「回合末询问 + /openpr 流程」问下一步
- 用户明确说"跑 check" / "跑 test" 时再跑
- 不要把 lint / test 塞进常规收尾 checklist
