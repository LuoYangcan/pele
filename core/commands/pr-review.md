---
description: PR review — Sonnet subagent review 指定 PR（默认当前分支 PR），在评论区留评
---

让 Sonnet 对一个 PR 做 review 并在评论区留评。**本 skill 只做 PR review**，不 commit、不 push、不合并。

## 参数

- 若用户传了 PR URL / 编号 → 用它
- 否则 → 用 `gh pr view --json url,number,title` 取当前分支的 PR；若不存在 → 提示「当前分支未开 PR，先开 PR 再调 `/pr-review`」

## 派发（Sonnet）

用 Agent 工具派发 subagent：

- `subagent_type`: `general-purpose`
- `model`: `sonnet`
- `description`: "Sonnet PR review"
- 任务 prompt：
  - PR URL
  - 让 subagent 自己跑 `gh pr view <url> --json title,body,files,additions,deletions` 和 `gh pr diff <url>` 读元信息与 diff
  - 从「整体思路 / 潜在风险 / 后续建议」三个角度给评价
  - **最后必须**用 `gh pr comment <url> --body "..."` 把评价发到 PR 评论区
  - 返回给主 agent 的内容：「已评论」+ 评论摘要

## 回报

把 PR URL 和 Haiku 评论摘要返给用户。不自动进下一步。

## 不做的事

- ❌ 不修代码
- ❌ 不合并 PR
- ❌ 不再跑 Sonnet review（那是 `/review` 的事）
