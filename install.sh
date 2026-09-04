#!/usr/bin/env bash
# Pele installer — symlinks core/ into a .claude/ directory (global or per-project).
#
# Usage:
#   ./install.sh                          # global mode (default): install into ~/.claude/
#   ./install.sh --global                 # explicit global mode (same as default)
#   ./install.sh --project <path>         # project mode: install into <path>/.claude/
#   ./install.sh --host codex             # install for Codex instead of Claude Code
#   ./install.sh --host both              # install for both hosts
#   ./install.sh --figma                  # also install figma-extras hooks (global mode only)
#   ./install.sh --dry-run                # show what would be done, do not change anything
#   ./install.sh --force                  # skip confirmation prompts (still backs up)
#
# Hosts (--host claude|codex|both, default claude):
#   claude - ~/.claude/: CLAUDE.md index, .md agents, commands/, hooks merged.
#   codex  - ~/.codex/:  AGENTS.md index, .toml agents, prompts/, no hooks.
#            Global only; Codex has no per-project config dir.
#
# Modes (--global and --project are mutually exclusive):
#   global  — symlink core/{rules,agents,skills,commands,templates}/* into ~/.claude/,
#             merge hooks into ~/.claude/settings.json, install CLAUDE.md.
#   project — symlink the same dirs into <path>/.claude/.
#             Does NOT touch <path>/CLAUDE.md or <path>/AGENTS.md.
#             Does NOT merge hooks (hooks live in ~/.claude/settings.json globally).
#             Prints manual instruction to add `@.claude/pele-index.md` to <path>/CLAUDE.md.
#
# Idempotent: re-running updates symlinks; existing files are backed up to ~/.claude.backup-<timestamp>/

set -euo pipefail

# -------------------------- args --------------------------
WITH_FIGMA=0
HOST="claude"        # claude | codex | both
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
    --host)
      shift
      if [ $# -eq 0 ] || [ -z "${1:-}" ]; then
        echo "Error: --host requires a value (claude | codex | both)." >&2
        exit 2
      fi
      case "$1" in
        claude|codex|both) HOST="$1" ;;
        *) echo "Error: --host must be claude, codex, or both (got '$1')." >&2; exit 2 ;;
      esac
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
      cat <<'EOF'
Pele installer — symlinks core/ into a .claude/ directory (global or per-project).

Usage:
  ./install.sh                          # global mode (default): install into ~/.claude/
  ./install.sh --global                 # explicit global mode (same as default)
  ./install.sh --project <path>         # project mode: install into <path>/.claude/
  ./install.sh --host codex             # install for Codex instead of Claude Code
  ./install.sh --host both              # install for both hosts
  ./install.sh --figma                  # also install figma-extras hooks (global mode only)
  ./install.sh --dry-run                # show what would be done, do not change anything
  ./install.sh --force                  # skip confirmation prompts (still backs up)

Hosts (--host claude|codex|both, default claude):
  claude - ~/.claude/: CLAUDE.md index, .md agents, commands/, hooks merged.
  codex  - ~/.codex/:  AGENTS.md index, .toml agents, prompts/, no hooks.
           Global only; Codex has no per-project config dir.

Modes (--global and --project are mutually exclusive):
  global  — symlink core/{rules,agents,skills,commands,templates}/* into ~/.claude/,
            merge hooks into ~/.claude/settings.json, install CLAUDE.md.
  project — symlink the same dirs into <path>/.claude/.
            Does NOT touch <path>/CLAUDE.md or <path>/AGENTS.md.
            Does NOT merge hooks (hooks live in ~/.claude/settings.json globally).
            Prints manual instruction to add `@.claude/pele-index.md` to <path>/CLAUDE.md.
EOF
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

# Codex reads its config from one place per machine; there is no per-project
# equivalent of <path>/.claude, so Codex installs are global only.
if [ "$MODE" = "project" ] && [ "$HOST" != "claude" ]; then
  echo "Error: --host ${HOST} is incompatible with --project (Codex config is global only)." >&2
  exit 2
fi

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
CODEX_DIR="${CODEX_HOME:-${HOME}/.codex}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${CLAUDE_DIR}.backup-${TS}"

# Set per host pass; backup_if_exists and link helpers read these.
CURRENT_TARGET="$CLAUDE_DIR"
CURRENT_BACKUP="$BACKUP_DIR"

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
log "Host:      ${HOST}"
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
    local rel="${p#${CURRENT_TARGET}/}"
    local dest="${CURRENT_BACKUP}/${rel}"
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

# Mirror only files with a given extension (agents/: .md for Claude, .toml for Codex)
link_dir_ext() {
  local src="$1" dst="$2" ext="$3"
  mkdir -p "$dst"
  local f base found=0
  for f in "$src"/*."$ext"; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    link_file "$f" "${dst}/${base}"
    found=1
  done
  [ "$found" = 0 ] && warn "  no .${ext} files in $(basename "$src")/ — nothing linked"
  return 0
}

# Some skills are written for one host's tooling and are noise on the other.
skill_is_compatible() {
  case "$1:$2" in
    claude:codex-simplify|claude:source-command-review-codex|codex:source-command-review)
      return 1
      ;;
  esac
  return 0
}

# Mirror a directory containing nested dirs (e.g. skills/<name>/)
link_dir_recursive_top() {
  # Symlink each TOP-LEVEL entry in src (file or dir) into dst.
  # Top-level dirs are linked as a whole (one symlink), so updates inside the source repo are visible immediately.
  local src="$1" dst="$2" host="${3:-claude}"
  mkdir -p "$dst"
  local entry base
  for entry in "$src"/*; do
    [ -e "$entry" ] || continue
    base="$(basename "$entry")"
    skill_is_compatible "$host" "$base" || { log "  skip: ${base} (not for ${host})"; continue; }
    link_file "$entry" "${dst}/${base}"
  done
}

# ----------------------- confirm -----------------------
if [ "$FORCE" != 1 ] && [ "$DRY_RUN" != 1 ]; then
  echo "${C_BOLD}This will:${C_RESET}"
  if [ "$HOST" = "claude" ] || [ "$HOST" = "both" ]; then
    echo "  • symlink ${PELE_ROOT}/core/{rules,agents,skills,commands,templates}/* into ${CLAUDE_DIR}/*"
  fi
  if [ "$HOST" = "codex" ] || [ "$HOST" = "both" ]; then
    echo "  • symlink ${PELE_ROOT}/core/* into ${CODEX_DIR}/* (AGENTS.md index, .toml agents, prompts/)"
  fi
  if [ "$MODE" = "global" ]; then
    echo "  • symlink ${PELE_ROOT}/core/CLAUDE.md to ${CLAUDE_DIR}/CLAUDE.md"
    [ "$WITH_FIGMA" = 1 ] && echo "  • merge ${PELE_ROOT}/figma-extras/hooks/settings.hooks.json into settings.json"
    echo "  • merge core hooks into ${CLAUDE_DIR}/settings.json (backup taken)"
  else
    echo "  • leave ${PROJECT_PATH}/CLAUDE.md and ${PROJECT_PATH}/AGENTS.md untouched"
    echo "  • print manual instruction to add '@.claude/pele-index.md' after install"
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

# ----------------------- core install, per host -----------------------
# Claude and Codex read the same content from different filenames and dirs:
#   index    CLAUDE.md / pele-index.md   vs  AGENTS.md
#   agents   *.md                        vs  *.toml
#   commands commands/                   vs  prompts/
# Hooks stay Claude-only — they are a Claude Code settings.json feature.

install_core_for_host() {
  local host="$1" dir="$2"
  local index_name agents_ext commands_dir

  if [ "$host" = "codex" ]; then
    index_name="AGENTS.md"; agents_ext="toml"; commands_dir="prompts"
  elif [ "$MODE" = "global" ]; then
    index_name="CLAUDE.md"; agents_ext="md"; commands_dir="commands"
  else
    index_name="pele-index.md"; agents_ext="md"; commands_dir="commands"
  fi

  CURRENT_TARGET="$dir"
  CURRENT_BACKUP="${dir}.backup-${TS}"
  mkdir -p "$dir"

  log "[${host}] Installing ${index_name}..."
  link_file "${PELE_ROOT}/core/CLAUDE.md" "${dir}/${index_name}"

  log "[${host}] Installing rules/..."
  link_dir_flat "${PELE_ROOT}/core/rules" "${dir}/rules"

  log "[${host}] Installing agents/ (.${agents_ext})..."
  link_dir_ext "${PELE_ROOT}/core/agents" "${dir}/agents" "$agents_ext"

  log "[${host}] Installing ${commands_dir}/..."
  link_dir_flat "${PELE_ROOT}/core/commands" "${dir}/${commands_dir}"

  log "[${host}] Installing templates/..."
  link_dir_flat "${PELE_ROOT}/core/templates" "${dir}/templates"

  log "[${host}] Installing skills/..."
  link_dir_recursive_top "${PELE_ROOT}/core/skills" "${dir}/skills" "$host"

  if [ "$MODE" = "global" ]; then
    log "[${host}] Installing scripts/..."
    link_dir_flat "${PELE_ROOT}/scripts" "${dir}/scripts"
  fi
}

INSTALLED_DIRS=()
if [ "$HOST" = "claude" ] || [ "$HOST" = "both" ]; then
  install_core_for_host claude "$CLAUDE_DIR"
  INSTALLED_DIRS+=( "$CLAUDE_DIR" )
fi
if [ "$HOST" = "codex" ] || [ "$HOST" = "both" ]; then
  install_core_for_host codex "$CODEX_DIR"
  INSTALLED_DIRS+=( "$CODEX_DIR" )
fi

# Restore Claude as the target for the hooks step below.
CURRENT_TARGET="$CLAUDE_DIR"
CURRENT_BACKUP="$BACKUP_DIR"

# ----------------------- merge hooks (global only) -----------------------
if [ "$HOST" = "codex" ]; then
  log "Skipping hooks merge (--host codex — hooks are a Claude Code feature)."
elif [ "$MODE" = "project" ]; then
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
fi  # end: hooks applicable

# ----------------------- done -----------------------
echo ""
for d in "${INSTALLED_DIRS[@]}"; do ok "Pele installed to ${d}/"; done
[ -d "$BACKUP_DIR" ] && log "Backup of any conflicts: ${BACKUP_DIR}"

# Check for unreplaced placeholders and warn (safety net — should be 0 after the decouple refactor)
PLACEHOLDER_COUNT=0
if command -v grep >/dev/null 2>&1; then
  PLACEHOLDER_COUNT=$(grep -rEn '<(YourApp|your-monorepo|your (build|iOS build|macOS build|lint check|test|auto-fix) recipe|DesignSystemPackage|ImageRegistry)' "${PELE_ROOT}/core/" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')
fi
if [ "${PLACEHOLDER_COUNT}" -gt 0 ]; then
  echo ""
  echo "${C_YELLOW}!${C_RESET} ${C_BOLD}${PLACEHOLDER_COUNT} placeholders${C_RESET} found in rule files (e.g. ${C_BOLD}<YourApp>${C_RESET}, ${C_BOLD}<your build recipe>${C_RESET})."
  echo "  These are project-specific defaults you should review and replace."
  echo ""
  echo "  List them all:"
  echo "    ${C_DIM}grep -rEn '<(YourApp|your-monorepo|your (build|iOS build|macOS build|lint check|test|auto-fix) recipe|DesignSystemPackage|ImageRegistry)' ${PELE_ROOT}/core/ --include='*.md'${C_RESET}"
fi

# ----------------------- project mode: manual instruction -----------------------
if [ "$MODE" = "project" ]; then
  echo ""
  echo "${C_BOLD}Next step (project mode):${C_RESET}"
  echo "  Add this line to ${PROJECT_PATH}/CLAUDE.md (or ${PROJECT_PATH}/AGENTS.md):"
  echo ""
  echo "      ${C_BOLD}@.claude/pele-index.md${C_RESET}"
  echo ""
  echo "  Without it, the pele rules are installed but Claude will not auto-load the index."
  echo "  (The @ syntax recursively injects file contents into the agent's context.)"
fi

echo ""
echo "Verify with:"
for d in "${INSTALLED_DIRS[@]}"; do
  echo "  ls -la ${d}/rules ${d}/agents ${d}/skills"
done
echo ""
echo "Uninstall with:"
if [ "$MODE" = "global" ]; then
  echo "  ${PELE_ROOT}/uninstall.sh --host ${HOST}"
else
  echo "  ${PELE_ROOT}/uninstall.sh --project ${PROJECT_PATH}"
fi
