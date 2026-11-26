#!/usr/bin/env bash
# Install Pele for Claude Code, Codex, or both without replacing user-owned config.
set -euo pipefail

HOST="claude"
MODE="global"
MODE_FLAG=""
PROJECT_PATH=""
WITH_FIGMA=0
DRY_RUN=0
FORCE=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--global | --project PATH] [--host claude|codex|both]
                    [--figma] [--dry-run] [--force]

Global targets are ~/.claude and ${CODEX_HOME:-~/.codex}. Project targets are
<project>/.claude and <project>/.codex; Pele adds only a managed short entry to
an existing project AGENTS.md and never replaces its content.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --global) [ "$MODE_FLAG" != project ] || { echo "--global and --project are mutually exclusive" >&2; exit 2; }; MODE="global"; MODE_FLAG="global"; shift ;;
    --project) [ "$MODE_FLAG" != global ] || { echo "--global and --project are mutually exclusive" >&2; exit 2; }; MODE="project"; MODE_FLAG="project"; PROJECT_PATH="${2:-}"; [ -n "$PROJECT_PATH" ] || { echo "--project requires PATH" >&2; exit 2; }; shift 2 ;;
    --host) HOST="${2:-}"; case "$HOST" in claude|codex|both) ;; *) echo "--host must be claude, codex, or both" >&2; exit 2;; esac; shift 2 ;;
    --figma) WITH_FIGMA=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

PELE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CLAUDE_DIR="${HOME}/.claude"
CODEX_DIR="${CODEX_HOME:-${HOME}/.codex}"
if [ "$MODE" = "project" ]; then
  [ ! -L "$PROJECT_PATH" ] || { echo "Project root is a symlink; refusing to write through it: $PROJECT_PATH" >&2; exit 2; }
  if [ ! -d "$PROJECT_PATH" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      PROJECT_PATH="$(cd "$(dirname "$PROJECT_PATH")" && pwd -P)/$(basename "$PROJECT_PATH")"
    else
      echo "Project path does not exist: $PROJECT_PATH" >&2
      exit 2
    fi
  else
    PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd -P)"
  fi
  CLAUDE_DIR="$PROJECT_PATH/.claude"
  CODEX_DIR="$PROJECT_PATH/.codex"
fi

python_bin=""
for candidate in "${PYTHON_BIN:-}" python3.14 python3.13 python3.12 python3.11 python3 python; do
  [ -n "$candidate" ] || continue
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
    python_bin="$candidate"
    break
  fi
done
[ -n "$python_bin" ] || { echo "Python 3.11 or newer is required." >&2; exit 2; }
[ -f "$PELE_ROOT/scripts/harness-doctor.py" ] || { echo "Missing required source: scripts/harness-doctor.py" >&2; exit 2; }
[ -f "$PELE_ROOT/scripts/model-policy.py" ] || { echo "Missing required source: scripts/model-policy.py" >&2; exit 2; }
[ -x "$PELE_ROOT/core/hooks/protected-branch.sh" ] || { echo "Missing executable protected-branch hook." >&2; exit 2; }
[ -f "$PELE_ROOT/core/hooks/settings.hooks.json" ] || { echo "Missing required hook source." >&2; exit 2; }
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required by the protected-branch hook; install it before installing Pele." >&2
  exit 2
fi
if [ "$WITH_FIGMA" = 1 ] && [ "$HOST" = "codex" ]; then
  echo "--figma only configures Claude Code hooks." >&2
  exit 2
fi
[ "$WITH_FIGMA" = 0 ] || [ "$MODE" = global ] || { echo "--figma is only available in global mode." >&2; exit 2; }
[ "$WITH_FIGMA" = 0 ] || [ -f "$PELE_ROOT/figma-extras/hooks/settings.hooks.json" ] || { echo "Missing required Figma hook source." >&2; exit 2; }

log() { printf '[pele] %s\n' "$*"; }
run_doctor() { "$python_bin" "$PELE_ROOT/scripts/harness-doctor.py" "$@"; }
maybe_mkdir() {
  if [ "$DRY_RUN" = 1 ]; then log "would create directory: $1"; else mkdir -p "$1"; fi
}
backup_or_replace() {
  local path="$1" backup="$2"
  [ -e "$path" ] || [ -L "$path" ] || return 0
  local destination="$backup/${path#${CURRENT_TARGET}/}"
  if [ "$DRY_RUN" = 1 ]; then
    log "would back up: $path -> $destination"
  else
    mkdir -p "$(dirname "$destination")"
    mv "$path" "$destination"
  fi
}
link_file() {
  local source="$1" destination="$2" backup="$3"
  if [ -L "$destination" ] && [ "$(readlink "$destination")" = "$source" ]; then return 0; fi
  backup_or_replace "$destination" "$backup"
  if [ "$DRY_RUN" = 1 ]; then
    log "would link: $destination -> $source"
  else
    mkdir -p "$(dirname "$destination")"
    ln -s "$source" "$destination"
  fi
}
link_flat() {
  local source_dir="$1" destination_dir="$2" backup="$3" extension="${4:-}"
  maybe_mkdir "$destination_dir"
  local source
  for source in "$source_dir"/*; do
    [ -e "$source" ] || continue
    [ "$(basename "$source")" != "__pycache__" ] || continue
    [[ "$source" != *.pyc ]] || continue
    [ -z "$extension" ] || [[ "$source" == *".$extension" ]] || continue
    link_file "$source" "$destination_dir/$(basename "$source")" "$backup"
  done
}
link_skills() {
  local destination="$1" backup="$2" host="$3"
  maybe_mkdir "$destination"
  local source name
  for source in "$PELE_ROOT/core/skills"/*; do
    [ -e "$source" ] || continue
    name="$(basename "$source")"
    case "$host:$name" in
      claude:codex-simplify|claude:source-command-review-codex|claude:source-command-pr-review|codex:source-command-review) continue ;;
    esac
    link_file "$source" "$destination/$name" "$backup"
  done
}
preflight_directories() {
  printf '%s\n' rules templates skills scripts hooks agents prompts commands
}
managed_directories() {
  local host="$1"
  printf '%s\n' rules templates skills scripts hooks agents
  if [ "$host" = codex ]; then printf '%s\n' prompts; else printf '%s\n' commands; fi
}
preflight_host_target() {
  local host="$1" target="$2" directory
  [ ! -L "$target" ] || { echo "Host target is a symlink; refusing to write through it: $target" >&2; exit 2; }
  for directory in $(preflight_directories); do
    if [ -L "$target/$directory" ] && [ ! -e "$target/$directory" ]; then
      echo "Host subdirectory is a dangling symlink; refusing to migrate it: $target/$directory" >&2
      exit 2
    fi
    if [ -L "$target/$directory" ] && [ ! -d "$target/$directory" ]; then
      echo "Host subdirectory symlink does not point to a directory: $target/$directory" >&2
      exit 2
    fi
  done
}
materialize_symlink_directory() {
  local path="$1" backup="$2"
  [ -L "$path" ] || return 0
  local destination="$backup/directory-links/${path#${CURRENT_TARGET}/}"
  local original_source
  original_source="$(cd "$path" && pwd -P)"
  if [ "$DRY_RUN" = 1 ]; then
    log "would back up and materialize directory symlink: $path -> $destination"
    return
  fi
  [ ! -e "$destination" ] && [ ! -L "$destination" ] || { echo "Refusing to overwrite symlink backup: $destination" >&2; exit 2; }
  mkdir -p "$(dirname "$destination")"
  mv "$path" "$destination"
  mkdir -p "$path"
  cp -a "$original_source"/. "$path"/
}
prepare_host_target() {
  local host="$1" target="$2" backup="$3" directory
  CURRENT_TARGET="$target"
  maybe_mkdir "$target"
  for directory in $(managed_directories "$host"); do
    materialize_symlink_directory "$target/$directory" "$backup"
  done
}
install_index() {
  local host="$1" target="$2" backup="$3" index
  if [ "$host" = claude ]; then
    index="$target/$([ "$MODE" = global ] && printf CLAUDE.md || printf pele-index.md)"
    link_file "$PELE_ROOT/core/CLAUDE.md" "$index" "$backup"
    return
  fi
  link_file "$PELE_ROOT/core/CLAUDE.md" "$target/pele-index.md" "$backup"
  if [ "$MODE" = global ]; then
    index="$target/AGENTS.md"
    run_doctor index install --path "$index" --entry "Read $target/pele-index.md before following Pele-managed workflow." --backup-dir "$backup/index" $([ "$DRY_RUN" = 1 ] && printf '%s' --dry-run)
  else
    index="$PROJECT_PATH/AGENTS.md"
    run_doctor index install --path "$index" --entry "Read .codex/pele-index.md before following Pele-managed workflow." --backup-dir "$backup/index" $([ "$DRY_RUN" = 1 ] && printf '%s' --dry-run)
  fi
}
install_host() {
  local host="$1" target="$2" backup
  backup="$target.backup-$(date -u +%Y%m%dT%H%M%SZ)"
  prepare_host_target "$host" "$target" "$backup"
  install_index "$host" "$target" "$backup"
  link_flat "$PELE_ROOT/core/rules" "$target/rules" "$backup"
  if [ "$host" = claude ]; then
    link_flat "$PELE_ROOT/core/agents" "$target/agents" "$backup" md
  fi
  link_flat "$PELE_ROOT/core/commands" "$target/$([ "$host" = codex ] && printf prompts || printf commands)" "$backup"
  link_flat "$PELE_ROOT/core/templates" "$target/templates" "$backup"
  link_skills "$target/skills" "$backup" "$host"
  link_flat "$PELE_ROOT/scripts" "$target/scripts" "$backup"
  link_flat "$PELE_ROOT/core/hooks" "$target/hooks" "$backup"
  if [ "$host" = codex ] && [ "$MODE" = project ]; then
    CURRENT_TARGET="$PROJECT_PATH"
    materialize_symlink_directory "$PROJECT_PATH/.agents" "$PROJECT_PATH/.agents.backup-$(date -u +%Y%m%dT%H%M%SZ)-root"
    materialize_symlink_directory "$PROJECT_PATH/.agents/skills" "$PROJECT_PATH/.agents.backup-$(date -u +%Y%m%dT%H%M%SZ)-skills"
    link_skills "$PROJECT_PATH/.agents/skills" "$PROJECT_PATH/.agents.backup-$(date -u +%Y%m%dT%H%M%SZ)-links" codex
    CURRENT_TARGET="$target"
  fi
  if [ "$host" = codex ]; then
    run_doctor codex-hooks --target "$target" --backup-dir "$backup/codex-hooks" $([ "$DRY_RUN" = 1 ] && printf '%s' --dry-run)
    local policy_args=(install --target "$target" --backup-dir "$backup")
    [ "$MODE" = project ] && policy_args+=(--repo "$PROJECT_PATH")
    [ "$DRY_RUN" = 1 ] && policy_args+=(--dry-run)
    "$python_bin" "$PELE_ROOT/scripts/model-policy.py" "${policy_args[@]}"
  fi
  if [ "$host" = claude ]; then
    local settings="$target/settings.json"
    run_doctor merge-hooks --target "$target" --settings "$settings" --source "$PELE_ROOT/core/hooks/settings.hooks.json" --root "$PELE_ROOT" --backup-dir "$backup/claude-hooks" $([ "$DRY_RUN" = 1 ] && printf '%s' --dry-run)
    if [ "$WITH_FIGMA" = 1 ]; then
      run_doctor merge-hooks --target "$target" --settings "$settings" --source "$PELE_ROOT/figma-extras/hooks/settings.hooks.json" --root "$PELE_ROOT" --backup-dir "$backup/figma-hooks" $([ "$DRY_RUN" = 1 ] && printf '%s' --dry-run)
    fi
  fi
  log "installed $host entries in $target"
}

log "root: $PELE_ROOT"
log "host: $HOST; mode: $MODE"
if [ "$HOST" = claude ] || [ "$HOST" = both ]; then preflight_host_target claude "$CLAUDE_DIR"; fi
if [ "$HOST" = codex ] || [ "$HOST" = both ]; then
  preflight_host_target codex "$CODEX_DIR"
  if [ "$MODE" = project ] && [ -L "$PROJECT_PATH/.agents" ] && [ ! -e "$PROJECT_PATH/.agents" ]; then
    echo "Project .agents is a dangling symlink; refusing to migrate it: $PROJECT_PATH/.agents" >&2
    exit 2
  fi
  if [ "$MODE" = project ] && [ -L "$PROJECT_PATH/.agents" ] && [ ! -d "$PROJECT_PATH/.agents" ]; then
    echo "Project .agents symlink does not point to a directory: $PROJECT_PATH/.agents" >&2
    exit 2
  fi
  if [ "$MODE" = project ] && [ -L "$PROJECT_PATH/.agents/skills" ] && { [ ! -e "$PROJECT_PATH/.agents/skills" ] || [ ! -d "$PROJECT_PATH/.agents/skills" ]; }; then
    echo "Project .agents/skills is not a migratable directory symlink: $PROJECT_PATH/.agents/skills" >&2
    exit 2
  fi
fi
if [ "$FORCE" != 1 ] && [ "$DRY_RUN" != 1 ]; then
  printf 'Install Pele-managed entries? [y/N] '
  read -r reply < /dev/tty || reply=n
  case "$reply" in y|Y|yes|YES) ;; *) exit 0;; esac
fi
if [ "$HOST" = claude ] || [ "$HOST" = both ]; then install_host claude "$CLAUDE_DIR"; fi
if [ "$HOST" = codex ] || [ "$HOST" = both ]; then install_host codex "$CODEX_DIR"; fi

log "Codex hook scripts are installed under hooks/. Enable them through Codex /hooks; Pele does not bypass that trust decision."
