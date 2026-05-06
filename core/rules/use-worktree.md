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
6. **`<project-specific>` 跑项目的初始化命令**（例如生成 xcodeproj / 安装 npm 依赖 / build 一次）。如果该产物在 `.gitignore`，每个 worktree 都要跑一次
7. **`<project-specific>` cp 锁文件 / 已解析依赖**（如 `Package.resolved`、`yarn.lock`、`Cargo.lock`），如果项目里它在 `.gitignore` 但是新 worktree 解析依赖时需要它
8. **`<project-specific>` 打开 IDE / workspace**：在 worktree cwd 下打开**当前 worktree 自己的** workspace（不是主仓库的）

若 step 6 失败：报告失败原因、**不要**强行进 step 7-8，等用户决定。常见 fail：忘了 step 5 的本地配置。

若用户事前说"不开 IDE"：跳过 6、7、8。但 step 5 的本地配置还是要 cp（命令行工具也依赖它）。

## `<project-specific>` 命令行 build 的注意点

新 worktree 第一次跑工程级 build 时（如 `xcodebuild -workspace`、`turbo build`）可能会重新解析依赖。锁文件 / `<your-resolved-deps-file>` 没 cp 到位时会失败 —— 看错误信息确认是依赖解析问题再补上。

可能的兜底：build 单个子项目而不是 workspace 级别，绕开 workspace 里其他平台 / target 的包污染（例：iOS workspace 含 macOS-only binary target 时）。

## 生命周期

- 走 `/openpr` push + 开 PR 之后：可以 `ExitWorktree(action="keep")` 保留，等后续 PR 改动回来继续用；或让 session 退出时由 harness 提示清理
- 若 worktree 做到一半发现不需要、无改动：`ExitWorktree(action="remove")` 干净退出
- 有未提交改动又想删：需要 `ExitWorktree(action="remove", discard_changes=true)`，**先跟用户确认**

## Why

过去所有需求叠在同一分支 / 同一工作区，新需求和旧 WIP 互相污染；开 PR 容易带入不相关改动。worktree 让每个需求物理隔离、各自从干净的 dev 起步、互不干扰。
