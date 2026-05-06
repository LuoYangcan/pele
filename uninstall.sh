#!/usr/bin/env bash
# Pele uninstaller — removes all symlinks pointing into this pele repo from ~/.claude/.
# Does NOT restore backups (those live in ~/.claude.backup-* and you can restore manually).
# Does NOT touch settings.json (your hooks may have been customized; restore from backup if needed).
#
# Usage:
#   ./uninstall.sh             # remove pele symlinks
#   ./uninstall.sh --dry-run   # show what would be removed

set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

PELE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CLAUDE_DIR="${HOME}/.claude"

if [ -t 1 ]; then
  C_DIM=$'\033[2m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
  C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RESET=""
fi
log() { echo "${C_DIM}[pele-uninstall]${C_RESET} $*"; }
ok()  { echo "${C_GREEN}✓${C_RESET} $*"; }

removed=0
# Walk ~/.claude/ and unlink any symlinks pointing into PELE_ROOT
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
log "  • settings.json hooks were NOT modified — edit manually or restore from ~/.claude.backup-*/settings.json.before-merge"
log "  • Backups of pre-existing files are still in ~/.claude.backup-* — restore manually as needed"
