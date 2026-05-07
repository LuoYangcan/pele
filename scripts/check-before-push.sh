#!/usr/bin/env bash
#
# PreToolUse Bash hook helper: gate `git push` / `gh pr create` behind a
# project-defined check command (e.g. `just check`, `npm run lint`,
# `make lint`). Designed to be invoked from a project-level hook in
# `<repo>/.claude/settings.local.json`.
#
# Why this script exists:
#   The naive approach — putting the check command directly in a hook —
#   fires for ANY `git push` you run during the session, even if you `cd`
#   into a different repository to push something there. This script
#   resolves the **target repo of the push** (by parsing `cd <dir>` from
#   the command, or falling back to $PWD) and only runs the check when
#   the target is **this** repo (or one of its worktrees). Pushes to other
#   repos pass through silently.
#
# Usage (from <repo>/.claude/settings.local.json):
#
#   {
#     "hooks": {
#       "PreToolUse": [{
#         "matcher": "Bash",
#         "hooks": [{
#           "type": "command",
#           "command": "bash $HOME/.claude/scripts/check-before-push.sh \"just check\"",
#           "timeout": 240,
#           "statusMessage": "Running pre-push lint..."
#         }]
#       }]
#     }
#   }
#
# Replace `just check` with whatever your project's lint/check recipe is.
# If no command is passed, the hook silently exits 0 (no gate).
#
# Exit codes:
#   0 — pass (either skipped because target wasn't this repo, or check passed)
#   2 — check failed (push blocked); stderr contains the failure message + tail of log

set -u

# ----------------------- args -----------------------
# $1: the gate command to run (e.g. "just check", "npm run lint")
GATE_CMD="${1:-}"
[[ -z "$GATE_CMD" ]] && exit 0

# ----------------------- read hook payload -----------------------
payload="$(cat || true)"
cmd=""
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
fi

# Only care about push / PR-creating commands
case "$cmd" in
  *"git push"*|*"gh pr create"*) ;;
  *) exit 0 ;;
esac

# ----------------------- resolve target repo of the push -----------------------
# Try to extract `cd <dir>` from the command (handles unquoted, "double-quoted",
# and 'single-quoted' forms). If no cd, the target is $PWD.
target_dir=$(echo "$cmd" | sed -nE 's/(^|[[:space:]&;|]+)cd[[:space:]]+("([^"]+)"|'\''([^'\'']+)'\''|([^[:space:]&;|]+)).*/\3\4\5/p' | head -1)
[[ -z "$target_dir" ]] && target_dir="$PWD"
[[ "$target_dir" != /* ]] && target_dir="$PWD/$target_dir"

# Canonicalise (resolve symlinks, strip trailing slashes)
target_real=$(cd "$target_dir" 2>/dev/null && pwd -P || true)
[[ -z "$target_real" ]] && exit 0   # Couldn't resolve → don't gate

# ----------------------- resolve "this repo" (the session's main repo) -----------------------
# Use the hook's $PWD (Claude Code session cwd) to find the git common dir,
# then derive the main repo root. Worktrees share a common dir with their
# main repo, so worktree pushes still gate correctly.
common_dir=$(git -C "$PWD" rev-parse --git-common-dir 2>/dev/null || true)
[[ -z "$common_dir" ]] && exit 0   # $PWD not in any git repo → don't gate
[[ "$common_dir" != /* ]] && common_dir="$PWD/$common_dir"
session_repo=$(cd "$(dirname "$common_dir")" 2>/dev/null && pwd -P || true)
[[ -z "$session_repo" ]] && exit 0

# Only gate when the push target is inside the session's repo.
# Prefix match covers the main worktree AND any `.worktrees/<slug>` checkouts.
case "$target_real" in
  "$session_repo"|"$session_repo"/*) ;;
  *) exit 0 ;;
esac

# ----------------------- run the gate command -----------------------
log_file="${TMPDIR:-/tmp}/claude-check-$$.log"
if ! bash -c "$GATE_CMD" >"$log_file" 2>&1; then
  echo "${GATE_CMD} failed — fix issues before pushing" >&2
  tail -40 "$log_file" >&2
  rm -f "$log_file"
  exit 2
fi
rm -f "$log_file"
