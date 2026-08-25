#!/usr/bin/env bash
# One-shot create + initialize an isolated worktree under <repo>/.worktrees/.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: worktree-bootstrap.sh <slug> [--base <branch>] [--type <type>] [--branch <name>]
                             [--copy <rel-path>]... [--init "<cmd>"] [--repo <path>]

Creates <repo>/.worktrees/<slug> on a new branch from origin/<base>, then:
  - copies gitignored config from the main checkout (.claude/settings.local.json
    by default, plus every --copy path that exists)
  - symlinks build/DerivedData/SourcePackages/artifacts when present
    (never checkouts/, repositories/ or workspace-state.json)
  - pre-seeds Claude folder trust via trust-dir.sh when available
  - optionally runs --init "<cmd>" inside the new worktree

--base defaults to origin/HEAD, falling back to dev > main > master.
--branch overrides the default "<type>/<slug>" (type defaults to feat).
Prints worktree path, branch and base commit on success.
EOF
}

die() {
  printf 'worktree-bootstrap: %s\n' "$*" >&2
  exit 2
}

slug=""
base=""
btype="feat"
branch=""
init_cmd=""
repo_arg=""
copies=(".claude/settings.local.json")

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    --base) [ "$#" -ge 2 ] || die "--base needs a value"; base="$2"; shift 2 ;;
    --type) [ "$#" -ge 2 ] || die "--type needs a value"; btype="$2"; shift 2 ;;
    --branch) [ "$#" -ge 2 ] || die "--branch needs a value"; branch="$2"; shift 2 ;;
    --copy) [ "$#" -ge 2 ] || die "--copy needs a value"; copies+=("$2"); shift 2 ;;
    --init) [ "$#" -ge 2 ] || die "--init needs a value"; init_cmd="$2"; shift 2 ;;
    --repo) [ "$#" -ge 2 ] || die "--repo needs a value"; repo_arg="$2"; shift 2 ;;
    -*) die "unknown option: $1" ;;
    *)
      [ -z "$slug" ] || die "unexpected argument: $1"
      slug="$1"
      shift
      ;;
  esac
done

[ -n "$slug" ] || { usage >&2; exit 2; }
[[ "$slug" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid slug: $slug"

toplevel="$(git -C "${repo_arg:-$PWD}" rev-parse --show-toplevel 2>/dev/null)" ||
  die "not inside a Git worktree (or bad --repo)"
# Always anchor on the main checkout, even when invoked from another worktree.
root="${toplevel%%/.worktrees/*}"

if [ -z "$base" ]; then
  head_ref="$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  base="${head_ref#origin/}"
  if [ -z "$base" ]; then
    for candidate in dev main master; do
      if git -C "$root" show-ref --verify --quiet "refs/remotes/origin/$candidate"; then
        base="$candidate"
        break
      fi
    done
  fi
fi
[ -n "$base" ] || die "cannot determine base branch; pass --base"
base="${base#origin/}"

wt="$root/.worktrees/$slug"
[ ! -e "$wt" ] || die "worktree path already exists: $wt"
branch="${branch:-$btype/$slug}"

git -C "$root" fetch origin "$base"
git -C "$root" worktree add "$wt" -b "$branch" "origin/$base"

for rel in "${copies[@]}"; do
  src="$root/$rel"
  [ -e "$src" ] || continue
  if [ -d "$src" ]; then
    # Merge into the (possibly checked-out) directory instead of nesting src inside it.
    mkdir -p "$wt/$rel"
    cp -Rp "$src"/. "$wt/$rel"/
  else
    mkdir -p "$(dirname "$wt/$rel")"
    cp -p "$src" "$wt/$rel"
  fi
  printf 'copied %s\n' "$rel"
done

artifacts="$root/build/DerivedData/SourcePackages/artifacts"
if [ -d "$artifacts" ]; then
  mkdir -p "$wt/build/DerivedData/SourcePackages"
  ln -sfn "$artifacts" "$wt/build/DerivedData/SourcePackages/artifacts"
  printf 'linked SPM artifacts\n'
fi

trust="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/trust-dir.sh"
if [ -x "$trust" ]; then
  "$trust" "$wt" || printf 'worktree-bootstrap: trust-dir.sh failed (continue manually)\n' >&2
fi

if [ -n "$init_cmd" ]; then
  if ! (cd "$wt" && bash -c "$init_cmd"); then
    printf 'worktree-bootstrap: init command failed; worktree kept at %s\n' "$wt" >&2
    exit 1
  fi
fi

printf 'worktree: %s\nbranch: %s\nbase: origin/%s @ %s\n' \
  "$wt" "$branch" "$base" "$(git -C "$wt" rev-parse HEAD)"
