#!/usr/bin/env bash

set -euo pipefail

VALIDATION_REPO_ROOT=""

usage() {
  cat <<'EOF'
Usage:
  validation-receipt.sh [--repo <worktree>] source-fingerprint
  validation-receipt.sh [--repo <worktree>] fingerprint  # compatibility alias
  validation-receipt.sh [--repo <worktree>] run <receipt.json> <check-id> <coverage> -- <command> [args...]
  validation-receipt.sh [--repo <worktree>] reusable <receipt.json> <check-id> <coverage>
  validation-receipt.sh [--repo <worktree>] review-fingerprint semantic <key=value> [...]
  validation-receipt.sh [--repo <worktree>] review-fingerprint ui <key=value> [...]
  validation-receipt.sh [--repo <worktree>] artifact-digest <path>

source-fingerprint is the only fingerprint valid for receipts. It represents
the Git-visible working-tree snapshot while excluding .specs/ and .reviews/.
review-fingerprint binds that source snapshot to caller-supplied context and
sorts bindings by key. semantic requires plan=, validation=, and diff=. ui
requires plan=, validation=, design=, cases=, and build=.
EOF
}

die() {
  printf 'validation-receipt: %s\n' "$*" >&2
  exit 2
}

repo_root() {
  if [[ -n "$VALIDATION_REPO_ROOT" ]]; then
    printf '%s\n' "$VALIDATION_REPO_ROOT"
    return
  fi
  git rev-parse --show-toplevel 2>/dev/null || die "not inside a Git worktree"
}

sha256_stream() {
  shasum -a 256 | awk '{print $1}'
}

artifact_digest() {
  local raw_path="$1"
  local path
  if [[ "$raw_path" == /* ]]; then
    path="$raw_path"
  else
    path="$(repo_root)/$raw_path"
  fi
  command -v python3 >/dev/null 2>&1 || die "python3 is required for artifact-digest"
  python3 - "$path" <<'PY'
import hashlib
import os
import stat
import sys

path = os.path.abspath(sys.argv[1])
if not os.path.lexists(path):
    raise SystemExit(f"artifact does not exist: {path}")

digest = hashlib.sha256()

def add(value):
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)

def add_entry(entry, relative):
    metadata = os.lstat(entry)
    add(os.fsencode(relative))
    add(oct(stat.S_IMODE(metadata.st_mode)).encode())
    if stat.S_ISLNK(metadata.st_mode):
        add(b"symlink")
        add(os.fsencode(os.readlink(entry)))
    elif stat.S_ISREG(metadata.st_mode):
        add(b"file")
        with open(entry, "rb") as stream:
            while True:
                chunk = stream.read(1024 * 1024)
                if not chunk:
                    break
                add(chunk)
    elif stat.S_ISDIR(metadata.st_mode):
        add(b"directory")
    else:
        add(b"special")

if os.path.isdir(path) and not os.path.islink(path):
    add(b"artifact-directory-v1")
    for current, directories, files in os.walk(path, topdown=True, followlinks=False):
        names = sorted(directories + files, key=os.fsencode)
        for name in names:
            entry = os.path.join(current, name)
            relative = os.path.relpath(entry, path).replace(os.sep, "/")
            add_entry(entry, relative)
else:
    add(b"artifact-file-v1")
    add_entry(path, ".")

print(digest.hexdigest())
PY
}

source_fingerprint() {
  local root path absolute target blob
  root="$(repo_root)"

  {
    printf 'source-v2\0head\0'
    git -C "$root" rev-parse HEAD
    printf '\0tracked-diff\0'
    git -C "$root" diff --no-color --no-ext-diff --binary --full-index --no-renames \
      HEAD -- . ':(exclude).specs' ':(exclude).specs/**' \
      ':(exclude).reviews' ':(exclude).reviews/**'
    printf '\0untracked\0'
    while IFS= read -r -d '' path; do
      absolute="$root/$path"
      printf 'path\0%s\0' "$path"
      if [[ -L "$absolute" ]]; then
        target="$(readlink "$absolute")"
        blob="$(printf '%s' "$target" | git hash-object --stdin)"
        printf 'symlink\0%s\0' "$blob"
      elif [[ -f "$absolute" ]]; then
        blob="$(git hash-object --no-filters -- "$absolute")"
        printf 'file\0%s\0' "$blob"
      else
        printf 'missing-or-special\0'
      fi
    done < <(
      git -C "$root" ls-files -z --others --exclude-standard -- . \
        ':(exclude).specs' ':(exclude).specs/**' \
        ':(exclude).reviews' ':(exclude).reviews/**'
    )
  } | sha256_stream
}

valid_receipt_for_fingerprint() {
  local receipt="$1"
  local fingerprint="$2"
  [[ -f "$receipt" ]] || return 1
  jq -e --arg fingerprint "$fingerprint" \
    '.schema_version == 1
     and .fingerprint_kind == "source-v2"
     and .fingerprint == $fingerprint' \
    "$receipt" >/dev/null 2>&1
}

write_check() {
  local receipt="$1"
  local check_id="$2"
  local coverage="$3"
  local status="$4"
  local command_text="$5"
  local expected_fingerprint="$6"
  local fingerprint now base temp changed_during_write

  command -v jq >/dev/null 2>&1 || die "jq is required"
  fingerprint="$(source_fingerprint)"
  changed_during_write=0
  if [[ "$fingerprint" != "$expected_fingerprint" ]]; then
    status="invalidated"
    changed_during_write=1
  fi
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$receipt")"
  if valid_receipt_for_fingerprint "$receipt" "$fingerprint"; then
    base="$(cat "$receipt")"
  else
    base='{"schema_version":1,"checks":{}}'
  fi

  temp="$(mktemp "$(dirname "$receipt")/.validation-receipt.XXXXXX")"
  printf '%s\n' "$base" | jq \
    --arg fingerprint "$fingerprint" \
    --arg now "$now" \
    --arg check_id "$check_id" \
    --arg coverage "$coverage" \
    --arg status "$status" \
    --arg command "$command_text" \
    '.schema_version = 1
     | .fingerprint = $fingerprint
     | .fingerprint_kind = "source-v2"
     | .updated_at = $now
     | .checks = (.checks // {})
     | .checks[$check_id] = {
         status: $status,
         coverage: $coverage,
         command: $command,
         completed_at: $now
       }' >"$temp"
  mv "$temp" "$receipt"
  [[ "$changed_during_write" -eq 0 ]]
}

run_and_record() {
  local receipt="$1"
  local check_id="$2"
  local coverage="$3"
  shift 3
  [[ "${1:-}" == "--" ]] || die "run requires -- before the command"
  shift
  [[ "$#" -gt 0 ]] || die "run requires a command"

  local command_text result status before_fingerprint after_fingerprint source_changed
  printf -v command_text '%q ' "$@"
  command_text="${command_text% }"

  before_fingerprint="$(source_fingerprint)"
  set +e
  if [[ -n "$VALIDATION_REPO_ROOT" ]]; then
    (cd "$VALIDATION_REPO_ROOT" && "$@")
  else
    "$@"
  fi
  result=$?
  set -e
  after_fingerprint="$(source_fingerprint)"
  source_changed=0
  if [[ "$before_fingerprint" != "$after_fingerprint" ]]; then
    status="invalidated"
    source_changed=1
  elif [[ "$result" -eq 0 ]]; then
    status="pass"
  else
    status="fail"
  fi
  if ! write_check \
    "$receipt" "$check_id" "$coverage" "$status" "$command_text" "$after_fingerprint"; then
    source_changed=1
  fi
  if [[ "$source_changed" -eq 1 ]]; then
    printf 'validation-receipt: source changed while check %s ran; result invalidated\n' \
      "$check_id" >&2
    return 3
  fi
  return "$result"
}

check_reusable() {
  local receipt="$1"
  local check_id="$2"
  local coverage="$3"
  local fingerprint
  fingerprint="$(source_fingerprint)"
  valid_receipt_for_fingerprint "$receipt" "$fingerprint" || return 1
  jq -e --arg check_id "$check_id" --arg coverage "$coverage" \
    '.checks[$check_id].status == "pass"
     and .checks[$check_id].coverage == $coverage' \
    "$receipt" >/dev/null
}

review_fingerprint() {
  local profile="${1:-}"
  [[ -n "$profile" ]] || die "review-fingerprint requires semantic or ui profile"
  shift

  local binding key seen required_keys required_key source
  case "$profile" in
    semantic)
      required_keys="plan validation diff"
      ;;
    ui)
      required_keys="plan validation design cases build"
      ;;
    *)
      die "invalid review-fingerprint profile: $profile"
      ;;
  esac

  seen=":"
  for binding in "$@"; do
    [[ "$binding" == *=* ]] || die "binding must be key=value: $binding"
    [[ "$binding" != *$'\n'* && "$binding" != *$'\r'* && "$binding" != *$'\t'* ]] ||
      die "binding must be canonical single-line text"
    key="${binding%%=*}"
    [[ "$key" =~ ^[a-z][a-z0-9_-]*$ ]] || die "invalid binding key: $key"
    [[ "$key" != "source" ]] || die "source binding is computed automatically"
    [[ "$seen" != *":$key:"* ]] || die "duplicate binding key: $key"
    seen="${seen}${key}:"
    [[ -n "${binding#*=}" ]] || die "binding value is empty: $key"
  done
  for required_key in $required_keys; do
    [[ "$seen" == *":$required_key:"* ]] || die "missing $required_key= binding for $profile review"
  done

  source="$(source_fingerprint)"
  {
    printf 'review-input-v2\n'
    printf 'profile=%s\n' "$profile"
    printf 'source=%s\n' "$source"
    printf '%s\n' "$@" | LC_ALL=C sort
  } | sha256_stream
}

main() {
  if [[ "${1:-}" == "--repo" ]]; then
    [[ "$#" -ge 3 ]] || { usage >&2; exit 2; }
    VALIDATION_REPO_ROOT="$(
      git -C "$2" rev-parse --show-toplevel 2>/dev/null
    )" || die "invalid repo/worktree: $2"
    shift 2
  fi

  local command="${1:-}"
  case "$command" in
    source-fingerprint)
      shift
      [[ "$#" -eq 0 ]] || { usage >&2; exit 2; }
      source_fingerprint
      ;;
    fingerprint)
      shift
      [[ "$#" -eq 0 ]] || { usage >&2; exit 2; }
      source_fingerprint
      ;;
    run)
      shift
      [[ "$#" -ge 5 ]] || { usage >&2; exit 2; }
      run_and_record "$@"
      ;;
    reusable)
      shift
      [[ "$#" -eq 3 ]] || { usage >&2; exit 2; }
      check_reusable "$@"
      ;;
    review-fingerprint)
      shift
      review_fingerprint "$@"
      ;;
    artifact-digest)
      shift
      [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
      artifact_digest "$1"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
