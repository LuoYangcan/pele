#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <removed-worktree-absolute-path>" >&2
  exit 2
fi

worktree_path="${1%/}"
case "$worktree_path" in
  /*/.worktrees/*) ;;
  *)
    echo "refusing non-worktree path: $worktree_path" >&2
    exit 3
    ;;
esac

if [[ -e "$worktree_path" ]]; then
  echo "refusing cleanup while worktree still exists: $worktree_path" >&2
  exit 4
fi

if ! command -v plutil >/dev/null 2>&1; then
  echo "plutil unavailable; skipped Xcode DerivedData cleanup"
  exit 0
fi

derived_data_root="${HOME:?}/Library/Developer/Xcode/DerivedData"
if [[ ! -d "$derived_data_root" ]]; then
  echo "Xcode DerivedData directory not found; nothing to remove"
  exit 0
fi

removed_count=0
removed_kb=0
shopt -s nullglob

for candidate in "$derived_data_root"/*; do
  [[ -d "$candidate" ]] || continue
  case "$candidate" in
    "$derived_data_root"/*) ;;
    *)
      echo "refusing target outside DerivedData: $candidate" >&2
      exit 5
      ;;
  esac

  info="$candidate/info.plist"
  [[ -f "$info" ]] || info="$candidate/Info.plist"
  [[ -f "$info" ]] || continue

  workspace_path="$(plutil -extract WorkspacePath raw -o - "$info" 2>/dev/null || true)"
  if [[ "$workspace_path" != "$worktree_path" && "$workspace_path" != "$worktree_path/"* ]]; then
    continue
  fi

  size_kb="$(du -sk "$candidate" 2>/dev/null | awk '{print $1}')"
  size_kb="${size_kb:-0}"
  /bin/rm -r -- "$candidate"
  removed_count=$((removed_count + 1))
  removed_kb=$((removed_kb + size_kb))
  echo "removed DerivedData: $candidate"
done

awk -v count="$removed_count" -v kb="$removed_kb" \
  'BEGIN {printf "DerivedData cleanup: removed %d item(s), %.2f GiB\n", count, kb / 1048576}'
