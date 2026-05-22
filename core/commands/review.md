---
description: 纯代码 review — Opus 4.7 (extended thinking) subagent review 当前 dev...HEAD + 未提交改动，输出意见到 .reviews/<branch>-<ts>.md，不 commit、不 push、不开 PR
---

对当前分支做一轮**深度** review。**本 skill 只做 review**，不 commit、不 push、不开 PR —— 这些交给用户或 `/openpr`。

## 前置

1. `git status` 看是否有未提交改动；有就把未提交部分也纳入 review 范围
2. `git log --oneline dev..HEAD` 看领先 dev 的 commits
3. `git diff dev...HEAD` 拿到已 commit 的 diff（领先 dev 的部分）
4. `git diff` 拿到未提交的 diff
5. 若上面 3、4 都为空 → 提示「没有可 review 的 diff」并退出
6. 取 `branch=$(git branch --show-current)` 和 `ts=$(date +%Y%m%d-%H%M%S)`，输出文件路径预定为 `.reviews/${branch//\//-}-${ts}.md`（branch 里的 `/` 替换成 `-` 避免目录嵌套）
7. `mkdir -p .reviews`（若不存在）

## Review 派发（Opus 4.7 + extended thinking）

用 `Agent` 工具派发 subagent：

- `subagent_type`: `general-purpose`
- `model`: `opus`
- `description`: "Opus 4.7 deep code review"
- 任务 prompt **必须包含**：
  - 当前分支名、目标输出文件路径（`.reviews/<branch>-<ts>.md`）
  - `git diff dev...HEAD` 的输出（领先 dev 的已 commit 部分）
  - `git diff` 的输出（未提交部分）— 若非空
  - **明确指令**：「请用 extended thinking 深入分析每一处改动，不要只看表面 diff，要思考它在整个调用链 / 状态流转 / 并发 / 错误传播里的影响。如果有疑虑，先用 Read 看相关文件的完整上下文再下结论。」
  - Review 标准（**全部检查**）：
    1. **逻辑 / 正确性**：边界条件、空值、异常路径、并发安全、内存/线程问题、性能热点
    2. **项目规范**（按你 repo 内的 AGENTS.md / CLAUDE.md 列出的具体条目，例如：分节注释约定、UI 约束库用法、是否禁某些 API、测试框架选型、命名约定 等）
    3. **包归属 / 模块边界**：跨平台 / 共享 / 业务包的依赖方向是否正确；资源放置是否符合项目级 rule
    4. **平台 gating**（如多平台项目里的 `#available` / 系统版本 / 平台条件编译）是否合理
    5. **🆕 测试用代码残留**（必查）：
       - `print(...)` / `NSLog(...)` / `os_log(.debug, ...)` 这种 debug 输出
       - `// FIXME`、`// TODO`、`// HACK`、`// XXX` 标记（不是绝对禁止，但要列出来确认是否该清理）
       - hard-coded mock 数据 / 假账号 / 测试 URL（如 `https://test.example.com`、`mockUser`、`@example.com`、placeholder 字符串如 `"测试一下"`）
       - 临时 tap 计数器 / 调试 alert / 临时 UI（红框、`backgroundColor = .red` 这种排查色）
       - 注释掉的 `// fatalError(...)` / `// preconditionFailure(...)` 留下的"调试断言"
       - 没接通的 stub return（如 `return // TODO`、`return ""`）
    6. **🆕 无用代码残留**（必查）：
       - 未被引用的私有函数 / 私有属性 / 私有类型（dead code）
       - 大块被注释掉的代码（commented-out blocks）
       - 改完没删掉的旧实现（同名函数的两份、`oldFunction` / `legacyXxx` 这类重影）
       - 没用到的 import
       - 没用到的局部变量（`_` 接收的不算）
       - 函数参数定义了但没读取（用 `_` 标明的不算）
  - **输出格式要求**（subagent 必须落地这个 md 文件）：
    - **subagent 必须用 Write 工具**把 review 报告落到 `.reviews/<branch>-<ts>.md`
    - md 结构如下：

```markdown
# Code Review: <branch>

> 时间：<YYYY-MM-DD HH:MM> · 范围：dev...HEAD + 未提交改动
> Reviewer: Opus 4.7 (extended thinking)

## Verdict

`pass` / `fail` / `pass-with-nits`

一句话总结：...

## 必修（fail-blocking）

- [ ] **<file>:<line>** — <问题简述>
  - 详细：...
  - 建议：...

## 建议（nice-to-have）

- [ ] ...

## 🧹 测试用代码残留

- [ ] **<file>:<line>** — `print(...)` / mock 数据 / TODO 标记 / 临时调试 UI
  - 建议：删除 / 替换为 ...

如果没有，写一行 "无残留"。

## 🗑 无用代码残留

- [ ] **<file>:<line>** — 未引用的 `<symbol>` / 注释块 / 旧实现
  - 建议：删除 / 合并到 ...

如果没有，写一行 "无残留"。

## 项目规范偏离

- [ ] ...

如果没有，写一行 "全部符合"。

## 整体评估

3-5 句话，覆盖：架构合理性、最大风险点、是否需要拆 PR。
```

  - **subagent 完成后**返回给主 agent：报告文件路径 + verdict + issues 数量（按类别）
  - **明确告知 subagent**：不动代码、不 commit、不 push，只产出 .md 报告

## 主 agent 收到 subagent 结果后

不直接长输出整份报告。简要汇报：

```
✅ Review 完成 → .reviews/<branch>-<ts>.md

Verdict: <pass / fail / pass-with-nits>
- 必修: N 条
- 建议: M 条
- 🧹 测试用代码残留: K 处
- 🗑 无用代码残留: L 处
- 规范偏离: P 条

打开报告看详情：cat .reviews/<branch>-<ts>.md
```

然后用 `AskUserQuestion` 问用户下一步：
- 全部按建议改
- 只改"必修"
- 看完报告自己判断（不动）

## 生命周期 / PR 前清理

- 多次 `/review` 会留下多份报告（带不同 timestamp），不会互相覆盖；用户想保留可以单独移到别处，否则 `/openpr` 时会一并删

## 不做的事

- ❌ 不 commit（即使 review pass）
- ❌ 不 push
- ❌ 不开 PR
- ❌ 不调 `/openpr` 或 `/pr-review`
- ❌ 不做 UI 还原度验证（走独立的 UI 验证 skill 或 ios-simulator-mcp）
- ❌ 不在 chat 里把整份 review 报告刷出来 —— 报告在 `.reviews/`，chat 只给摘要
