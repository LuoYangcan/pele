#!/usr/bin/env bash
# Export Apple's Xcode-provided skills into this repo's skills/ so install.sh links them
# like any other skill. The exported content ships inside Xcode and is NOT committed:
# this script rewrites a managed block in .gitignore listing exactly what it wrote.
#
# Re-run after every Xcode upgrade. Idempotent.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=xcode-tooling.sh
. "$ROOT/scripts/xcode-tooling.sh"

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

log() {
  [ "$QUIET" -eq 1 ] || printf '[sync-xcode-skills] %s\n' "$*"
}

fail() {
  printf '[sync-xcode-skills] %s\n' "$*" >&2
  exit 1
}

APP="$(xcode_app_with agent)" || fail "no Xcode with Developer/usr/bin/agent found"
AGENT="$APP/Contents/Developer/usr/bin/agent"
log "exporting from $(basename "$APP") ($(xcode_short_version "$APP"))"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
# An unavailable Xcode MCP service can leave export waiting indefinitely.
python3 - "$AGENT" "$STAGE" <<'PY_EXPORT'
import subprocess, sys
try:
    result = subprocess.run([sys.argv[1], "skills", "export"], cwd=sys.argv[2], stdout=subprocess.DEVNULL, timeout=30)
    sys.exit(result.returncode)
except subprocess.TimeoutExpired:
    print("[sync-xcode-skills] export timed out after 30s; existing skills were preserved", file=sys.stderr)
    sys.exit(124)
PY_EXPORT

SRC="$STAGE/xcode-skills"
[ -d "$SRC" ] || fail "export produced no xcode-skills directory"

# Exported skills this harness does not use (C bounds safety, document-based apps,
# build-setting audits, XCTest migration); skip them so they stay out of every skill listing.
EXCLUDED=(adopt-c-bounds-safety audit-xcode-security-settings building-document-based-swiftui-applications modernize-tests)
is_excluded() {
  local candidate
  for candidate in "${EXCLUDED[@]}"; do
    [ "$candidate" = "$1" ] && return 0
  done
  return 1
}

SKILLS_DIR="$ROOT/core/skills"
NAMES=()
for dir in "$SRC"/*/; do
  [ -f "$dir/SKILL.md" ] || continue
  name="$(basename "$dir")"
  is_excluded "$name" && continue
  NAMES+=("$name")
done
[ "${#NAMES[@]}" -gt 0 ] || fail "export contained no SKILL.md"

BEGIN='# >>> xcode-provided skills (managed by scripts/sync-xcode-skills.sh) >>>'
END='# <<< xcode-provided skills <<<'
IGNORE="$ROOT/.gitignore"
if [ -f "$IGNORE" ]; then
  while IFS= read -r old; do
    [[ "$old" =~ ^/(core/)?skills/[a-zA-Z0-9_-]+/$ ]] || fail "invalid managed skill path: $old"
    old_name="$(basename "$old")"
    if [ ! -f "$SRC/$old_name/SKILL.md" ] || is_excluded "$old_name" || [ "$ROOT$old" != "$SKILLS_DIR/$old_name/" ]; then
      [ -z "$(git -C "$ROOT" ls-files -- "${old#/}")" ] || fail "refusing to remove tracked skill: $old"
      rm -rf "$ROOT$old"
    fi
  done < <(awk -v b="$BEGIN" -v e="$END" '$0 == b {active=1; next} $0 == e {active=0} active' "$IGNORE")
fi

mkdir -p "$SKILLS_DIR"
for name in "${NAMES[@]}"; do
  dir="$SRC/$name"
  dest="$SKILLS_DIR/$name"
  [ -z "$(git -C "$ROOT" ls-files -- "${dest#"$ROOT"/}")" ] || fail "refusing to replace tracked skill: $dest"
  rm -rf "$dest"
  cp -R "$dir" "$dest"
  # Xcode exports read-only files; make them writable so the next sync can replace them.
  chmod -R u+w "$dest"
done

KEPT="$(mktemp)"
trap 'rm -rf "$STAGE" "$KEPT"' EXIT

if [ -f "$IGNORE" ]; then
  awk -v b="$BEGIN" -v e="$END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip
  ' "$IGNORE" > "$KEPT"
else
  : > "$KEPT"
fi

# Drop trailing blank lines so repeated runs do not accumulate them.
while [ -s "$KEPT" ] && [ -z "$(tail -n 1 "$KEPT")" ]; do
  sed -i '' -e '$d' "$KEPT"
done

{
  cat "$KEPT"
  [ -s "$KEPT" ] && printf '\n'
  printf '%s\n' "$BEGIN"
  printf '/core/skills/%s/\n' "${NAMES[@]}"
  printf '%s\n' "$END"
} > "$IGNORE"

log "synced ${#NAMES[@]} skills: ${NAMES[*]}"
