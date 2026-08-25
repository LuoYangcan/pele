#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: review-input-snapshot.sh [--repo <worktree>] <base-ref> <slug>

Writes .reviews/<slug>-semantic.patch, .reviews/<slug>-untracked.json and
.reviews/<slug>-mtime.txt (mtime/inode of every candidate file, for the
post-review drift check) for a conditional semantic verifier, then
prints their absolute paths and SHA-256 values as JSON.
EOF
}

die() {
  printf 'review-input-snapshot: %s\n' "$*" >&2
  exit 2
}

requested_repo=""
if [[ "${1:-}" == "--repo" ]]; then
  [[ "$#" -ge 3 ]] || { usage >&2; exit 2; }
  requested_repo="$2"
  shift 2
fi
[[ "$#" -eq 2 ]] || { usage >&2; exit 2; }
base_ref="$1"
slug="$2"
[[ "$slug" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid slug: $slug"
command -v jq >/dev/null 2>&1 || die "jq is required"

if [[ -n "$requested_repo" ]]; then
  repo_root="$(git -C "$requested_repo" rev-parse --show-toplevel 2>/dev/null)" ||
    die "invalid repo/worktree: $requested_repo"
else
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a Git worktree"
fi
base_commit="$(
  git -C "$repo_root" rev-parse --verify --end-of-options "${base_ref}^{commit}" 2>/dev/null
)" || die "base ref is not a commit: $base_ref"

review_dir="$repo_root/.reviews"
patch_path="$review_dir/${slug}-semantic.patch"
manifest_path="$review_dir/${slug}-untracked.json"
mtime_path="$review_dir/${slug}-mtime.txt"
mkdir -p "$review_dir"
validation_helper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/validation-receipt.sh"
source_before="$("$validation_helper" --repo "$repo_root" source-fingerprint)"

patch_temp="$(mktemp "$review_dir/.semantic-patch.XXXXXX")"
manifest_temp="$(mktemp "$review_dir/.semantic-untracked.XXXXXX")"
mtime_temp="$(mktemp "$review_dir/.semantic-mtime.XXXXXX")"
cleanup() {
  [[ ! -e "$patch_temp" ]] || unlink "$patch_temp"
  [[ ! -e "$manifest_temp" ]] || unlink "$manifest_temp"
  [[ ! -e "$mtime_temp" ]] || unlink "$mtime_temp"
}
trap cleanup EXIT

git -C "$repo_root" diff --no-color --no-ext-diff --binary --full-index --no-renames \
  "$base_commit" -- . ':(exclude).reviews' ':(exclude).reviews/**' \
  ':(exclude).specs' ':(exclude).specs/**' >"$patch_temp"
git -C "$repo_root" ls-files -z --others --exclude-standard -- . \
  ':(exclude).reviews' ':(exclude).reviews/**' \
  ':(exclude).specs' ':(exclude).specs/**' |
  jq -Rs 'split("\u0000") | map(select(length > 0))' >"$manifest_temp"

# Probe GNU vs BSD stat once: GNU `stat -f` succeeds with filesystem info, so
# exit-code fallback cannot distinguish the two dialects.
if stat -c '%Y' /dev/null >/dev/null 2>&1; then
  stat_style="gnu"
else
  stat_style="bsd"
fi
{
  git -C "$repo_root" -c core.quotepath=off diff --name-only --no-renames "$base_commit" -- . \
    ':(exclude).reviews' ':(exclude).reviews/**' \
    ':(exclude).specs' ':(exclude).specs/**'
  jq -r '.[]' "$manifest_temp"
} | LC_ALL=C sort -u | while IFS= read -r rel; do
  [[ -n "$rel" && -e "$repo_root/$rel" ]] || continue
  # Line format: "<mtime> <inode> <path>" — path last so it may contain spaces.
  if [[ "$stat_style" == "gnu" ]]; then
    stat -c '%Y %i %n' "$repo_root/$rel" 2>/dev/null || true
  else
    stat -f '%m %i %N' "$repo_root/$rel" 2>/dev/null || true
  fi
done >"$mtime_temp"

source_after="$("$validation_helper" --repo "$repo_root" source-fingerprint)"
[[ "$source_before" == "$source_after" ]] ||
  die "source changed while snapshot was generated; retry from the final candidate"

mv "$patch_temp" "$patch_path"
mv "$manifest_temp" "$manifest_path"
mv "$mtime_temp" "$mtime_path"
trap - EXIT

patch_sha256="$(shasum -a 256 "$patch_path" | awk '{print $1}')"
manifest_sha256="$(shasum -a 256 "$manifest_path" | awk '{print $1}')"
mtime_sha256="$(shasum -a 256 "$mtime_path" | awk '{print $1}')"
jq -n \
  --arg base_ref "$base_ref" \
  --arg base_commit "$base_commit" \
  --arg patch_path "$patch_path" \
  --arg patch_sha256 "$patch_sha256" \
  --arg manifest_path "$manifest_path" \
  --arg manifest_sha256 "$manifest_sha256" \
  --arg mtime_path "$mtime_path" \
  --arg mtime_sha256 "$mtime_sha256" \
  '{
    schema_version: 1,
    base_ref: $base_ref,
    base_commit: $base_commit,
    patch: {path: $patch_path, sha256: $patch_sha256},
    untracked_manifest: {path: $manifest_path, sha256: $manifest_sha256},
    mtime_manifest: {path: $mtime_path, sha256: $mtime_sha256}
  }'
