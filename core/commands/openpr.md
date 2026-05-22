---
description: push 当前分支并开 PR。不跑 review（用 /review）、不跑 PR review（用 /pr-review）、不 merge
---

把当前分支推到 remote 并开 PR。**本 skill 只做 push + PR**，不跑 review、不 merge —— 代码 review 走 `/review`，PR review 走 `/pr-review`。

## 前置检查

- `git status`、`git log --oneline dev..HEAD`，确认：
  - 当前不在 `main` / `master` / `dev` 分支上
  - 工作区干净（无未提交改动）；若有 → 提示用户先 commit，暂停
  - 至少有一个领先 base 分支的 commit
- **不**强制要求先跑过 `/review`。review 是用户自己决定的节奏，`/openpr` 这里不 gate

## 同步远程（先拉 + rebase 再 push）

顺序：

1. `git fetch origin` —— 拉所有远程更新
2. **同步当前分支的远程**（如果存在）：
   - 检查是否有上游：`git rev-parse --abbrev-ref @{u} 2>/dev/null`
   - 有 → `git rebase origin/<当前分支>`（等价 `git pull --rebase`）
   - 无（首次 push 的新分支）→ 跳过这一步
3. **rebase 到最新 base**（默认 `origin/dev`，按你项目的 PR base 替换；`main` / `master` / `develop` 都常见）：`git rebase origin/dev`
   - 保证 PR base 是最新的，冲突在本地提前暴露
4. 成功后才进入下一节

### 冲突处理

任何一步 rebase 冲突：**中止 /openpr**，报告给用户：

- 冲突文件清单（`git status --short | grep ^U`）
- 提示两条路：
  - 手动解冲突 → `git add <files>` → `git rebase --continue` → 重跑 `/openpr`
  - 放弃同步 → `git rebase --abort` → 回到 rebase 前状态，自己决定下一步

不要 agent 自作主张调用 `--abort` 或试图解复杂冲突。

## 文档同步检查（push 前必做）

确认 worktree 改动是否需要同步项目内的 agent 文档。**只检查项目内的**：

- `CLAUDE.md` / `AGENTS.md`（项目根 + 各子目录里的）
- 上述文件**渐进式披露**索引到的子文档（`rules/*.md`、`skills/*.md`、`templates/*.md` 以及它们内部 `Read` / 引用链指向的文件）
- 渐进式披露的**索引结构本身**（新增/删除一个 rule、skill、子文档，但 `CLAUDE.md` / `AGENTS.md` 索引没改 → 算文档没同步）

不检查 `~/.claude/` 下的全局规则、用户级别 README、代码注释、CHANGELOG —— 那些不在 `/openpr` 关心的范围。

### 步骤

1. **看改动范围**：`git diff origin/dev...HEAD --stat`，列出 worktree 内所有变更文件
2. **Agent 自动判断**是否触发文档更新需求。常见触发信号：
   - 新增 / 删除 / 重命名了 rule / skill / template / hook / slash command
   - 改了某个工作流的步骤（worktree 流程、spec 流程、`/openpr` 自己等）
   - 改了项目结构、模块边界、命名约定、目录组织
   - 改了对 agent 行为有约束的配置（`settings.json` hooks、permissions、env）
   - 引入了新的 third-party SDK / 工具链 / 命令需要 agent 知道

   如果 diff 都是常规业务代码 / UI / bug fix，没碰到上述信号 → 在这一节明确写"无需更新文档"，跳到下一节
3. **用 AskUserQuestion 确认**。Agent 把判断结论 + 推测要更新的具体文档路径给用户，问清：
   - 是否真的需要更新（agent 可能误判）
   - 哪些文档要更新（列出候选）
   - 是否已经在当前 worktree 里更新过了（diff 里能看到对应文档变更就直接确认）
4. **agent 代写**：用户确认需要更新、但 worktree 里没体现对应文档变更 → **不中止 `/openpr`、不要求用户重跑**，agent 直接接手写：

   1. agent 先列出**要改的具体文件路径 + 每处的改动大纲**（一两句话说清楚加什么 / 删什么 / 改什么），用 AskUserQuestion 让用户拍板大方向（接受 / 调整 / 撤销某条）
   2. 用户拍板后 agent Edit / Write 落地到当前 worktree
   3. **写完后停下来**让用户 review diff（agent 主动跑 `git diff` 把改动展示出来）
   4. 用户 OK → agent commit（按 `commit-message.md` 风格）→ 进入下一节继续 `/openpr` 流程
   5. 用户提修改建议 → agent 按建议改、重新展示 diff，循环到 OK
   6. 用户在 review 阶段说"这部分我自己来" → 暂停 agent 落笔，让用户在当前 worktree 自己改完 commit，然后告诉 agent 继续 `/openpr`（不需要重跑）

### 跳过本节

用户明确说"这次不用更新文档" / "下个 PR 一起更" / "已经在另一个 PR 里更过了" → 跳过本节，但在最终的 PR body 里加一行说明（如 `docs follow-up: tracked in #123` 或 `docs intentionally deferred: <原因>`），方便后续追踪，避免文档债静默堆积。

## 清理临时目录（push 前必做）

push / 开 PR 前，自动清理 pele 工作流的临时目录——这些目录靠 `.gitignore` 兜底，但显式清理是双保险：

```bash
rm -rf .specs/ .reviews/ 2>/dev/null || true
```

清理对象：

- `.specs/` — `/spec-before-code` 流程产生的需求 spec 文档（`.specs/<slug>.md` / `.skip`）
- `.reviews/` — `/review` 流程产生的 review 报告 + executor 阶段的 UI 截图目录（`.reviews/ui-<slug>-<ts>/`）

如果用户在 `/openpr` 前明确说"留着 review 报告 / UI 截图，我要看一下"，跳过这一步——但注意提醒用户后续自己删，否则下次 `/openpr` 会被自动清掉。

## push 与开 PR

- `git push -u origin HEAD --force-with-lease`
  - 用 `--force-with-lease` 是因为上一节 rebase 可能重写了 commit hash；首次 push 时该参数等价普通 push（无害）
  - **不要**用 `--force`——会覆盖别人可能在同一远程分支上推过的改动
- 按项目 PR 风格开 PR：
  - `gh pr create --base dev --title "<type(scope): desc>" --body "$(cat <<'EOF' ... EOF)"`
  - body 列改动摘要、测试计划、若有 UI 变更附截图说明
- 保存 PR URL

## 交付

返给用户：
- PR URL
- 提示可用 `/pr-review` 让 reviewer subagent 评 PR

## 不做的事

- ❌ 不跑 deep code review（那是 `/review`）
- ❌ 不跑 PR review（那是 `/pr-review`）
- ❌ 不做 UI 还原度验证
- ❌ 不自动合并 PR
