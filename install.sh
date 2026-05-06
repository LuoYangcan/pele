#!/usr/bin/env bash
# Pele installer — symlinks core/ into ~/.claude/ and merges core hooks into
# ~/.claude/settings.json. Optional figma-extras hooks via --figma.
#
# Usage:
#   ./install.sh              # install core only
#   ./install.sh --figma      # core + figma-extras (PreToolUse hook for Figma MCP)
#   ./install.sh --dry-run    # show what would be done, do not change anything
#   ./install.sh --force      # skip confirmation prompts (still backs up)
#
# Idempotent: re-running updates symlinks; existing files are backed up to ~/.claude.backup-<timestamp>/

set -euo pipefail

# -------------------------- args --------------------------
WITH_FIGMA=0
DRY_RUN=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --figma)   WITH_FIGMA=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# ----------------------- paths -----------------------
PELE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CLAUDE_DIR="${HOME}/.claude"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${HOME}/.claude.backup-${TS}"

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
    local rel="${p#${HOME}/}"
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
  echo "  • symlink ${PELE_ROOT}/core/* into ${CLAUDE_DIR}/*"
  [ "$WITH_FIGMA" = 1 ] && echo "  • merge ${PELE_ROOT}/figma-extras/hooks/settings.hooks.json into settings.json"
  echo "  • merge core hooks into ${CLAUDE_DIR}/settings.json (backup taken)"
  echo "  • back up any conflicting files to ${BACKUP_DIR}/"
  echo ""
  printf "Continue? [y/N] "
  read -r REPLY < /dev/tty || REPLY="n"
  case "$REPLY" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

# ----------------------- core: top-level CLAUDE.md -----------------------
log "Installing CLAUDE.md..."
link_file "${PELE_ROOT}/core/CLAUDE.md" "${CLAUDE_DIR}/CLAUDE.md"

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

# ----------------------- core: scripts (helpers used by hooks) -----------------------
log "Installing scripts/..."
link_dir_flat "${PELE_ROOT}/scripts" "${CLAUDE_DIR}/scripts"

# ----------------------- merge hooks -----------------------
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

# ----------------------- done -----------------------
echo ""
ok "Pele installed."
[ -d "$BACKUP_DIR" ] && log "Backup of any conflicts: ${BACKUP_DIR}"

# Check for unreplaced placeholders and warn
PLACEHOLDER_COUNT=0
if command -v grep >/dev/null 2>&1; then
  PLACEHOLDER_COUNT=$(grep -rEn '<(YourApp|your-monorepo|your build recipe|DesignSystemPackage|ImageRegistry)' "${PELE_ROOT}/core/" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')
fi
if [ "${PLACEHOLDER_COUNT}" -gt 0 ]; then
  echo ""
  echo "${C_YELLOW}!${C_RESET} ${C_BOLD}${PLACEHOLDER_COUNT} placeholders${C_RESET} found in rule files (e.g. ${C_BOLD}<YourApp>${C_RESET}, ${C_BOLD}<your build recipe>${C_RESET})."
  echo "  These are project-specific defaults you should review and replace."
  echo "  See README → ${C_BOLD}\"After install: customize for your project\"${C_RESET}."
  echo ""
  echo "  List them all:"
  echo "    ${C_DIM}grep -rEn '<(YourApp|your-monorepo|your build recipe|DesignSystemPackage|ImageRegistry)' ${PELE_ROOT}/core/ --include='*.md'${C_RESET}"
fi

echo ""
echo "Verify with:"
echo "  claude mcp list                    # MCP servers"
echo "  ls -la ~/.claude/rules ~/.claude/agents ~/.claude/skills"
echo ""
echo "Uninstall with:"
echo "  ${PELE_ROOT}/uninstall.sh"
