---
name: use-worktree
description: 代码改动一律用独立 git worktree 隔离，主仓 checkout 只做只读操作。触发：任何要落地 Edit/Write 的编码任务且当前不在 .worktrees/。不触发：已在 worktree 内延续当前任务、纯问答、读代码、查状态；meta 配置不自动加载本 skill，但仍服从 AGENTS 的 protected-branch 路由。
---

# 代码改动一律使用独立 worktree

在第一次源码写入前创建 worktree。不要从当前可能含 WIP 的 HEAD 隐式派生，不在主仓 checkout 直接改代码。

## 入口判断

- 任何要落地 Edit/Write 的编码任务（新需求、bugfix、重构、补测试等）：触发，无论是否切换话题。
- 当前路径已含 `.worktrees/`：不新建，继续使用当前 worktree。
- 修改 rule、skill、hook、settings 等 agent harness：不自动触发本 skill；若 repo-backed meta 位于 main/master/dev，仍须按 AGENTS 先切任务分支或选择 worktree。
- 项目规则禁止创建分支且未给 worktree 例外时：先问用户，不静默回退到主仓直改。
- 主仓存在用户未提交改动或停在非基线分支时：先与用户确认再创建；只读确认这些改动，不移动或回滚。

## 复用

创建前先 `git worktree list`。`.worktrees/` 下已有 worktree 满足「工作区干净且其分支已合并进基线（`git merge-base --is-ancestor <branch> origin/<基线>`）」时，可在其中 `git fetch` 后从 `origin/<基线>` 直接 `git switch -c <新分支>` 复用（连同依赖解析与构建缓存）；旧分支留在原处，是否删除交用户。分支未合并或有未提交改动的 worktree 不得自动复用，须经用户明确授权。

## 创建与初始化

1. 读项目 `AGENTS.md` 确认默认基线分支；未指定时使用项目约定，不能假定所有仓库都是 `dev`。
2. 一键 bootstrap（fetch、worktree add、复制 gitignored 配置、SPM artifacts symlink、目录信任、可选项目初始化）：

   ```bash
   ~/.claude/scripts/worktree-bootstrap.sh <slug> --base <基线分支> \
     [--type feat] [--copy <相对路径>]... [--init "<命令>"]
   ```

   脚本默认复制主仓存在的 `.claude/settings.local.json`；SPM 只 symlink `build/DerivedData/SourcePackages/artifacts`，不共享 `checkouts`、`repositories` 或 `workspace-state.json`；复制的文件内容不在输出中暴露。`--init` 只运行让仓库可编辑所必需的初始化（codegen、依赖安装、项目生成）。脚本不可用时手动执行同等步骤（`git fetch` + `git worktree add .worktrees/<slug> -b <type>/<slug> origin/<基线>` + `trust-dir.sh "$PWD"`）。
3. 分支类型通常为 `feat | fix | refactor | chore | docs | test | perf | style`；遵守项目或 host 的分支命名约定。

初始化阶段不做 baseline build、不预热 Simulator、不自动打开 IDE；最终候选统一按 `rules/post-change-verify.md` 验证。初始化失败时先区分本地配置、依赖和环境问题，不把环境失败当成源码失败；用户明确要求不解析依赖时跳过相关初始化。

## 生命周期

- PR 或后续迭代仍需该分支：保留 worktree。
- 无改动且任务取消：可移除 worktree。
- 有未提交改动时，未经用户明确授权不得丢弃或强制移除。
