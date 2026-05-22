# Pele

> Volcanic harness for Claude Code — opinionated rules, agents, and workflow that turn the main model into a dispatcher.

Pele is a set of global Claude Code rules, subagents, slash commands, and hooks distilled from real day-to-day use. The signature piece is a **three-stage dispatch pipeline** (`planner` → `generator` → `executor`) that keeps the main agent as a coordinator and offloads code-writing, review, and verification to specialized subagents — each running in an isolated context.

Named after [Pele](https://en.wikipedia.org/wiki/Pele_(deity)), the Hawaiian volcano goddess: she controls the eruption.

## What you get

Drop-in install adds the following under `~/.claude/`:

| Layer | Contents |
|---|---|
| **CLAUDE.md** | Top-level index that progressively discloses rules / skills / agents on demand |
| **rules/** | `dispatch-pipeline` · `spec-before-code` · `iteration-checkpoint` · `parallel-subagents` · `post-change-verify` (`use-worktree` is now a skill — see below; `rules/use-worktree.md` is a stub redirect) |
| **agents/** | `planner` · `generator` · `executor` (the three-stage pipeline) |
| **commands/** | `/openpr` · `/review` · `/pr-review` |
| **skills/** | `use-worktree` (new-topic worktree isolation; full SOP for fetch / branch / project init steps) · `architecture-first` (pattern / architecture selection before adding abstraction) · `dead-code` (zombie-symbol scanner for recent diff via LSP `findReferences` + grep, with optional Periphery fast-path for Swift projects; auto-cleanup hook in `generator` Step 4.5) · `scan-trigger-docs` (read project AGENTS.md trigger-on-touch docs; shared by all three subagents) · `lean-diff` (single source of truth for verbose-comment / patchwork-bloat / silent-catch judgments — write mode for `generator`, review mode for `executor`) |
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

The bootstrap script clones the repo to `<pele-checkout>` (defaults to `~/Developer/pele/`, override with `PELE_INSTALL_DIR=<path>` before piping to bash) and runs `./install.sh`. Pass flags after `--` :

```bash
curl -fsSL https://raw.githubusercontent.com/LuoYangCan/pele/main/scripts/bootstrap.sh | bash -s -- --figma

# Install to a non-default location:
PELE_INSTALL_DIR=~/code/pele curl -fsSL https://raw.githubusercontent.com/LuoYangCan/pele/main/scripts/bootstrap.sh | bash
```

### Manual (git clone)

```bash
git clone https://github.com/LuoYangCan/pele.git <pele-checkout>   # e.g. ~/Developer/pele, ~/code/pele, anywhere
cd <pele-checkout>
./install.sh             # global mode (default) — symlinks into ~/.claude/
./install.sh --figma     # + Figma extras
./install.sh --dry-run   # see what would change without touching anything
```

`install.sh` auto-detects its own location, so `<pele-checkout>` can be anywhere — it doesn't have to be `~/Developer/pele/`. Throughout this doc `<pele-checkout>` is a placeholder for wherever you put the repo.

### Install modes

Pele supports two mutually-exclusive install modes:

#### Global (`--global`, default)

Symlinks `core/` into `~/.claude/`. Pele's rules / agents / skills apply across every project Claude Code opens on this machine.

```bash
./install.sh             # equivalent to ./install.sh --global
```

#### Project (`--project <path>`)

Symlinks `core/` into `<path>/.claude/`. Pele's rules / agents / skills only apply when Claude Code opens that one project. Use this when you want to try pele on a single repo without affecting your global setup, or when different repos need different harness versions.

```bash
./install.sh --project /path/to/your-project
./install.sh --project /path/to/your-project --dry-run
```

After install, **manually add this line** to the end of `<path>/CLAUDE.md` (or `<path>/AGENTS.md`):

```
@.claude/rules/index.md
```

Pele installs `<path>/.claude/rules/index.md` as the entry point — but `install.sh` deliberately does **not** modify your `CLAUDE.md` / `AGENTS.md`. Without that one `@` line, Claude Code won't pick up the index automatically.

Pass `--figma` to either mode for the Figma extras.

### What install does

1. **Symlinks** `core/` (and `--figma` content if enabled) into the target `.claude/` directory — `~/.claude/` in global mode, `<path>/.claude/` in project mode. Editing files in `<pele-checkout>/core/...` takes effect immediately — no reinstall needed.
2. **Backs up** any pre-existing files in the target directory to `<target>.backup-<timestamp>/` before linking. Nothing is destroyed.
3. **Merges hooks** into the target `settings.json` using `jq`. Your `model`, `mcpServers`, `permissions`, and other keys are preserved. The pre-merge `settings.json` is also backed up.

   For an optional starter set of recommended permissions (e.g. an `mcp__ios-simulator__*` allow-list so the executor's iOS UI smoke steps don't prompt for each tool call), see `core/permissions/settings.permissions.json` and copy the entries you want into your target `settings.json`'s `permissions.allow` array. This file is **not** auto-merged.

### Requirements

- macOS / Linux (zsh or bash)
- `git`, `jq` (for hook merging — optional but recommended)
- [Claude Code](https://docs.anthropic.com/claude/docs/claude-code) installed

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

Pele uses **symlinks**, so you customize by editing the source files in `<pele-checkout>`:

- Add a new rule → `core/rules/<name>.md` + add an entry to `core/CLAUDE.md` index
- Add a new subagent → `core/agents/<name>.md`, then reference it from a rule (e.g. `dispatch-pipeline.md`)
- Add a slash command → `core/commands/<name>.md`
- Add project-specific hooks → edit `~/.claude/settings.json` directly (your edits are preserved across re-installs as long as you don't touch the `.hooks` key Pele manages)
- Add recommended permissions → edit `core/permissions/settings.permissions.json`, then copy entries into your `~/.claude/settings.json`'s `permissions.allow` (this file is not auto-merged by `install.sh`)
- Disable a rule → just delete the symlink in `~/.claude/rules/` (or the source file in `<pele-checkout>/core/rules/`); the index in `CLAUDE.md` is progressive-disclosure, missing files are silently ignored

For project-specific overrides (per-repo CLAUDE.md, per-repo hooks), use the standard Claude Code mechanisms in `<repo>/.claude/` — they layer on top of pele's globals.

## Maintainer: syncing personal `~/.claude/` → public `pele/core/`

If you maintain a fork of pele (or you are the original maintainer), you'll iterate on `~/.claude/` locally — and your local copy includes personal additions that don't belong in the public release: per-project rules (image-assets, viewcontroller-split, logging-pii), language-specific rules (commit-message trailer policy, swift-formatting), project-specific commands, project-specific build skills (iOS build artifact lookup). Periodically push the **shared** improvements back into the public `core/` while leaving the personal parts behind.

`scripts/sync-from-local.sh` automates the mechanical part: it `cp`s the files that pele actually ships and skips the ones that are personal. It's a first-pass tool — you still scan the diff for personal content that slipped through.

```bash
cd <pele-checkout>
git fetch origin
git worktree add .worktrees/sync-N -b chore/sync-from-local-N origin/main
cd .worktrees/sync-N
../../scripts/sync-from-local.sh --dry-run   # preview
../../scripts/sync-from-local.sh             # do it
# … manual review for personal content that slipped through, then commit + PR
```

Full SOP — what ships vs what stays personal, step-by-step, and why the script can't do everything — is in **[docs/sync-from-local.md](docs/sync-from-local.md)**.

## Upgrade / Reinstall

If you installed an earlier version of pele and are picking up changes (new rules, renamed skills, deleted files), reinstall in three steps from your existing `<pele-checkout>`:

```bash
cd <pele-checkout>
git pull origin main          # pull the new pele
./uninstall.sh                # global mode — also clears stale symlinks for deleted files
./install.sh                  # rebuild symlinks against the new layout
#  ./uninstall.sh --project /path/to/your-project && ./install.sh --project /path/to/your-project   (project mode equivalent)
```

`uninstall.sh` walks every symlink under the target `.claude/` and removes any that points into `<pele-checkout>` — including symlinks whose target file no longer exists (e.g. `~/.claude/rules/commit-message.md` → `<pele-checkout>/core/rules/commit-message.md` after that source file is deleted upstream). This is why running `uninstall.sh` before `install.sh` is recommended for upgrades, not just for full removal.

If you hand-added pele-related lines into `~/.claude/CLAUDE.md` (or `<your-project>/CLAUDE.md` for project mode) — for instance an index entry like `[commit-message](rules/commit-message.md)` or `[swift-formatting](rules/swift-formatting.md)` for rules that have since been removed from pele — those lines were never managed by `install.sh` and won't be cleaned up automatically. Grep your `CLAUDE.md` for references to deleted files and remove them manually:

```bash
grep -nE 'commit-message|swift-formatting|find-ios-build-artifact' ~/.claude/CLAUDE.md
```

## Uninstall

```bash
<pele-checkout>/uninstall.sh                                # global mode
<pele-checkout>/uninstall.sh --project /path/to/your-project   # project mode
```

Removes every symlink in the target `.claude/` directory that points into `<pele-checkout>`. Does **not** auto-restore from `<target>.backup-*/` — those are kept for you to restore manually if needed:

```bash
# Global mode example
cp ~/.claude.backup-<timestamp>/.claude/CLAUDE.md ~/.claude/CLAUDE.md
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
- **Project-neutral by construction**: pele ships with no real project names, no hardcoded build commands, no language-specific rules. When a rule needs to talk about "the project's build / lint / test command", it stays generic — agents discover the actual command from the project's `Justfile` / `package.json` / `Cargo.toml` / `Makefile` / `AGENTS.md`, or ask the user.

## License

MIT — see [LICENSE](LICENSE).

## Credits

Inspired by months of working with Claude Code on a real-world codebase. The structure is debt repayment for everything that's gone wrong: forgetting to clarify, drifting mid-implementation, mock tests passing while prod broke, "I'll fix the spec later", and so on.

Pele has eruptions. Channel them.
