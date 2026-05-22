# 回合末验证：只验编译

代码改完（Edit / Write 有任何落地）后，本轮验证只跑**编译**，**不**主动跑项目的 lint / test / format-fix 命令。

- 按项目实际 build 命令执行 —— 从 Justfile / Makefile / package.json scripts / Cargo.toml / 项目根 AGENTS.md / CLAUDE.md 中识别；都识别不出来就问用户
- 只改单个 package：跑该 package 的 build，不必跑整 workspace
- 用户明确说"跑 check" / "跑 test" / "跑 format" 时再跑；其他情况下不主动跑
- 多平台 / 多 target 项目：只跑本轮改动涉及的平台 / target 的 build

完整 lint / test 由 `git push` / `gh pr create` 前的 PreToolUse hook 和 CI 兜底。

> 项目级 AGENTS.md 里如果有"每次迭代跑全套 lint + test"的默认做法，本规则覆盖它。
