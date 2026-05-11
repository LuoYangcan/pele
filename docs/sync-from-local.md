# Sync from local ~/.claude/ — Maintainer SOP

Pele is a **deliberate fork**: the maintainer's `~/.claude/` is personalized (real project names like `TodayiOS`, `just build-ios`, `~/Developer/pele/`), while the published `pele/core/` is decoupled (placeholders like `<YourApp>iOS`, `<your iOS build recipe>`, `<pele-checkout>`) so any user can install pele on any project. This doc describes how to push improvements from the personal version into the public version without leaking project-internal names back in.

If you're reading this as an agent: **`scripts/sync-from-local.sh` does the mechanical first pass; you still have to scan the result.** The script is a labor-saver, not a replacement for your eyes.

## When to sync

Trigger:

- The maintainer says "the harness updated, sync it" or "my subagents updated"
- A diff check shows `~/.claude/agents/*.md` ≠ `pele/core/agents/*.md` (or similar for rules / skills / templates / CLAUDE.md)
- You finish a workflow improvement directly in `~/.claude/` and need to publish it

Don't trigger for:

- Changes to project-specific rules that don't ship with pele (e.g. `~/.claude/rules/image-assets.md` belongs to the maintainer's project repo, not to pele)
- Changes inside `~/.claude/skills/*/evals/` (gitignored — these contain real test cases that may leak project structure)

## What pele ships, what stays personal

| File in `~/.claude/` | Ships in pele? | Why |
|---|---|---|
| `CLAUDE.md` | Yes | Global index, must be decoupled |
| `agents/{generator,executor,planner}.md` | Yes | Core subagent contracts |
| `rules/{dispatch-pipeline,spec-before-code,iteration-checkpoint,parallel-subagents,post-change-verify,commit-message,swift-formatting,use-worktree}.md` | Yes | Public workflow rules |
| `templates/*.md` | Yes | Spec / feedback templates |
| `skills/{scan-trigger-docs,lean-diff,find-ios-build-artifact,use-worktree,architecture-first,dead-code}/SKILL.md` | Yes | Public skills |
| `skills/*/evals/` | **No** | Test fixtures may contain real project names |
| `rules/image-assets.md` | **No** | Lives in the maintainer's project repo, not in pele |
| `rules/logging-pii.md`, `rules/viewcontroller-split.md`, `rules/nse-dependencies.md`, etc. | **No** | Same — project-level rules, not portable |
| `commands/<project-specific>.md` | **No** | Maintainer-specific slash commands |

The script's file list reflects this — extend it when pele starts shipping a new file family.

## Step-by-step

### 1. Diff first to confirm there's actually something to sync

```bash
cd <pele-checkout>
git fetch origin
for f in agents/generator.md agents/executor.md agents/planner.md rules/dispatch-pipeline.md CLAUDE.md; do
  diff -q ~/.claude/$f core/$f && echo "  $f: same" || echo "  $f: DIFFERS"
done
```

If everything says `same`, there's nothing to sync — stop.

### 2. Open a sync worktree (never sync on main)

```bash
cd <pele-checkout>
git worktree add .worktrees/sync-N -b chore/sync-from-local-N origin/main
cd .worktrees/sync-N
mkdir -p .specs && touch .specs/sync-N.skip   # spec-before-code bypass; this is meta work
```

### 3. Run the script

```bash
../../scripts/sync-from-local.sh --dry-run   # see what would change
../../scripts/sync-from-local.sh             # do it
```

The script does:

1. **Copy** ~/.claude/{agents,rules,templates,skills}/* into core/ (only the files listed in `TOP_LEVEL_FILES` / `AGENT_FILES` / etc. — see the script)
2. **Apply token replacement** for unambiguous real-name → placeholder mappings (TodayiOS → \<YourApp\>iOS, TDChat → \<ChatModule\>, etc.)
3. **Flag locations that need manual review** — paragraph-level rewrites the script can't safely do mechanically
4. **Final privacy grep** — reports any remaining project-internal names

### 4. Manual review (this is where the agent / human still earns their keep)

The script writes a list of `[sync] ⚠️` warnings. For each one:

#### `just X` hardcode

Pattern: SOP says something like `iOS 改动: \`just build-ios\``.
Fix: replace with `<your iOS build recipe>` + parenthetical example. See PR #6 for the precise hunk pattern. If the line **already** has `<your X recipe>` and the `just X` is inside `(如 ... )` parens, **leave it** — that's the established "placeholder with example" pattern.

#### `image-assets.md` reference

Pele does NOT ship this rule (it lives in the maintainer's project repo). The reference is a dangling link for downstream users.
Fix: remove the line. If surrounding prose mentions `TodayTheme` + `ThemeImageManager`, rewrite to abstract `<DesignSystemPackage>` + `<ImageRegistry>` wording (PR #6 set the precedent).

#### `apps/ios-app/...` path hardcode

Project-specific path that won't apply elsewhere.
Fix: replace with a generic example using `-workspace <YourApp>.xcworkspace` etc., or drop the path entirely if the context is just illustrative.

#### `~/Developer/pele/` path

Allowed only when explaining the default value (e.g. "defaults to `~/Developer/pele/`, override with `PELE_INSTALL_DIR=`"). Anywhere else → replace with `<pele-checkout>`. PR #7 set this precedent.

#### A new pattern not in the dictionary

If you see a recurring real-name leak the script didn't catch (e.g. a new Today module that hasn't been added to the dictionary):

1. Hand-edit this round's file
2. **Add a line to `REPLACE_PAIRS` at the top of `scripts/sync-from-local.sh`** so the next sync handles it
3. Commit the dictionary update alongside the sync — same PR is fine

### 5. Re-run the final privacy scan as a tripwire

```bash
SENSITIVE='today-platform-apple|TDChat\b|TDProfile|TDDevices|TDOnBoarding|TDTasks|TDSkills\b|TDToday|TDChannels|TDConnectors|TodayCore|TodayUI\b|TodayTheme|TodayNetworking|TodayAuth|TodayRouter|TodayTelemetry|TodayCloudKit|TodayFoundation|TDModel|TDCache|TDAPISet|JDStatusBarNotification|TodayiOS|Today\.xcworkspace|TodayiOS\.xcodeproj|Today\.app|ThemeImageManager|TodayTools'
grep -rEn "$SENSITIVE" core/ README.md docs/ && echo "⚠️ still leaks" || echo "✓ clean"
```

This should print "✓ clean" before you commit.

### 6. Commit

For pure sync (no new upstream workflow concept):

```
chore(sync): pull subagents / rules from local ~/.claude
```

For sync **+** new upstream concept (e.g. PR #8 introduced §9 Amendments along with re-decoupling):

```
feat(<thing>): <new concept> + re-decouple agents
```

Split into 2 commits if the diff would be hard to review otherwise (e.g. "first commit pulls in the new content, second commit re-applies placeholders") — but 1 commit is fine when the sync is small.

### 7. Push + PR

Standard pele PR workflow. Description should list:

- What changed upstream (the substantive content)
- That re-decoupling was applied (so reviewer knows the placeholder churn isn't gratuitous)
- The final privacy-scan result (`0 hits`)

After merge, clean up:

```bash
cd <pele-checkout>
git worktree remove .worktrees/sync-N
git branch -D chore/sync-from-local-N
git push origin --delete chore/sync-from-local-N
git checkout main && git pull --ff-only
```

## Reference PRs

| PR | Sync subject |
|---|---|
| [#4](https://github.com/LuoYangCan/pele/pull/4) | First extraction of 3 shared skills (`scan-trigger-docs` / `lean-diff` / `find-ios-build-artifact`) |
| [#5](https://github.com/LuoYangCan/pele/pull/5) | `use-worktree` rule → skill |
| [#6](https://github.com/LuoYangCan/pele/pull/6) | First systematic decoupling: `just X` / `Today*` / `TD*` → placeholders. **This PR's commit is the canonical reference for the token replacement playbook** |
| [#7](https://github.com/LuoYangCan/pele/pull/7) | `~/Developer/pele/` → `<pele-checkout>` |
| [#8](https://github.com/LuoYangCan/pele/pull/8) | §9 Amendments workflow + re-decoupling (because the upstream version had regressed PR #6's work) |

## Why the script can't do all of it

A purely-automated script would be tempting but wrong. Three reasons:

1. **Context-sensitive rewrites**: `just build-ios` should become `<your iOS build recipe>` only when it's hardcoded as **the** build command. When it appears inside a parenthetical example list (`(如 just build-ios / xcodebuild ... / cargo build)`), it must stay — it's serving as a hint for what placeholders might mean. A regex can't distinguish those two roles reliably.
2. **Dangling references**: Removing `image-assets.md` reference isn't just deleting the line — surrounding prose ("严格按 `image-assets.md` 放 TodayTheme") needs paragraph-level rewriting to "项目自己的图片资源约定（如有；例 `<DesignSystemPackage>` + `<ImageRegistry>`）". The script can flag, not fix.
3. **New patterns**: When the maintainer invents a new workflow concept (like §9 Amendments) or a new module name, the script doesn't know about it yet. The flagging output catches "anything matching SENSITIVE that isn't in the dictionary" so it's visible.

So the design is: **script handles the boring 80%, agent / maintainer handles the 20% that requires judgment.** That 20% is also where the script's `REPLACE_PAIRS` and `flag_manual` lists get *updated* — making the script smarter over time.
