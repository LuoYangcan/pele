---
description: 退出前清理当前 worktree（/exit 默认不会问；用这个先清理再 /exit）
---

退出 Claude Code 之前清理当前 worktree。`/exit` `/quit` 默认**不会**问你是否要删 worktree —— 因为 `use-worktree.md` 用 `EnterWorktree(path=...)` 进 worktree、不被 session 跟踪。本命令补上交互式清理。

## 你（Claude）要做的

### Step 1: 看当前位置 + 状态

跑：

```bash
pwd
git rev-parse --abbrev-ref HEAD 2>/dev/null
git status --short 2>/dev/null | wc -l        # 未提交改动行数
git worktree list 2>/dev/null
git log --oneline @{u}..HEAD 2>/dev/null      # 未推送 commit
gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --json number,state,url 2>/dev/null || true
```

判断：

- cwd 是不是在 `.worktrees/<slug>/` 下（含 `.subworktrees/<group>/` 嵌套层级）
- 当前分支名、主仓库根（`git worktree list` 第一行）
- 有没有未提交改动 / 未推送 commit
- 当前分支 PR 状态（OPEN / MERGED / 未开）

### Step 2: 不在 worktree

cwd 不在 `.worktrees/` 下 → 告诉用户：「你现在不在 worktree 里（cwd: `<pwd>`），没需要清理的。直接 /exit 或 /quit 退出 Claude Code 即可。」**结束**，不继续后面 Step。

### Step 3: 在 worktree 里 — 摘要 + AskUserQuestion 让用户选

先 echo 一行状态摘要给用户：

```
worktree: .worktrees/<slug>/
分支: <branch>
未提交改动: <N> 个文件
未推送 commit: <M> 个
PR: <未开 | #123 OPEN | #123 MERGED>
```

然后用 `AskUserQuestion` 问，4 个选项：

1. **删 worktree + 删本地 branch**（推荐用于 PR merged / 工作完结）
   - 触发条件：无未提交改动 + 无未推送 commit。如果有 → **不让用户选这个**（在 question 里把这条标灰或直接说「当前条件不允许：你有未推送的工作，先 commit + push 再来」）
2. **删 worktree 保留 branch**（PR 还在 review、不要工作目录但留分支）
3. **保留 worktree + branch**（之后还回来继续）
4. **取消，我不退出了**（什么都不动、继续 session）

### Step 4: 按选择执行

主仓库根路径用 `git worktree list` 第一行第一列。

#### 选项 1: 删 worktree + 删 branch

```bash
cd <主仓库绝对路径>          # 不能在 worktree 内删自己
git worktree remove .worktrees/<slug>
git branch -D <branch>       # -D 强删，分支可能没被 merge 但 PR 已 merge 不影响
```

然后调 `ExitWorktree(action="remove")` 让 session 同步把 cwd 切回主仓库。如果 ExitWorktree 报错说「这是 path= 进入的 worktree、不删」，没关系 —— 上面的 git 命令已经删过了，这一步只是切 cwd。

#### 选项 2: 删 worktree 保留 branch

```bash
cd <主仓库绝对路径>
git worktree remove .worktrees/<slug>
```

然后 `ExitWorktree(action="keep")` 把 cwd 切回主仓库。

#### 选项 3: 保留全部

什么都不动，但仍然 `ExitWorktree(action="keep")` 把 cwd 切回主仓库（这样下次 /exit 时不在 worktree 里、避免重复弹本命令）。

#### 选项 4: 取消

什么都不动，结束。**不**调 ExitWorktree。

### Step 5: 收尾

- 选项 1/2/3：「OK，cwd 现在是 `<主仓库>`。可以 /exit 或 /quit 退出 Claude Code 了。」
- 选项 4：「不动。你继续工作；下次想退出再调 `/cleanup-and-exit`。」

## sub-worktree 处理（dispatch-pipeline 并行模式产物）

cwd 在 `.worktrees/<slug>/.subworktrees/<group>/` 嵌套层级时：

1. 先 `ExitWorktree(action="keep")` 退到上层 `.worktrees/<slug>/`
2. 跑 `git worktree list | grep .subworktrees/` 看主 worktree 还有没有遗留 sub-worktree
3. 有遗留 → 提示用户「⚠️ 还有 N 个 sub-worktree 未清理（dispatch-pipeline 并行模式中途退出过？阶段 3C 没跑完）。是否一并清理？」用 AskUserQuestion 让用户拍板：
   - 全部 `git worktree remove .subworktrees/<group>` + `git branch -D <type/scope-slug>--<group>` —— 适合并行任务确实终止
   - 保留，等之后再说
4. 处理完 sub-worktree 后回到 Step 3 走主 worktree 的清理流程

## 禁止 / 注意

- ❌ 不要在 worktree 内 `git worktree remove` 自己 —— 必须先 `cd` 到主仓库
- ❌ 不要用 `git worktree remove --force` 跳过未提交检查 —— 选项 1 应当 refuse 让用户先 commit + push
- ❌ 不要自动 `git push` —— 那是 `/ship` / `/openpr` 的事
- ❌ 不要替用户输入 `/exit` —— slash command 没法让 Claude Code 自己退；最后让用户手动输
- ✅ 选项 4（取消）后正常继续 session，不影响后续工作

## Why

`use-worktree.md` 的「基于最新 origin/dev」硬约束要求用 `git worktree add ... origin/dev` + `EnterWorktree(path=...)` 模式，但 `path=` 进入的 worktree 不被 Claude Code session 视为「session 拥有」—— 所以 session 退出时 Claude Code 内置的 keep/remove prompt **不会出现**。`SessionEnd` hook 又是 fire-and-forget 不能交互。本命令补上这条交互式路径，依赖你**主动**在退出前调用。
