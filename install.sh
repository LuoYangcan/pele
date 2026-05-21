#!/usr/bin/env bash
# Pele installer — symlinks core/ into a .claude/ directory (global or per-project).
#
# Usage:
#   ./install.sh                          # global mode (default): install into ~/.claude/
#   ./install.sh --global                 # explicit global mode (same as default)
#   ./install.sh --project <path>         # project mode: install into <path>/.claude/
#   ./install.sh --figma                  # also install figma-extras hooks (global mode only)
#   ./install.sh --dry-run                # show what would be done, do not change anything
#   ./install.sh --force                  # skip confirmation prompts (still backs up)
#
# Modes (--global and --project are mutually exclusive):
#   global  — symlink core/{rules,agents,skills,commands,templates}/* into ~/.claude/,
#             merge hooks into ~/.claude/settings.json, install CLAUDE.md.
#   project — symlink the same dirs into <path>/.claude/.
#             Does NOT touch <path>/CLAUDE.md or <path>/AGENTS.md.
#             Does NOT merge hooks (hooks live in ~/.claude/settings.json globally).
#             Prints manual instruction to add `@.claude/rules/index.md` to <path>/CLAUDE.md.
#
# Idempotent: re-running updates symlinks; existing files are backed up to ~/.claude.backup-<timestamp>/

set -euo pipefail

# -------------------------- args --------------------------
WITH_FIGMA=0
DRY_RUN=0
FORCE=0
MODE=""              # "" | "global" | "project"
PROJECT_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --global)
      if [ "$MODE" = "project" ]; then
        echo "Error: --global and --project are mutually exclusive." >&2
        exit 2
      fi
      MODE="global"
      shift
      ;;
    --project)
      if [ "$MODE" = "global" ]; then
        echo "Error: --global and --project are mutually exclusive." >&2
        exit 2
      fi
      MODE="project"
      shift
      if [ $# -eq 0 ] || [ -z "${1:-}" ] || [ "${1#--}" != "$1" ]; then
        echo "Error: --project requires a path argument." >&2
        exit 2
      fi
      PROJECT_PATH="$1"
      shift
      ;;
    --figma)
      WITH_FIGMA=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

# Default mode is global
[ -z "$MODE" ] && MODE="global"

# In project mode, --figma is incompatible (hooks are global-only)
if [ "$MODE" = "project" ] && [ "$WITH_FIGMA" = 1 ]; then
  echo "Error: --figma is only valid in global mode (hooks live in ~/.claude/settings.json)." >&2
  exit 2
fi

# ----------------------- paths -----------------------
PELE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ "$MODE" = "project" ]; then
  # Resolve project path to absolute (without requiring it to already exist beyond parent)
  if [ ! -d "$PROJECT_PATH" ]; then
    mkdir -p "$PROJECT_PATH" 2>/dev/null || true
  fi
  if [ ! -d "$PROJECT_PATH" ]; then
    echo "Error: project path '$PROJECT_PATH' does not exist and could not be created." >&2
    exit 2
  fi
  PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd -P)"
  CLAUDE_DIR="${PROJECT_PATH}/.claude"
else
  CLAUDE_DIR="${HOME}/.claude"
fi
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${CLAUDE_DIR}.backup-${TS}"

# ANSI helpers (degrade gracefully without TTY)
if [ -t 1 ]; then
  C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'
else
  C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_RESET=""
fi
log()  { echo "${C_DIM}[pele]${C_RESET} $*"; }
ok()   { echo "${C_GREEN}[pele] ✓${C_RESET} $*"; }
warn() { echo "${C_YELLOW}[pele] !${C_RESET} $*"; }
err()  { echo "${C_RED}[pele] ✗${C_RESET} $*" >&2; }

# ----------------------- preflight -----------------------
log "Pele root: ${PELE_ROOT}"
log "Mode:      ${MODE}$([ "$MODE" = "project" ] && echo " (${PROJECT_PATH})")"
log "Target:    ${CLAUDE_DIR}"
log "Figma extras: $([ "$WITH_FIGMA" = 1 ] && echo "yes" || echo "no")"
log "Dry run:   $([ "$DRY_RUN" = 1 ] && echo "yes" || echo "no")"
echo ""

if [ ! -d "${PELE_ROOT}/core" ]; then
  err "core/ not found at ${PELE_ROOT}/core. Run from the pele repo root."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found — hooks merge will fall back to manual instructions."
  warn "  Install: brew install jq   (macOS)"
fi

mkdir -p "${CLAUDE_DIR}"

# ----------------------- helpers -----------------------
backup_if_exists() {
  # backup_if_exists <path>
  # If <path> exists and is not already a symlink into PELE_ROOT, move it under BACKUP_DIR preserving relative structure.
  local p="$1"
  if [ -e "$p" ] || [ -L "$p" ]; then
    if [ -L "$p" ]; then
      local target
      target="$(readlink "$p")"
      case "$target" in
        "${PELE_ROOT}"*) return 0 ;;  # already pointing into pele
      esac
    fi
    # Compute relative path under CLAUDE_DIR (handles both global ~/.claude and project <path>/.claude)
    local rel="${p#${CLAUDE_DIR}/}"
    local dest="${BACKUP_DIR}/${rel}"
    mkdir -p "$(dirname "$dest")"
    if [ "$DRY_RUN" = 1 ]; then
      log "  would backup: $p → $dest"
    else
      mv "$p" "$dest"
      log "  backup: $p → $dest"
    fi
  fi
}

link_file() {
  # link_file <src> <dst>
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    log "  ✓ already linked: $dst"
    return 0
  fi
  backup_if_exists "$dst"
  mkdir -p "$(dirname "$dst")"
  if [ "$DRY_RUN" = 1 ]; then
    log "  would link: $dst → $src"
  else
    ln -s "$src" "$dst"
    log "  link: $dst → $src"
  fi
}

# Mirror a directory of single-level files (e.g. rules/, agents/, commands/)
link_dir_flat() {
  # link_dir_flat <src_dir> <dst_dir>
  local src="$1" dst="$2"
  mkdir -p "$dst"
  local f base
  for f in "$src"/*; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    link_file "$f" "${dst}/${base}"
  done
}

# Mirror a directory containing nested dirs (e.g. skills/<name>/)
link_dir_recursive_top() {
  # Symlink each TOP-LEVEL entry in src (file or dir) into dst.
  # Top-level dirs are linked as a whole (one symlink), so updates inside the source repo are visible immediately.
  local src="$1" dst="$2"
  mkdir -p "$dst"
  local entry base
  for entry in "$src"/*; do
    [ -e "$entry" ] || continue
    base="$(basename "$entry")"
    link_file "$entry" "${dst}/${base}"
  done
}

# ----------------------- confirm -----------------------
if [ "$FORCE" != 1 ] && [ "$DRY_RUN" != 1 ]; then
  echo "${C_BOLD}This will:${C_RESET}"
  echo "  • symlink ${PELE_ROOT}/core/{rules,agents,skills,commands,templates}/* into ${CLAUDE_DIR}/*"
  if [ "$MODE" = "global" ]; then
    echo "  • symlink ${PELE_ROOT}/core/CLAUDE.md to ${CLAUDE_DIR}/CLAUDE.md"
    [ "$WITH_FIGMA" = 1 ] && echo "  • merge ${PELE_ROOT}/figma-extras/hooks/settings.hooks.json into settings.json"
    echo "  • merge core hooks into ${CLAUDE_DIR}/settings.json (backup taken)"
  else
    echo "  • leave ${PROJECT_PATH}/CLAUDE.md and ${PROJECT_PATH}/AGENTS.md untouched"
    echo "  • print manual instruction to add '@.claude/rules/index.md' after install"
  fi
  echo "  • back up any conflicting files to ${BACKUP_DIR}/"
  echo ""
  printf "Continue? [y/N] "
  read -r REPLY < /dev/tty || REPLY="n"
  case "$REPLY" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

# ----------------------- core: top-level CLAUDE.md (global only) -----------------------
if [ "$MODE" = "global" ]; then
  log "Installing CLAUDE.md..."
  link_file "${PELE_ROOT}/core/CLAUDE.md" "${CLAUDE_DIR}/CLAUDE.md"
fi

# ----------------------- core: rules / agents / commands / templates -----------------------
log "Installing rules/..."
link_dir_flat "${PELE_ROOT}/core/rules" "${CLAUDE_DIR}/rules"

log "Installing agents/..."
link_dir_flat "${PELE_ROOT}/core/agents" "${CLAUDE_DIR}/agents"

log "Installing commands/..."
link_dir_flat "${PELE_ROOT}/core/commands" "${CLAUDE_DIR}/commands"

log "Installing templates/..."
link_dir_flat "${PELE_ROOT}/core/templates" "${CLAUDE_DIR}/templates"

# ----------------------- core: skills (nested) -----------------------
log "Installing skills/..."
link_dir_recursive_top "${PELE_ROOT}/core/skills" "${CLAUDE_DIR}/skills"

# ----------------------- core: scripts (helpers used by hooks; global only) -----------------------
if [ "$MODE" = "global" ]; then
  log "Installing scripts/..."
  link_dir_flat "${PELE_ROOT}/scripts" "${CLAUDE_DIR}/scripts"
fi

# ----------------------- merge hooks (global only) -----------------------
if [ "$MODE" = "project" ]; then
  log "Skipping hooks merge (project mode — hooks live in ~/.claude/settings.json globally)."
else
log "Merging hooks into settings.json..."
SETTINGS="${CLAUDE_DIR}/settings.json"

# Collect hook sources to merge in order (later sources extend earlier ones)
HOOK_SRCS=( "${PELE_ROOT}/core/hooks/settings.hooks.json" )
[ "$WITH_FIGMA" = 1 ] && HOOK_SRCS+=( "${PELE_ROOT}/figma-extras/hooks/settings.hooks.json" )

if ! command -v jq >/dev/null 2>&1; then
  warn "jq missing — cannot auto-merge hooks. Manually merge these files into ${SETTINGS}:"
  for s in "${HOOK_SRCS[@]}"; do warn "  ${s}"; done
elif [ "$DRY_RUN" = 1 ]; then
  log "  would merge into $SETTINGS:"
  for s in "${HOOK_SRCS[@]}"; do log "    + ${s}"; done
else
  # Backup if exists
  if [ -f "$SETTINGS" ]; then
    mkdir -p "$BACKUP_DIR"
    cp "$SETTINGS" "${BACKUP_DIR}/settings.json.before-merge"
  fi

  # Build merged hooks payload (deep merge across all hook sources, concatenating arrays per event)
  # Strategy: for each event (PreToolUse, PostToolUse, UserPromptSubmit, ...), concatenate the arrays from all sources.
  # Result is wrapped under {"hooks": ...} and shallow-merged into existing settings.json (replacing the entire .hooks key).
  TMP="$(mktemp)"
  if [ -f "$SETTINGS" ]; then
    BASE="$SETTINGS"
  else
    echo '{}' > "$TMP.base"
    BASE="$TMP.base"
  fi

  jq -s '
    # First arg: base settings.json. Rest: hook source files.
    .[0] as $base
    | (.[1:] | map(.hooks) | reduce .[] as $h ({}; reduce ($h | to_entries[]) as $kv (.; .[$kv.key] = ((.[$kv.key] // []) + $kv.value)))) as $merged_hooks
    | $base * {hooks: $merged_hooks}
  ' "$BASE" "${HOOK_SRCS[@]}" > "$TMP"
  mv "$TMP" "$SETTINGS"
  [ -f "$TMP.base" ] && rm -f "$TMP.base"
  ok "Merged hooks into $SETTINGS (backup at ${BACKUP_DIR}/settings.json.before-merge if existed)"
fi
fi  # end: MODE != "project"

# ----------------------- done -----------------------
echo ""
ok "Pele installed to ${CLAUDE_DIR}/"
[ -d "$BACKUP_DIR" ] && log "Backup of any conflicts: ${BACKUP_DIR}"

# Check for unreplaced placeholders and warn (safety net — should be 0 after the decouple refactor)
PLACEHOLDER_COUNT=0
if command -v grep >/dev/null 2>&1; then
  PLACEHOLDER_COUNT=$(grep -rEn '<(YourApp|your-monorepo|your build recipe|DesignSystemPackage|ImageRegistry)' "${PELE_ROOT}/core/" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')
fi
if [ "${PLACEHOLDER_COUNT}" -gt 0 ]; then
  echo ""
  echo "${C_YELLOW}!${C_RESET} ${C_BOLD}${PLACEHOLDER_COUNT} placeholders${C_RESET} found in rule files (e.g. ${C_BOLD}<YourApp>${C_RESET}, ${C_BOLD}<your build recipe>${C_RESET})."
  echo "  These are project-specific defaults you should review and replace."
  echo ""
  echo "  List them all:"
  echo "    ${C_DIM}grep -rEn '<(YourApp|your-monorepo|your build recipe|DesignSystemPackage|ImageRegistry)' ${PELE_ROOT}/core/ --include='*.md'${C_RESET}"
fi

# ----------------------- project mode: manual instruction -----------------------
if [ "$MODE" = "project" ]; then
  echo ""
  echo "${C_BOLD}Next step (project mode):${C_RESET}"
  echo "  Add this line to ${PROJECT_PATH}/CLAUDE.md (or ${PROJECT_PATH}/AGENTS.md):"
  echo ""
  echo "      ${C_BOLD}@.claude/rules/index.md${C_RESET}"
  echo ""
  echo "  Without it, the pele rules are installed but Claude will not auto-load the index."
  echo "  (The @ syntax recursively injects file contents into the agent's context.)"
fi

echo ""
echo "Verify with:"
if [ "$MODE" = "global" ]; then
  echo "  claude mcp list                          # MCP servers"
  echo "  ls -la ${CLAUDE_DIR}/rules ${CLAUDE_DIR}/agents ${CLAUDE_DIR}/skills"
else
  echo "  ls -la ${CLAUDE_DIR}/rules ${CLAUDE_DIR}/agents ${CLAUDE_DIR}/skills"
fi
echo ""
echo "Uninstall with:"
if [ "$MODE" = "global" ]; then
  echo "  ${PELE_ROOT}/uninstall.sh"
else
  echo "  ${PELE_ROOT}/uninstall.sh --project ${PROJECT_PATH}"
fi
