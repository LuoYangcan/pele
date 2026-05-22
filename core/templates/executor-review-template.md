# Executor → Generator Review

> executor 验收 FAIL 时把 issues 落到这里给 generator 重试时参考。多轮失败 → **追加** iter 章节（不覆盖旧的），保留累积视图。
>
> 文件位置：`.specs/<slug>-review.md`（worktree 根、和 spec 同 slug）。
>

---

## iter-N · `<YYYY-MM-DD HH:MM>`

> 每次 executor FAIL 就追加一个 `## iter-N` 节。N 从 1 起递增（与本 spec 的 generator iter 编号**独立**计数）。

### 触发场景

- **本轮重试次数（generator 视角）**: `<retry_count，主 agent 入参>`
- **本轮 verdict**: `FAIL`
- **build 状态**: `<pass | fail / 错误摘要>`
- **lint 状态**: `<pass | fail | skipped / 错误摘要>`

### Blocking issues（共 `<N>` 条）

> blocking 触发打回。逐条按下面格式列。

- `<file>:<line>` · `<issue_type>` · spec §`<N>`
  - **描述**：<一句话>
  - **建议修**：<suggested_fix；不强求，但有就写>

- ...（按 blocking 数量复制）

### Warning（共 `<M>` 条）

> warning 不阻断本轮、但写在这给 generator 下轮顺手修；多轮累积时也帮 generator 看「上轮 warning 是不是变成 blocking 了」。

- `<file>:<line>` · `<issue_type>` · spec §`<N>`
  - **描述**：<一句话>
  - **建议修**：<如有>

- ...

### UI 验证状态

- **ui_verified**: `<pass | fail | degraded | not_applicable>`
- **ui_dynamic_cases_skipped**（动态用例需用户自己跑）：
  - `<case_number>` — `<spec_description 摘要>`
  - ...
- **ui_screenshots_dir**: `<绝对路径，如有>`
- **ui_degradation_reason**: `<reason，仅 degraded 时给>`

### 与上一轮（iter-N-1）的 diff

> 仅 N >= 2 时填。grep 上一轮 issues 的 `file:line` 字段、与本轮对比分类。

- ✅ **上轮已修复的 issues**：
  - `<file>:<line>` `<issue_type>` <一句话摘要>
  - ...
- ❌ **上轮未修复仍存在的 issues**：
  - `<file>:<line>` `<issue_type>` <一句话摘要>
  - ...
- 🆕 **本轮新冒出的 issues**（generator 修上轮 issue 时引入的）：
  - `<file>:<line>` `<issue_type>` <一句话摘要>
  - ...

### freeze 与 scope 核对

> 即使没产生 blocking issue，每轮简短记一次状态，方便累积比对。

- spec §6 freeze 列表全部守住：`<是 | 否；如否，列出被破的项>`
- spec §6 「不在 scope 的事」未被扩：`<是 | 否；如否，列出顺手扩的范围>`
- 落地位置（`git diff --name-only origin/dev..HEAD`）全部在 spec §6 圈定范围内：`<是 | 否>`

### 整体 notes

executor 一句话评语 —— 例：「代码契约都到位、freeze 守住、build 过；本轮失败仅因 N 处 lint，修复成本低」/「上轮修了 3 / 5，新增 1 条 race，需要 generator 重审 §7 风险 7 的混用 dedup 路径」之类。

---

## iter-N+1 · `<YYYY-MM-DD HH:MM>`

（下一轮失败后追加，结构同上）
