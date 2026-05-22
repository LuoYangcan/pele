#!/usr/bin/env bash
# Pele uninstaller — removes all symlinks pointing into this pele repo from a .claude/ directory.
# Does NOT restore backups (those live in <claude-dir>.backup-* and you can restore manually).
# Does NOT touch settings.json (your hooks may have been customized; restore from backup if needed).
#
# Usage:
#   ./uninstall.sh                          # global mode (default): clean ~/.claude/
#   ./uninstall.sh --global                 # explicit global mode
#   ./uninstall.sh --project <path>         # project mode: clean <path>/.claude/
#   ./uninstall.sh --dry-run                # show what would be removed
#
# --global and --project are mutually exclusive.

set -euo pipefail

DRY_RUN=0
MODE=""
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
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

[ -z "$MODE" ] && MODE="global"

PELE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ "$MODE" = "project" ]; then
  if [ ! -d "$PROJECT_PATH" ]; then
    echo "Error: project path '$PROJECT_PATH' does not exist." >&2
    exit 2
  fi
  PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd -P)"
  CLAUDE_DIR="${PROJECT_PATH}/.claude"
else
  CLAUDE_DIR="${HOME}/.claude"
fi

if [ ! -d "$CLAUDE_DIR" ]; then
  echo "[pele-uninstall] Nothing to do: $CLAUDE_DIR does not exist."
  exit 0
fi

if [ -t 1 ]; then
  C_DIM=$'\033[2m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
  C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RESET=""
fi
log() { echo "${C_DIM}[pele-uninstall]${C_RESET} $*"; }
ok()  { echo "${C_GREEN}✓${C_RESET} $*"; }

log "Mode:   ${MODE}$([ "$MODE" = "project" ] && echo " (${PROJECT_PATH})")"
log "Target: ${CLAUDE_DIR}"

removed=0
# Walk <claude-dir>/ and unlink any symlinks pointing into PELE_ROOT
while IFS= read -r -d '' lnk; do
  target="$(readlink "$lnk")"
  case "$target" in
    "${PELE_ROOT}"*)
      if [ "$DRY_RUN" = 1 ]; then
        log "would remove: $lnk → $target"
      else
        rm "$lnk"
        log "removed: $lnk"
      fi
      removed=$((removed+1))
      ;;
  esac
done < <(find "${CLAUDE_DIR}" -type l -print0 2>/dev/null)

ok "Pele symlinks removed: ${removed}"
echo ""
log "Notes:"
if [ "$MODE" = "global" ]; then
  log "  • settings.json hooks were NOT modified — edit manually or restore from ~/.claude.backup-*/settings.json.before-merge"
else
  log "  • ${PROJECT_PATH}/CLAUDE.md and ${PROJECT_PATH}/AGENTS.md were NOT modified — remove the '@.claude/rules/index.md' line manually if you added it"
fi
log "  • Backups of pre-existing files are still in ${CLAUDE_DIR}.backup-* — restore manually as needed"
