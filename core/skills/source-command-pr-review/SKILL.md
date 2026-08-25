---
name: "source-command-pr-review"
description: "PR review — subagent review 指定 PR（默认当前分支 PR），在评论区留评；Claude 用 Haiku，Codex 用 Terra high"
---

# source-command-pr-review

Use this skill when the user asks to run the migrated source command `pr-review`.

## Command Template

让 subagent 对一个 PR 做 review 并在评论区留评。**本 skill 只做 PR review**，不 commit、不 push、不合并。

## 参数

- 若用户传了 PR URL / 编号 → 用它
- 否则 → 用 `gh pr view --json url,number,title` 取当前分支的 PR；若不存在 → 提示「当前分支未开 PR，先开 PR 再调 `/pr-review`」

## 派发

用 Agent 工具派发 subagent：

- `subagent_type`: `general-purpose`
- `model`: Claude 用 `haiku`；Codex 用 `gpt-5.6-terra` + `high`。PR review 含语义判断和外部评论，不下放 Luna
- `description`: "PR review"
- 任务 prompt：
  - PR URL
  - 让 subagent 自己跑 `gh pr view <url> --json title,body,files,additions,deletions` 和 `gh pr diff <url>` 读元信息与 diff
  - 从「整体思路 / 潜在风险 / 后续建议」三个角度给评价
  - **最后必须**用 `gh pr comment <url> --body "..."` 把评价发到 PR 评论区
  - 返回给主 agent 的内容：「已评论」+ 评论摘要

若没有 subagent 工具：主 agent 自己跑同样的 `gh pr view` / `gh pr diff` / `gh pr comment` 流程。**不要**因为 fallback 产生第二条重复评论；先查 PR comments 确认没有刚发出的评论。

## 回报

把 PR URL 和评论摘要返给用户。不自动进下一步。

## 不做的事

- ❌ 不修代码
- ❌ 不合并 PR
- ❌ 不再跑深度 review（那是 `/review` 的旗舰 reviewer 路径）
