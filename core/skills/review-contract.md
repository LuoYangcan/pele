# Review Contract

Shared contract for the Claude and Codex source-command review backends. Backend skills own tool invocation; this file owns scope, schemas, verdicts, and report format.

## Modes

- `active-command`: run cleanup, build verification, and report-only review; include the cleanup annex in the report
- `embedded-review`: run only report-only review after another workflow has validated the code; never run cleanup or edit files

Inputs:

- `base_ref`: default `dev` for active commands and `origin/dev` for executor-embedded review
- `report_suffix`: default empty for active commands and `-executor` for executor-embedded review
- `report_path`: absolute path computed from branch, timestamp, and `report_suffix`
- `snapshot_path`: active-command pre-cleanup patch path
- `cleanup_result`: required in active-command mode; set to `none` in embedded-review mode

## Scope and Artifacts

Default target: `<base_ref>...HEAD` plus staged, unstaged, and untracked working-tree changes.

Inspect:

```bash
git status --short
git log --oneline <base_ref>..HEAD
git diff <base_ref>...HEAD
git diff
git diff --cached
```

Freeze the relevant untracked path list from this initial status before creating `.reviews/`. Read those files, exclude `.reviews/` artifacts from the target, and do not add newly created review artifacts to the frozen list. If the branch diff, tracked working-tree diff, staged diff, and relevant untracked files are all empty, stop with `没有可 review 的 diff`.

In `active-command` mode, create:

```bash
branch=$(git branch --show-current)
ts=$(date +%Y%m%d-%H%M%S)
repo_root=$(git rev-parse --show-toplevel)
report_path="${repo_root}/.reviews/${branch//\//-}-${ts}<report_suffix>.md"
snapshot_path="${repo_root}/.reviews/${branch//\//-}-${ts}-pre-simplify.patch"
mkdir -p "${repo_root}/.reviews"
git diff HEAD > "$snapshot_path"
```

The snapshot records tracked working-tree state immediately before cleanup. Do not commit it.

Cleanup may edit only files tracked at snapshot time. It must not edit existing untracked files or create new files because the patch snapshot cannot restore them. Put untracked cleanup findings in `skipped`; the reviewer still reviews those files.

## Cleanup Result Schema

In active-command mode, return both lists even when empty:

```yaml
fixed:
  - file: <path>
    line: <line after fix>
    category: reuse | simplification | efficiency | altitude
    summary: <behavior-preserving change>
skipped:
  - file: <path>
    line: <line>
    category: reuse | simplification | efficiency | altitude
    summary: <finding>
    reason: <why it was unsafe or out of scope>
```

If cleanup changed code, start the project's documented build verification concurrently with review when supported. Do not run lint, tests, or format-fix unless the user asks.

## Reviewer Input

Give the reviewer a self-contained prompt containing:

- target: `<base_ref>...HEAD` plus staged/unstaged changes and the initially frozen untracked files; exclude `.reviews/` artifacts
- report-only: do not edit, commit, push, open a PR, merge, or post comments
- cleanup result in active-command mode: the complete `fixed` and `skipped` lists
- dedupe in active-command mode: verify cleanup preserved behavior; do not re-report already-fixed cleanup
- the checklist below

Checklist:

1. correctness: edge cases, nil/empty states, error paths, concurrency, memory/thread safety, and hot-path performance
2. project rules: applicable `AGENTS.md`, `CLAUDE.md`, and trigger-on-touch documents
3. package boundaries: dependency direction, shared/business ownership, and resource placement
4. platform gating: availability checks, minimum OS versions, and conditional compilation
5. test/debug residue: debug prints/logs, TODO/FIXME/HACK/XXX, mock data, fake accounts, test URLs, debug UI, commented assertions, and stub returns
6. dead residue: unused private symbols/imports/locals/params, commented-out blocks, and duplicate legacy implementations
7. iOS performance nits: non-virtualized repeated rows, main-thread heavy work, hot-callback logic, avoidable full rebuilds, and repeated expensive allocation

Only report issues introduced or exposed by the target diff. Include file and line evidence for every finding.

## Core Review Result Schema

Both modes return:

```yaml
review_subagent_verdict: pass | pass-with-nits | fail
review_findings_count:
  must_fix: <count>
  suggestions: <count>
  test_residue: <count>
  dead_code: <count>
  spec_deviations: <count>
  perf_advisory: <count>
review_summary: <one sentence>
review_file: <report_path>
```

## Verdict

- `fail`: build failed or at least one fail-blocking finding exists
- `pass-with-nits`: no blockers; meaningful suggestions, residue, or performance nits exist
- `pass`: build passed or was not required, with no blockers or meaningful nits

## Report Format

The reviewer returns canonical Markdown in this format. The backend or designated report writer persists it to `report_path`; the reviewer must not edit source files.

- `active-command`: use the complete template and include cleanup metadata/sections
- `embedded-review`: remove “含 cleanup 落地的清理”, identify only the reviewer in the header, omit the cleanup snapshot line and both cleanup sections, and keep every core review section

```markdown
# Code Review: <branch>

> 时间：<YYYY-MM-DD HH:MM> · 范围：<base_ref>...HEAD + 未提交改动（含 cleanup 落地的清理）
> Reviewer: <backend cleanup> → <backend reviewer>（high effort，report-only）
> 清理前快照：<snapshot_path>

## Verdict

`pass` / `fail` / `pass-with-nits`

一句话总结：...

## 必修（fail-blocking）

- [ ] **<file>:<line>** — <问题>

## 建议（nice-to-have）

- [ ] ...

## Cleanup 已落地的质量修复

- **<file>:<line>** — <修了什么>（reuse / simplification / efficiency / altitude）

如果没有，写“无可修项”。

## Cleanup 跳过的发现

- [ ] **<file>:<line>** — <发现> · 跳过原因：<reason>

如果没有，写“无”。

## 测试用代码残留

- [ ] **<file>:<line>** — <residue>

如果没有，写“无残留”。

## 无用代码残留

- [ ] **<file>:<line>** — <residue>

如果没有，写“无残留”。

## iOS 性能反模式（建议层，非阻断）

- [ ] **<file>:<line>** — <nit>

如果没有，写“无”。

## 项目规范偏离

- [ ] ...

如果没有，写“全部符合”。

## 整体评估

3-5 句话：架构合理性、最大风险点、是否需要拆 PR。
```

## Return Format

In `active-command` mode, do not paste the full report. Return:

```text
Review 完成 → <report_path>

cleanup: fixed F · skipped S · build <pass/fail/not run>
Verdict: <pass/fail/pass-with-nits>
- 必修: N
- 建议: M
- 测试用代码残留: K
- 无用代码残留: L
- iOS 性能反模式: Q
- 规范偏离: P

查看报告：cat <report_path>
查看机器清理 diff：git diff
```

Then ask whether to fix all findings, fix blockers only, revert cleanup, or only inspect.

In `embedded-review` mode, return the core review result schema to the caller. Do not ask the user a follow-up question.

## Hard Constraints

- Only the cleanup phase may edit the working tree.
- The reviewer and all review subagents are read-only.
- Do not commit, push, open or merge PRs, or post PR comments.
- Do not run `/openpr` or `/pr-review`.
