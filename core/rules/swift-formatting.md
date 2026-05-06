# Swift 代码风格

- 所有 Swift 代码必须遵守项目配置的 SwiftLint 和 SwiftFormat 规则（典型配置文件：`.swiftlint.yml` / `.swiftformat`）
- 规则冲突时以自动修复器为准：若项目的 lint-fix 命令改了代码风格，服从它，不要回滚
- 不允许用 `// swiftlint:disable ...` 绕过规则，除非理由清晰且写在注释里

> push / 开 PR 前的强制 `<your project's lint-check command>` 由 PreToolUse hook 兜底（如果你配置了），本规则不重复规定操作步骤。
