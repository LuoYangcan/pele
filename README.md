# Pele

> Volcanic harness for Claude Code — opinionated rules, agents, and workflow that turn the main model into a dispatcher.

Pele is a set of global Claude Code rules, subagents, slash commands, and hooks distilled from real day-to-day use. The signature piece is a **three-stage dispatch pipeline** (`planner` → `generator` → `executor`) that keeps the main agent as a coordinator and offloads code-writing, review, and verification to specialized subagents — each running in an isolated context.

Named after [Pele](https://en.wikipedia.org/wiki/Pele_(deity)), the Hawaiian volcano goddess: she controls the eruption.

## What you get

Drop-in install adds the following under `~/.claude/`:

| Layer | Contents |
|---|---|
| **CLAUDE.md** | Top-level index that progressively discloses rules / skills / agents on demand |
| **rules/** | `dispatch-pipeline` · `use-worktree` · `spec-before-code` · `iteration-checkpoint` · `parallel-subagents` · `post-change-verify` · `commit-message` · `swift-formatting` |
| **agents/** | `planner` · `generator` · `executor` (the three-stage pipeline) |
| **commands/** | `/openpr` · `/review` · `/pr-review` |
| **skills/** | `architecture-first` (pattern / architecture selection before adding abstraction) · `dead-code` (Periphery-backed zombie-symbol scanner for recent diff, with auto-cleanup hook in `generator` Step 4.5) · `scan-trigger-docs` (read project AGENTS.md trigger-on-touch docs; shared by all three subagents) · `lean-diff` (single source of truth for verbose-comment / patchwork-bloat / silent-catch judgments — write mode for `generator`, review mode for `executor`) · `find-ios-build-artifact` (locate iOS Simulator `.app` + bundle id via `xcodebuild -showBuildSettings`; used by `executor` UI smoke + project-level `open-sim`) |
| **templates/** | `spec-template.md` (the structure planner writes) |
| **hooks/** | Protected-branch guard · `spec-before-code` enforcement · per-prompt clarification reminder |
| **permissions/** | `settings.permissions.json` — recommended `permissions.allow` entries (e.g. `mcp__ios-simulator__*`). **Not auto-merged** by `install.sh`; copy entries into your settings manually |

Optional extras (gated by install flags):

- `--figma` — Figma MCP `PreToolUse` hook that asks Claude to clarify ambiguous static designs before generating code

## Install

### One-liner (curl)

```bash
curl -fsSL https://raw.githubusercontent.com/LuoYangCan/pele/main/scripts/bootstrap.sh | bash
```

The bootstrap script clones the repo to `~/Developer/pele/` and runs `./install.sh`. Pass flags after `--` :

```bash
curl -fsSL https://raw.githubusercontent.com/LuoYangCan/pele/main/scripts/bootstrap.sh | bash -s -- --figma
```

### Manual (git clone)

```bash
git clone https://github.com/LuoYangCan/pele.git ~/Developer/pele
cd ~/Developer/pele
./install.sh             # core only
./install.sh --figma     # + Figma extras
./install.sh --dry-run   # see what would change without touching anything
```

### What install does

1. **Symlinks** `core/` (and `--figma` content if enabled) into `~/.claude/`.
   Editing files in `~/Developer/pele/core/...` takes effect immediately — no reinstall needed.
2. **Backs up** any pre-existing files in `~/.claude/` to `~/.claude.backup-<timestamp>/` before linking. Nothing is destroyed.
3. **Merges hooks** into `~/.claude/settings.json` using `jq`. Your `model`, `mcpServers`, `permissions`, and other keys are preserved. The pre-merge `settings.json` is also backed up.

   For an optional starter set of recommended permissions (e.g. an `mcp__ios-simulator__*` allow-list so the executor's iOS UI smoke steps don't prompt for each tool call), see `core/permissions/settings.permissions.json` and copy the entries you want into your `~/.claude/settings.json`'s `permissions.allow` array. This file is **not** auto-merged.

### Requirements

- macOS / Linux (zsh or bash)
- `git`, `jq` (for hook merging — optional but recommended)
- [Claude Code](https://docs.anthropic.com/claude/docs/claude-code) installed

## After install: customize for your project

> ⚠️ **Some rule files contain placeholders** like `<YourApp>` and `<your build recipe>`. They're project-specific defaults that you should review and replace, otherwise Claude will see the literal `<YourApp>` text in your rules.

Pele's rule files use placeholders for project-specific paths and commands so the same rules can apply to any project. After install, **edit the placeholders in your `~/Developer/pele/` checkout** to match your project. Since `~/.claude/` is symlinked to it, your edits take effect immediately — no reinstall needed.

Common placeholders:

| Placeholder | Meaning | Replace with (example) |
|---|---|---|
| `<YourApp>` | Your iOS app name (workspace + scheme stem) | `Acme`, `MyApp` |
| `<YourApp>iOS` | Your iOS scheme name | `AcmeiOS` |
| `<your-monorepo>` | Your repo / monorepo name | `acme-platform-apple` |
| `<your build recipe>` | Your build command | `just build-ios`, `make build`, `npm run build` |
| `<DesignSystemPackage>` | Your shared theme / design package | `AcmeTheme`, `DesignKit` |
| `<ImageRegistry>` | Your image registry class (image-assets rule) | `ThemeImageManager`, `IconRegistry` |

**Find all placeholders in your installed rules:**

```bash
cd ~/Developer/pele
grep -rEn '<(YourApp|your-monorepo|your build recipe|DesignSystemPackage|ImageRegistry)' core/ --include='*.md'
```

**Bulk-replace one** (example: `<YourApp>` → `Acme`):

```bash
cd ~/Developer/pele
find core/ -name '*.md' -exec sed -i '' 's|<YourApp>|Acme|g' {} +
git diff   # review then commit if you want to track
```

If your project doesn't use the iOS-flavored examples at all (e.g. you're on a Node / Python / Rust stack), the rules referencing `<YourApp>iOS` etc. simply won't be triggered — Claude only `Read`s a rule when its trigger description matches the current task. You can leave them or delete the irrelevant rule files.

## The three-stage pipeline

The default behavior changes when you have a code-writing request:

```
You: "implement feature X"
   │
   ▼
[main agent]  not a coder anymore — just a dispatcher
   │
   ▼
[planner]   independent context, reads rules + writes
            .specs/<slug>.md (full spec: split / tests / acceptance / hard constraints)
   │
   ▼
[main agent] presents spec path to user → "ready to implement?"
   │
   ▼ user says yes
[generator] independent context, reads spec + writes code,
            stops + asks user when unsure (and flags spec-update)
   │
   ▼
[executor]  independent context, reads spec + reviews code,
            runs build + lint, optionally drives iOS simulator (--apple)
   │
   ▼
   PASS → main agent reports to user, you /openpr when ready
   FAIL → main agent loops back to generator with the issue list
          (max 3 retries, then escalates back to user)
```

Each subagent runs in its own context window — they cannot see each other's conversation history. They communicate **only** via `.specs/<slug>.md` and structured messages relayed by the main agent. This is by design: it forces specs to be a self-contained source of truth and prevents one agent's reasoning from leaking into another's review.

See `core/rules/dispatch-pipeline.md` for the full contract.

## Customize

Pele uses **symlinks**, so you customize by editing the source files in `~/Developer/pele/`:

- Add a new rule → `core/rules/<name>.md` + add an entry to `core/CLAUDE.md` index
- Add a new subagent → `core/agents/<name>.md`, then reference it from a rule (e.g. `dispatch-pipeline.md`)
- Add a slash command → `core/commands/<name>.md`
- Add project-specific hooks → edit `~/.claude/settings.json` directly (your edits are preserved across re-installs as long as you don't touch the `.hooks` key Pele manages)
- Add recommended permissions → edit `core/permissions/settings.permissions.json`, then copy entries into your `~/.claude/settings.json`'s `permissions.allow` (this file is not auto-merged by `install.sh`)
- Disable a rule → just delete the symlink in `~/.claude/rules/` (or the source file in `~/Developer/pele/core/rules/`); the index in `CLAUDE.md` is progressive-disclosure, missing files are silently ignored

For project-specific overrides (per-repo CLAUDE.md, per-repo hooks), use the standard Claude Code mechanisms in `<repo>/.claude/` — they layer on top of pele's globals.

## Uninstall

```bash
~/Developer/pele/uninstall.sh
```

Removes every symlink in `~/.claude/` that points into `~/Developer/pele/`. Does **not** auto-restore from `~/.claude.backup-*/` — those are kept for you to restore manually if needed:

```bash
# Restore your original CLAUDE.md
cp ~/.claude.backup-<timestamp>/.claude/CLAUDE.md ~/.claude/CLAUDE.md
# Restore the pre-merge settings.json
cp ~/.claude.backup-<timestamp>/settings.json.before-merge ~/.claude/settings.json
```

## Project layout

```
pele/
├── README.md
├── LICENSE
├── install.sh / uninstall.sh
├── scripts/
│   ├── bootstrap.sh         # used by the curl one-liner
│   └── check-spec.sh        # PreToolUse hook helper
├── core/                    # always installed
│   ├── CLAUDE.md
│   ├── rules/
│   ├── agents/
│   ├── commands/
│   ├── skills/
│   ├── templates/
│   ├── hooks/settings.hooks.json
│   └── permissions/settings.permissions.json   # recommended permissions, not auto-merged
├── figma-extras/            # --figma
│   └── hooks/settings.hooks.json
└── docs/
    └── architecture.md
```

## Design notes

- **Globals over per-project**: Rules / agents / hooks live in `~/.claude/`, not in each repo. Project-specific overrides go in `<repo>/.claude/` as usual.
- **Progressive disclosure**: `CLAUDE.md` is an *index*, not a manual. Each entry has a one-line trigger description so the model only `Read`s the body when it actually applies. Keeps context small.
- **Hard constraints via hooks**: Things that *must* happen (no Edit on `main`/`dev`, spec must exist before Edit in worktrees) are enforced as `PreToolUse` hooks — not as rule text the model can talk itself out of.
- **Independent contexts for subagents**: planner / generator / executor each run via the `Agent` tool with no shared memory. Spec files are the only handoff format.
- **Examples use placeholders**: Rule files use `<YourApp>`, `<your-monorepo>`, `<your build recipe>` etc. for project-specific paths and commands. Fork and edit — pele itself ships with no real-project identifiers.

## License

MIT — see [LICENSE](LICENSE).

## Credits

Inspired by months of working with Claude Code on a real-world codebase. The structure is debt repayment for everything that's gone wrong: forgetting to clarify, drifting mid-implementation, mock tests passing while prod broke, "I'll fix the spec later", and so on.

Pele has eruptions. Channel them.
