---
name: use-worktree
description: 新话题切换时进 git worktree 物理隔离，让每个需求独立从干净的 origin/dev 起步、互不干扰。触发：用户切到新话题（"新任务 / 另一个 / 接下来做 X / 开始搞 Y / 下一个需求 / 现在改 Z"等切话题信号）且本轮要写代码（会落地 Edit / Write / NotebookEdit），在第一次 Edit 前建 worktree。SOP：git fetch origin dev → 决定分支名 `<type>/<scope>-<slug>` → `git worktree add .worktrees/<slug> -b <branch> origin/dev` → `EnterWorktree(path=.worktrees/<slug>)` → 复制 gitignored 本地配置（Local.xcconfig / .env.local / 凭证）→ 跑项目初始化（生成 xcodeproj / npm install / build）→ cp 锁文件（Package.resolved / yarn.lock）。IDE 默认不自动打开，等用户/agent 明确要进 Xcode 时再 open。**不要**用 `EnterWorktree(name=...)`——会从当前 HEAD 起步、继承前一需求的 WIP。不触发：延续当前任务（修 bug / 调样式 / 基于同一需求追加 / 来回迭代）/ 纯问答 / 读代码 / 查状态 / 改 meta 配置（rule / memory / hook / settings）/ 当前已经在 .worktrees/ 里。拿不准是不是切话题时先问用户、别自作主张建 worktree。
---

# 新话题进 git worktree 隔离

用户**明显切到新话题**时，在开始写代码前进 worktree 隔离，每个需求物理独立、不互相干扰。

## 触发信号

"新任务 / 另一个 / 接下来做 X / 开始搞 Y / 下一个需求 / 现在改 Z" 这类**切话题信号**时触发。

**不触发**的场景：

- 延续当前任务（修 bug / 调样式 / 基于同一需求追加 / 来回迭代）
- 纯问答 / 读代码 / 查状态
- 改配置 / 改 rule / 改 memory
- 当前已经在 worktree 里（路径含 `.worktrees/`）—— 继续用当前 worktree

拿不准是不是切话题时，**问用户一句**再决定，别自作主张建 worktree。

## 建 worktree 流程（必须基于最新 origin/dev）

**不要**直接 `EnterWorktree(name=...)`—— 那会从当前 HEAD 起步，可能继承前一个需求的 WIP。

正确流程（标记 `<project-specific>` 的步骤要按你的项目改）：

1. `git fetch origin dev` —— 拉最新 dev
2. 决定分支名 `<type>/<scope>-<slug>`，`type ∈ {feat, fix, chore, refactor, docs, test, perf, style}`
3. `git worktree add .worktrees/<slug> -b <type>/<scope>-<slug> origin/dev` —— 指定 base 为 `origin/dev`，和当前分支 HEAD 解耦
4. `EnterWorktree(path=.worktrees/<slug>)` —— 进入已创建的 worktree（cwd 切到该 worktree 目录）
5. **`<project-specific>` 从主仓库 cp gitignored 的本地配置文件**（如 `Local.xcconfig` / `.env.local` / 凭证文件等，新 worktree 没有这些）：
   ```bash
   MAIN_REPO="${PWD%/.worktrees/*}"
   # 例：cp "$MAIN_REPO/<your-local-config>" ./<your-local-config>
   ```
6. **`<project-specific>` symlink 共享 SPM binary artifact**（iOS+macOS 双平台 monorepo 适用、单平台项目跳过）：worktree 用 `just build-ios` 等 `-project` 模式 build 时只下 iOS-only artifact，Xcode 打开 workspace 会缺 macOS-only artifact（Sparkle / CLibOpus 等）。symlink artifacts/ 到主仓库一次性根治，artifact 是 SHA256 hash 寻址的近 read-only cache、多 worktree 共享不打架：
   ```bash
   MAIN_REPO="${PWD%/.worktrees/*}"
   if [[ -d "$MAIN_REPO/build/DerivedData/SourcePackages/artifacts" ]]; then
     mkdir -p build/DerivedData/SourcePackages
     ln -sfn "$MAIN_REPO/build/DerivedData/SourcePackages/artifacts" build/DerivedData/SourcePackages/artifacts
   else
     echo "WARN: main repo artifacts/ missing; run 'just build-macos' in main first, then re-symlink"
   fi
   ```
   主仓库 artifacts/ 不存在时跳过 + 提示用户先在主仓库跑 `just build-macos`。只 symlink `artifacts/`、不 symlink `checkouts/`/`repositories/`/`workspace-state.json`（这三个 worktree 自己写、共享会冲突）。 即使本 step 因为 agent 忘了或工具异常被跳过，`~/.Codex/scripts/worktree-spm-symlink-fix.sh` SessionStart hook 会在下次 session 在 `.worktrees/<slug>/` 里启动时自动 ln -sfn 修一次（artifacts/ 不是指向主仓库的 symlink 就重建）—— hook 是兜底、本 step 仍是正路、不要因为有 hook 就主动跳。
7. **`<project-specific>` 跑项目的初始化命令**（例如生成 xcodeproj / 安装 npm 依赖 / build 一次）。如果该产物在 `.gitignore`，每个 worktree 都要跑一次
8. **`<project-specific>` cp 锁文件 / 已解析依赖**：如果项目里它在 `.gitignore` 但是新 worktree 解析依赖时需要它，必须 cp。**不是可选 step**——新 worktree 没 lock 时 SPM / npm 等会从零 resolve，碰上版本飘移直接整图失败（症状：Xcode 报「Missing package product '<SomeProduct>' / '<AnotherProduct>' 等一长串」）。

   `<project-specific>` 例子（每个项目按自己 .gitignore 排除的 lock 列出具体路径）：
   ```bash
   MAIN_REPO="${PWD%/.worktrees/*}"
   # 某 iOS monorepo 项目（Package.resolved 被 .gitignore 排除）：
   if [[ -f "$MAIN_REPO/<YourApp>.xcworkspace/xcshareddata/swiftpm/Package.resolved" ]]; then
     mkdir -p <YourApp>.xcworkspace/xcshareddata/swiftpm
     cp "$MAIN_REPO/<YourApp>.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
        <YourApp>.xcworkspace/xcshareddata/swiftpm/Package.resolved
   fi
   # 其他项目按需补：yarn.lock / pnpm-lock.yaml / Cargo.lock / poetry.lock ...
   ```

   时机：必须在 step 7 跑 build / install 命令**之前**完成。build 命令拿不到 lock 时会自己 fresh resolve，写一份不一致的 lock 进去、把问题固化。
9. **`<project-specific>` 按需打开 IDE / workspace（默认跳过）**：use-worktree 阶段**不**自动 open Xcode / IDE。命令行 build（如 `just build-ios`）已能验编译。用户/agent 后续明确说「在 Xcode 里调 / 看 UI / 开 IDE」时再 open。step 6 的 symlink 已让 Xcode 打开 workspace 时 macOS artifact 就位；symlink 没建上撞 binary target error 时见 `Skill(worktree-spm-bootstrap)` fallback。

若 step 6 (symlink) 主仓库 artifacts/ 缺：跳过、提示用户、不阻塞后续 step。
若 step 7 (初始化命令) 失败：报告失败原因、**不要**强行进 step 8，等用户决定。常见 fail：忘了 step 5 的本地配置。

若用户事前说"不跑 build / 不解析依赖"：跳过 7、8。但 step 5 的本地配置 + step 6 的 symlink 还是要做（命令行工具依赖配置 / Xcode 打开依赖 symlink）。

## `<project-specific>` 命令行 build 的注意点

新 worktree 第一次跑工程级 build 时（如 `xcodebuild -workspace`、`turbo build`）可能会重新解析依赖。锁文件 / `<your-resolved-deps-file>` 没 cp 到位时会失败 —— 看错误信息确认是依赖解析问题再补上。

可能的兜底：build 单个子项目而不是 workspace 级别，绕开 workspace 里其他平台 / target 的包污染（例：iOS workspace 含 macOS-only binary target 时）。

## 生命周期

- 走 `/openpr` push + 开 PR 之后：可以 `ExitWorktree(action="keep")` 保留，等后续 PR 改动回来继续用；或让 session 退出时由 harness 提示清理
- 若 worktree 做到一半发现不需要、无改动：`ExitWorktree(action="remove")` 干净退出
- 有未提交改动又想删：需要 `ExitWorktree(action="remove", discard_changes=true)`，**先跟用户确认**

## Why

过去所有需求叠在同一分支 / 同一工作区，新需求和旧 WIP 互相污染；开 PR 容易带入不相关改动。worktree 让每个需求物理隔离、各自从干净的 dev 起步、互不干扰。

SPM artifact symlink（step 6）有三道兜底：(1) 本 skill step 6 创建 worktree 时跑；(2) `~/.Codex/scripts/worktree-spm-symlink-fix.sh` SessionStart hook 每次 session 启动自动检测+修复；(3) `Skill(worktree-spm-bootstrap)` 兜底 fallback。多道防线是因为单靠 agent 凭记忆跑 step 6 实测会漏。
