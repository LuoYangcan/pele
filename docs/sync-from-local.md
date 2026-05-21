# Sync from local ~/.claude/ — Maintainer SOP

Pele is a **deliberate fork**: the maintainer's `~/.claude/` is the day-to-day working copy and accumulates personal additions (per-project rules, language-specific rules, project-specific commands, project-specific build skills). The published `pele/core/` only ships the universal subset that any user can install on any project. This doc describes how to push improvements from the personal version into the public version without leaking personal additions in.

If you're reading this as an agent: **`scripts/sync-from-local.sh` does the mechanical first pass; you still have to scan the result.** The script is a labor-saver, not a replacement for your eyes.

## The boundary: what ships vs what stays personal

Pele's core is **project-neutral**. It contains no real project names, no hardcoded build commands, no language-specific rules. Everything in your personal `~/.claude/` that violates that contract stays personal and is not synced.

| In `~/.claude/` | Ships in pele? | Why |
|---|---|---|
| `CLAUDE.md` | Yes | Global index — must stay project-neutral |
| `agents/{generator,executor,planner,ui-reviewer}.md` | Yes | Core subagent contracts |
| `rules/{dispatch-pipeline,spec-before-code,iteration-checkpoint,parallel-subagents,post-change-verify}.md` | Yes | Universal workflow rules |
| `templates/*.md` | Yes | Spec / feedback templates |
| `skills/{scan-trigger-docs,lean-diff,use-worktree,architecture-first,dead-code}/SKILL.md` | Yes | Universal skills |
| `skills/*/evals/` | **No** | Test fixtures may contain real project names |
| `rules/commit-message.md` | **No** | Personal trailer-policy preference, not universal |
| `rules/swift-formatting.md` | **No** | Language-specific, not universal |
| `rules/image-assets.md`, `rules/logging-pii.md`, `rules/viewcontroller-split.md`, `rules/nse-dependencies.md`, etc. | **No** | Project-level rules, live in the maintainer's project repo |
| `skills/find-ios-build-artifact/`, other iOS-specific skills | **No** | Project / platform specific |
| `commands/<project-specific>.md` | **No** | Maintainer-specific slash commands |

The script's file list reflects this — extend it when pele starts shipping a new file family or when you add a new personal-only rule that the script should skip.

## When to sync

Trigger:

- The maintainer says "the harness updated, sync it" or "my subagents updated"
- A diff check shows `~/.claude/agents/*.md` ≠ `pele/core/agents/*.md` (or similar for shared rules / skills / templates / CLAUDE.md)
- You finish a workflow improvement directly in `~/.claude/` and need to publish it

Don't trigger for:

- Changes to personal-only files (the "**No**" rows in the table above)
- Changes inside `~/.claude/skills/*/evals/` (gitignored)

## Step-by-step

### 1. Diff first to confirm there's actually something to sync

```bash
cd <pele-checkout>
git fetch origin
for f in agents/generator.md agents/executor.md agents/planner.md agents/ui-reviewer.md rules/dispatch-pipeline.md CLAUDE.md; do
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

1. **Copy** the files listed in its file lists (`TOP_LEVEL_FILES` / `AGENT_FILES` / `RULE_FILES` / `SKILL_FILES` / `TEMPLATE_FILES`) from `~/.claude/` into `core/`
2. **Skip** files that are personal-only (the script's lists deliberately exclude them; if you add a new personal rule, do **not** add it to the script's lists)
3. **Flag locations that need manual review** — anything mentioning real project names, hardcoded commands, or referencing personal-only rules
4. **Final privacy grep** — reports any remaining project-internal names

### 4. Manual review

The script writes a list of `[sync] ⚠️` warnings. For each one, decide:

- **Personal content leaked into a shared file** → rewrite the line to be project-neutral (talk about "the project's build / lint / test command" generically; let agents discover the actual command from `Justfile` / `package.json` / `Cargo.toml` / `Makefile` / project `AGENTS.md`)
- **Reference to a personal-only rule** (e.g. shared `generator.md` mentions `image-assets.md`) → either rewrite to be project-neutral, or drop the reference if it doesn't serve universal users
- **New personal pattern not in the script's skip list** → hand-edit this round's file, then update the script's `flag_manual` patterns so the next sync catches it. Commit the script update alongside the sync — same PR is fine

### 5. Final privacy scan as a tripwire

Maintain a `SENSITIVE` regex of your own real project names + your own build commands (kept in your personal notes, not in this repo), then:

```bash
SENSITIVE='<your-project-name>|<your-module-prefix>|<your-build-recipe>|...'
grep -rEn "$SENSITIVE" core/ README.md docs/ && echo "⚠️ still leaks" || echo "✓ clean"
```

This should print "✓ clean" before you commit. The `SENSITIVE` list lives outside pele on purpose — listing your real project markers inside `pele/core/` would itself be a leak. Keep the regex in a personal note / dotfile / scratch script.

### 6. Commit

For pure sync (no new upstream workflow concept):

```
chore(sync): pull subagents / rules from local ~/.claude
```

For sync **+** new upstream concept (e.g. PR #8 introduced §9 Amendments along with re-decoupling):

```
feat(<thing>): <new concept>
```

Split into 2 commits if the diff would be hard to review otherwise — but 1 commit is fine when the sync is small.

### 7. Push + PR

Standard pele PR workflow. Description should list:

- What changed upstream (the substantive content)
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
| [#8](https://github.com/LuoYangCan/pele/pull/8) | §9 Amendments workflow |

## Why the script can't do all of it

A purely-automated script would be tempting but wrong. Two reasons:

1. **New personal patterns**: When the maintainer adds a new personal rule, command, or skill that the script doesn't know about yet, only manual diff review catches it. The script's `flag_manual` patterns lag behind the maintainer's local additions.
2. **Context-sensitive prose**: A shared rule might mention a personal-only rule in passing ("see `image-assets.md` for how this project handles icons"). Removing the reference cleanly requires understanding the surrounding paragraph, which a regex can't do reliably.

So the design is: **script handles the boring 80% (copy the shared files, skip the personal ones, flag suspicious patterns), agent / maintainer handles the 20% that requires judgment.** That 20% is also where the script's flagging patterns get *updated* — making the script smarter over time.
