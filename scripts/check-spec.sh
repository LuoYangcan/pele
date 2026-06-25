#!/usr/bin/env bash
# PreToolUse hook: 在 worktree 内 Edit/Write/NotebookEdit 前，强制要求存在 spec 文件
# 规则文件：~/.claude/rules/spec-before-code.md
# 触发：cwd 在 .worktrees/<slug>/ 下；放行条件：.specs/<slug>.md 或 .specs/<slug>.skip 存在
set -u

# 读 hook payload（JSON）
payload="$(cat || true)"

# 取 cwd：优先用 payload.cwd，取不到 fallback 到 PWD
cwd=""
if command -v jq >/dev/null 2>&1; then
  cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
[[ -z "$cwd" ]] && cwd="$PWD"

# 不在 worktree 里 → 放行（改主仓库 / 改全局配置 / 改 rule 等场景不强制）
if [[ "$cwd" != *"/.worktrees/"* ]]; then
  exit 0
fi

# 找 worktree 根 + slug。
# 优先用 git 的真实 worktree 根（`git rev-parse --show-toplevel`）—— 这样对**嵌套** worktree
# （形如 .../.worktrees/<group>/<cell>，例如 bench 的 .worktrees/bench/<cell-rid>）也能正确取到
# 实际 worktree 根，而不是错误地把第一段 <group> 当 slug。
# 兜底：拿不到 git toplevel（非 git 目录等）时，退回旧的「.worktrees/ 后第一段」字符串解析。
wroot=""
if command -v git >/dev/null 2>&1; then
  top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  # 只有当 git 根确实落在某个 .worktrees/ 下时才采用它（避免主仓库根被当成 worktree）
  if [[ -n "$top" && "$top" == *"/.worktrees/"* ]]; then
    wroot="$top"
  fi
fi
if [[ -z "$wroot" ]]; then
  # fallback：旧逻辑，取 .worktrees/ 后第一段（对扁平 worktree 仍正确）
  rest="${cwd#*/.worktrees/}"
  first="${rest%%/*}"
  [[ -z "$first" ]] && exit 0
  wroot="${cwd%%/.worktrees/*}/.worktrees/$first"
fi

slug="$(basename "$wroot")"
[[ -z "$slug" ]] && exit 0

spec_md="$wroot/.specs/$slug.md"
spec_skip="$wroot/.specs/$slug.skip"

# 豁免: 如果本次 Edit/Write 的目标就是 spec 或 skip 文件本身 → 放行
# 这是 planner 第一次创建 spec 的场景，hook 不应该卡 planner 自己产物
if command -v jq >/dev/null 2>&1; then
  target_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
  if [[ -n "$target_path" ]]; then
    # 相对路径前缀加 cwd 规范化
    if [[ "$target_path" != /* ]]; then
      target_path="$cwd/$target_path"
    fi
    if [[ "$target_path" == "$spec_md" || "$target_path" == "$spec_skip" ]]; then
      exit 0
    fi
  fi
fi

# 子文件豁免：目标在 .specs/<slug>/{tasks,risks,amendments}/ 子目录里 → 放行
# planner / generator 写 task-N.md / risk-N.md / AMD-N.md 子文件时主索引可能还未持久化（极少数反序情况兜底）
spec_subdir="$wroot/.specs/$slug/"
if command -v jq >/dev/null 2>&1; then
  if [[ -n "$target_path" && "$target_path" == "$spec_subdir"* ]]; then
    exit 0
  fi
fi

# spec 主索引 或 skip 任一存在 → 放行
if [[ -f "$spec_md" || -f "$spec_skip" ]]; then
  exit 0
fi

# Deny + 引导 Claude 怎么生成 spec / 怎么 bypass
reason="当前 worktree \\\"$slug\\\" 还没有 spec 文件，按 ~/.claude/rules/spec-before-code.md 必须先写 spec 才能 Edit/Write。\\n\\n请按下列顺序处理：\\n1) 用 AskUserQuestion 向用户澄清需求目标 / 硬约束 / 存疑点（如果还没充分澄清）\\n2) 用 Write 工具按 ~/.claude/templates/spec-template.md 模板生成 spec 到：$spec_md\\n3) 然后再继续 Edit/Write\\n\\n如果是 1-2 行小修 / 改样式 / 用户明确说不需要 spec，可以用 Bash 跑：touch $spec_skip 来跳过本规则（.skip 文件可为空）。"

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$reason"
exit 0
