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

# 提取 slug：cwd 形如 .../.worktrees/<slug> 或 .../.worktrees/<slug>/...
# 取 .worktrees/ 后面、第一个 / 之前的部分
rest="${cwd#*/.worktrees/}"
slug="${rest%%/*}"
if [[ -z "$slug" ]]; then
  exit 0
fi

# 找 worktree 根
wroot="${cwd%%/.worktrees/*}/.worktrees/$slug"
spec_md="$wroot/.specs/$slug.md"
spec_skip="$wroot/.specs/$slug.skip"

# spec 或 skip 任一存在 → 放行
if [[ -f "$spec_md" || -f "$spec_skip" ]]; then
  exit 0
fi

# Deny + 引导 Claude 怎么生成 spec / 怎么 bypass
reason="当前 worktree \\\"$slug\\\" 还没有 spec 文件，按 ~/.claude/rules/spec-before-code.md 必须先写 spec 才能 Edit/Write。\\n\\n请按下列顺序处理：\\n1) 用 AskUserQuestion 向用户澄清需求目标 / 硬约束 / 存疑点（如果还没充分澄清）\\n2) 用 Write 工具按 ~/.claude/templates/spec-template.md 模板生成 spec 到：$spec_md\\n3) 然后再继续 Edit/Write\\n\\n如果是 1-2 行小修 / 改样式 / 用户明确说不需要 spec，可以用 Bash 跑：touch $spec_skip 来跳过本规则（.skip 文件可为空）。"

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$reason"
exit 0
