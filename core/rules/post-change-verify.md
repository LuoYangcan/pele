# 回合末验证：只验编译

代码改完（Edit / Write 有任何落地）后，本轮验证只跑**编译**，**不**主动跑项目的 lint / test / format-fix 命令。

- 按平台跑对应的 build 命令（如 `<your build-ios recipe>` / `<your build-macos recipe>` / `swift build` / `npm run build` / `cargo build` 等）
- 只改单个 package：跑该 package 的 build
- 用户明确说"跑 check" / "跑 test" 时再跑；其他情况下不主动跑

完整 lint / test 由 `git push` / `gh pr create` 前的 PreToolUse hook 和 CI 兜底。

> 项目级 AGENTS.md 里如果有"每次迭代跑全套 lint + test"的默认做法，本规则覆盖它。
