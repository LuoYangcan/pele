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
( cd "$STAGE" && "$AGENT" skills export >/dev/null )

SRC="$STAGE/xcode-skills"
[ -d "$SRC" ] || fail "export produced no xcode-skills directory"

NAMES=()
for dir in "$SRC"/*/; do
  [ -f "$dir/SKILL.md" ] || continue
  name="$(basename "$dir")"
  dest="$ROOT/skills/$name"
  rm -rf "$dest"
  cp -R "$dir" "$dest"
  # Xcode exports read-only files; make them writable so the next sync can replace them.
  chmod -R u+w "$dest"
  NAMES+=("$name")
done

[ "${#NAMES[@]}" -gt 0 ] || fail "export contained no SKILL.md"

BEGIN='# >>> xcode-provided skills (managed by scripts/sync-xcode-skills.sh) >>>'
END='# <<< xcode-provided skills <<<'
IGNORE="$ROOT/.gitignore"
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
  printf '/skills/%s/\n' "${NAMES[@]}"
  printf '%s\n' "$END"
} > "$IGNORE"

log "synced ${#NAMES[@]} skills: ${NAMES[*]}"
