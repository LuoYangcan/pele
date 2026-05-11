#!/usr/bin/env bash
#
# Pele sync helper — pull the user's customized ~/.claude/ into pele/core/ and
# apply the privacy-decoupling placeholder mappings established in PR #6 / #8.
#
# Background:
#   Pele's maintainer (LuoYangCan) keeps ~/.claude/ as a **personal customized**
#   harness that uses real project names (e.g. TodayiOS, TDChat, `just build-ios`,
#   `~/Developer/pele/`). The public pele/core/ must stay **decoupled** — using
#   <YourApp>iOS / <ChatModule> / <your iOS build recipe> / <pele-checkout>
#   placeholders so anyone forking pele can use it on any project.
#
#   This script automates the **safe, repeatable** part of that sync:
#     - cp the right files from ~/.claude/ into pele/core/
#     - apply token-level placeholder replacements (TodayiOS → <YourApp>iOS etc.)
#     - run a final privacy grep and flag locations that need agent / human review
#
#   The script DOES NOT auto-handle:
#     - paragraph-level rewrites (e.g. `just build-ios` hardcode → placeholder + (e.g. ...) example)
#     - dangling-reference cleanup (e.g. removing `image-assets.md` references)
#     - newly-introduced patterns the script doesn't know about
#   For those, the script prints **explicit hints** and the agent / maintainer
#   does a `git diff` review + edits before committing.
#
# Usage:
#
#   cd <pele-checkout>
#   git fetch origin
#   git worktree add .worktrees/sync-N -b chore/sync-N origin/main
#   cd .worktrees/sync-N
#   ../../scripts/sync-from-local.sh             # cp + replace, leaves staged diff
#   ../../scripts/sync-from-local.sh --dry-run   # show what would change, no writes
#
# After the script:
#   1. Read its output — it flags locations that need MANUAL review
#   2. `git diff` — review every change. Pay attention to (a) build-tooling
#      paragraphs (`just X` → `<your X recipe>` should keep `just X` as an
#      example in parentheses, see PR #6); (b) reference removals (e.g. the
#      `image-assets.md` rule doesn't exist in pele, the reference must go);
#      (c) any new pattern the replacement dictionary doesn't cover yet
#   3. Edit anything that slipped through. Add to the replacement dict below
#      if you spot a recurring pattern
#   4. Re-run the final privacy scan: `grep -rEn "$SENSITIVE_PATTERN" core/`
#   5. Commit + PR

set -euo pipefail

# ----------------------- pre-flight -----------------------

CLAUDE_DIR="${HOME}/.claude"
CWD="$(pwd -P)"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
  DRY_RUN=1
fi

log()  { printf "[sync] %s\n" "$*"; }
warn() { printf "[sync] ⚠️  %s\n" "$*" >&2; }
err()  { printf "[sync] ❌ %s\n" "$*" >&2; exit 1; }

# 0a. Must be inside a git worktree
if ! git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  err "Not inside a git repo. cd into a pele worktree first (script writes to \$CWD/core/)."
fi

# 0b. Must look like a pele checkout (has core/agents/ structure)
if [[ ! -d "$CWD/core/agents" || ! -d "$CWD/core/rules" ]]; then
  err "\$CWD ($CWD) doesn't look like a pele checkout (no core/agents/ or core/rules/). cd into the right place."
fi

# 0c. Refuse to run on main directly — sync must go through a branch
BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" == "main" ]]; then
  PELE_MAIN=$(cd "$(git -C "$CWD" rev-parse --git-common-dir)/.." && pwd -P)
  err "Refuse to run on main. Open a worktree first:
    cd $PELE_MAIN
    git fetch origin
    git worktree add .worktrees/sync-N -b chore/sync-from-local-N origin/main
    cd .worktrees/sync-N
    $PELE_MAIN/scripts/sync-from-local.sh"
fi

# 0d. ~/.claude/ must exist
if [[ ! -d "$CLAUDE_DIR" ]]; then
  err "$CLAUDE_DIR does not exist. Nothing to sync from."
fi

log "Source: $CLAUDE_DIR (your customized harness)"
log "Target: $CWD/core (pele worktree on branch '$BRANCH')"
log "Mode:   $([[ $DRY_RUN == 1 ]] && echo 'DRY RUN (no writes)' || echo 'WRITE')"
echo

# ----------------------- 1. cp files -----------------------

# Files that have a 1:1 personal → public mapping (we copy, then apply the
# placeholder dictionary). Don't add project-level rules that pele doesn't ship
# (e.g. image-assets.md, logging-pii.md, viewcontroller-split.md — those live
# in the user's project repo, not in ~/.claude/, but they aren't public-pele
# content either).

declare -a TOP_LEVEL_FILES=(
  "CLAUDE.md"
)
declare -a AGENT_FILES=(
  "agents/generator.md"
  "agents/executor.md"
  "agents/planner.md"
)
declare -a RULE_FILES=(
  "rules/dispatch-pipeline.md"
  "rules/spec-before-code.md"
  "rules/iteration-checkpoint.md"
  "rules/parallel-subagents.md"
  "rules/post-change-verify.md"
  "rules/commit-message.md"
  "rules/swift-formatting.md"
  "rules/use-worktree.md"
)
declare -a TEMPLATE_FILES=(
  "templates/spec-template.md"
  "templates/generator-feedback-template.md"
)
# Skills: each skill is a directory; we only sync SKILL.md (evals/ etc. are gitignored)
declare -a SKILL_NAMES=(
  "scan-trigger-docs"
  "lean-diff"
  "find-ios-build-artifact"
  "use-worktree"
  "architecture-first"
  "dead-code"
)

cp_one() {
  local rel="$1"
  local src="$CLAUDE_DIR/$rel"
  local dst="$CWD/core/$rel"
  if [[ ! -f "$src" ]]; then
    log "  skip: $rel (not present in ~/.claude/)"
    return
  fi
  if cmp -s "$src" "$dst" 2>/dev/null; then
    log "  same: $rel"
    return
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    log "  WOULD COPY: $rel"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    log "  copy: $rel"
  fi
}

log "==> Copying files from ~/.claude/ to <worktree>/core/"
for f in "${TOP_LEVEL_FILES[@]}"; do cp_one "$f"; done
for f in "${AGENT_FILES[@]}";   do cp_one "$f"; done
for f in "${RULE_FILES[@]}";    do cp_one "$f"; done
for f in "${TEMPLATE_FILES[@]}";do cp_one "$f"; done

log "==> Syncing skills (only SKILL.md; evals/ stay local)"
for s in "${SKILL_NAMES[@]}"; do
  cp_one "skills/$s/SKILL.md"
done
echo

# ----------------------- 2. token replacement dictionary -----------------------
#
# Safe global replacements — these tokens are unambiguous everywhere they
# appear. Edit this list when you discover a new recurring real-name leak.
#
# Each entry: PATTERN|REPLACEMENT|HUMAN_LABEL  (separator = "|")
# Pattern uses Perl regex (run via `perl -i -pe`).

declare -a REPLACE_PAIRS=(
  # iOS Business modules (real project) → <ModuleType> placeholders
  'TDChat\b|<ChatModule>|TDChat → <ChatModule>'
  'TDProfile\b|<ProfileModule>|TDProfile → <ProfileModule>'
  'TDDevices\b|<DevicesModule>|TDDevices → <DevicesModule>'
  'TDOnBoarding\b|<OnboardingModule>|TDOnBoarding → <OnboardingModule>'
  'TDTasks\b|<TasksModule>|TDTasks → <TasksModule>'
  'TDSkills\b|<SkillsModule>|TDSkills → <SkillsModule>'
  'TDToday\b|<TodayModule>|TDToday → <TodayModule>'
  'TDChannels\b|<ChannelsModule>|TDChannels → <ChannelsModule>'
  'TDConnectors\b|<ConnectorsModule>|TDConnectors → <ConnectorsModule>'

  # Common packages → placeholders
  'TodayCore\b|<CoreModule>|TodayCore → <CoreModule>'
  'TodayFoundation\b|<FoundationModule>|TodayFoundation → <FoundationModule>'
  'TodayNetworking\b|<NetworkingModule>|TodayNetworking → <NetworkingModule>'
  'TodayAuth\b|<AuthModule>|TodayAuth → <AuthModule>'
  'TodayTheme\b|<DesignSystemPackage>|TodayTheme → <DesignSystemPackage>'
  'TodayUI\b|<UIModule>|TodayUI → <UIModule>'
  'TodayRouter\b|<MyAppRouter>|TodayRouter → <MyAppRouter>'
  'TodayTelemetry\b|<TelemetryModule>|TodayTelemetry → <TelemetryModule>'
  'TodayCloudKit\b|<CloudKitModule>|TodayCloudKit → <CloudKitModule>'
  'TodayTools\b|<SystemToolsModule>|TodayTools → <SystemToolsModule>'
  'ThemeImageManager\b|<ImageRegistry>|ThemeImageManager → <ImageRegistry>'

  # iOS scheme / workspace / bundle (real → placeholder)
  'TodayiOS\b|<YourApp>iOS|TodayiOS scheme → <YourApp>iOS'
  'Today\.xcworkspace|<YourApp>.xcworkspace|Today.xcworkspace → <YourApp>.xcworkspace'
  'Today\.app|<YourApp>.app|Today.app → <YourApp>.app'

  # Project name / monorepo
  'today-platform-apple|某 iOS monorepo|today-platform-apple → 某 iOS monorepo'
)

apply_replace() {
  local pattern="$1"
  local replacement="$2"
  local label="$3"
  local files
  files=$(grep -rlE "$pattern" "$CWD/core/" 2>/dev/null || true)
  if [[ -z "$files" ]]; then return; fi
  local count
  count=$(echo "$files" | wc -l | tr -d ' ')
  if [[ "$DRY_RUN" == 1 ]]; then
    log "  WOULD REPLACE: $label  ($count file(s))"
  else
    echo "$files" | xargs perl -i -pe "s|$pattern|$replacement|g"
    log "  replace: $label  ($count file(s))"
  fi
}

log "==> Applying token replacement dictionary"
for entry in "${REPLACE_PAIRS[@]}"; do
  IFS='|' read -r pat repl lbl <<< "$entry"
  apply_replace "$pat" "$repl" "$lbl"
done
echo

# ----------------------- 3. flag locations needing MANUAL review -----------------------
#
# These patterns can't be safely auto-replaced because the right fix depends on
# surrounding context. The script lists them; the agent / human edits.

flag_manual() {
  local pattern="$1"
  local label="$2"
  local hint="$3"
  local hits
  hits=$(grep -rnE "$pattern" "$CWD/core/agents" "$CWD/core/rules" "$CWD/core/skills" 2>/dev/null || true)
  if [[ -z "$hits" ]]; then return; fi
  echo
  warn "$label — $hint"
  echo "$hits" | sed 's|^|    |'
}

log "==> Locations that need MANUAL review (script can't safely auto-replace these)"
flag_manual 'just (build|test|check|fix|generate|lint|format)' \
  'hardcoded `just X` build/lint command' \
  'replace with `<your X recipe>` + parenthetical example (PR #6 pattern). KEEP as example when already wrapped by a `<your X recipe>` placeholder.'
flag_manual 'image-assets\.md' \
  '`image-assets.md` reference' \
  'pele does NOT ship this rule (it lives in the project repo). Remove the line and replace any prose mentioning TodayTheme/ThemeImageManager with abstract "<DesignSystemPackage> + <ImageRegistry>" wording (PR #6 pattern).'
flag_manual 'apps/ios-app/' \
  'project-specific path `apps/ios-app/...`' \
  'genericize or remove. xcodebuild example commands should use `-workspace <YourApp>.xcworkspace` not a hardcoded project path.'
flag_manual '~/Developer/pele/' \
  '`~/Developer/pele/` checkout path' \
  'replace with `<pele-checkout>` unless the line is explaining the default value (PR #7 pattern).'
flag_manual 'JDStatusBarNotification|TodayVoiceCodec|TodayAEX|TodayMacNativeBridge|TGUIKit' \
  'less common Today/TD module not in the dictionary' \
  'add a new line to REPLACE_PAIRS at the top of this script and re-run, or hand-edit the file.'

echo

# ----------------------- 4. final privacy scan -----------------------

log "==> Final privacy scan"
SENSITIVE='today-platform-apple|TDChat\b|TDProfile|TDDevices|TDOnBoarding|TDTasks|TDSkills\b|TDToday|TDChannels|TDConnectors|TodayCore|TodayUI\b|TodayTheme|TodayNetworking|TodayAuth|TodayRouter|TodayTelemetry|TodayCloudKit|TodayFoundation|TDModel|TDCache|TDAPISet|JDStatusBarNotification|TodayiOS|Today\.xcworkspace|TodayiOS\.xcodeproj|Today\.app|ThemeImageManager|TodayTools'
remaining=$(grep -rnE "$SENSITIVE" "$CWD/core/" "$CWD/README.md" "$CWD/docs/" 2>/dev/null || true)
if [[ -n "$remaining" ]]; then
  warn "Still seeing project-internal names — these slipped past the dictionary:"
  echo "$remaining" | sed 's|^|    |'
  echo
  log "Add the missing patterns to REPLACE_PAIRS in this script and re-run, or hand-edit."
else
  log "  ✓ No project-internal names found"
fi
echo

# ----------------------- 5. next steps for the agent / maintainer -----------------------

log "==> Next steps (the script's first pass is NOT the whole job)"
cat <<'EOF'
  1. Review `git diff` end-to-end. Token replacement is mechanical and can't
     judge whether a paragraph still reads correctly after the substitution.
  2. Address every MANUAL-review entry flagged above. The common pattern: an
     agent SOP says "iOS 改动：`just build-ios`" — that needs to become
     "iOS 改动：`<your iOS build recipe>`（如 `just build-ios` / `xcodebuild
     ... build`）". See PR #6 commits for the full playbook.
  3. Re-run the final privacy scan command shown above. It should print 0 hits.
  4. If you found a NEW recurring leak, add it to REPLACE_PAIRS at the top of
     this script so the next sync handles it automatically.
  5. Commit (1 commit is usually fine for a sync, but split into 2 if you also
     introduced a new workflow concept upstream — see PR #8 split rationale).
  6. Push + PR. Sync PRs are titled `feat(spec): ... + re-decouple` or
     `chore(sync): pull from local ~/.claude`.

  Reference PRs:
    #4  initial 3-skill extraction        #7  ~/Developer/pele → <pele-checkout>
    #5  use-worktree rule → skill         #8  §9 Amendments workflow + re-decouple
    #6  decouple just / Today* names

  Full SOP: docs/sync-from-local.md
EOF
