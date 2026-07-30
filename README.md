# Pele

> Volcanic harness for Claude Code — opinionated rules, agents, and workflow that turn the main model into a dispatcher.

Pele is a set of global Claude Code rules, subagents, slash commands, and hooks distilled from real day-to-day use. Its **three-stage dispatch pipeline** keeps the main agent as a coordinator: a Lead Planner publishes the spec (optionally through planner fan-out), then generator and executor implement and verify it in independent contexts.

Named after [Pele](https://en.wikipedia.org/wiki/Pele_(deity)), the Hawaiian volcano goddess: she controls the eruption.

## What you get

Drop-in install adds the following under `~/.claude/`:

| Layer | Contents |
|---|---|
| **CLAUDE.md** | Top-level index that progressively discloses rules / skills / agents on demand |
| **rules/** | Workflow stubs and policies, plus portable Swift/iOS guidance |
| **agents/** | `planner` · `planner-worker` · `spec-integrator` · `generator` · `executor` · `ui-reviewer` |
| **commands/** | `/openpr` · `/review` · `/pr-review` · `/cleanup-and-exit` (`/clean-and-exit` alias) |
| **skills/** | Dispatch/spec/worktree orchestration, architecture/review helpers, optional iOS UI and Figma workflows |
| **scripts/** | `run-ios.sh` · `worktree-sim.sh` · `trust-dir.sh` and hook helpers |
| **templates/** | `spec-template.md` (the structure planner writes) |
| **hooks/** | Protected-branch guard · `spec-before-code` enforcement · per-prompt clarification reminder |
| **permissions/** | `settings.permissions.json` — conservative starter policy; **not auto-merged** by `install.sh` |

Optional extras (gated by install flags):

- `--figma` — Figma MCP `PreToolUse` hook that asks Claude to clarify ambiguous static designs before generating code

## Install

### One-liner (curl)

```bash
curl -fsSL https://raw.githubusercontent.com/LuoYangcan/pele/main/scripts/bootstrap.sh | bash
```

The bootstrap script clones the repo to `<pele-checkout>` (defaults to `~/Developer/pele/`, override with `PELE_INSTALL_DIR=<path>` before piping to bash) and runs `./install.sh`. Pass flags after `--` :

```bash
curl -fsSL https://raw.githubusercontent.com/LuoYangcan/pele/main/scripts/bootstrap.sh | bash -s -- --figma

# Install to a non-default location:
PELE_INSTALL_DIR=~/code/pele curl -fsSL https://raw.githubusercontent.com/LuoYangcan/pele/main/scripts/bootstrap.sh | bash
```

### Manual (git clone)

```bash
git clone https://github.com/LuoYangcan/pele.git <pele-checkout>   # e.g. ~/Developer/pele, ~/code/pele, anywhere
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

Pass `--figma` only in global mode; project mode deliberately does not merge global hooks.

### What install does

1. **Symlinks** `core/` (and `--figma` content if enabled) into the target `.claude/` directory — `~/.claude/` in global mode, `<path>/.claude/` in project mode. Editing an already-linked source takes effect immediately; adding or removing top-level entries requires reinstalling.
2. **Backs up** any pre-existing files in the target directory to `<target>.backup-<timestamp>/` before linking. Nothing is destroyed.
3. **Merges hooks** into the target `settings.json` using `jq`. Your `model`, `mcpServers`, `permissions`, and other keys are preserved. The pre-merge `settings.json` is also backed up.

   For a conservative permission-policy starter, see `core/permissions/settings.permissions.json`. It is **not** auto-merged; add only the command patterns you trust.

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
[Lead Planner] reads rules and repository context
            ├─ small/coupled work: writes the canonical spec
            └─ large independent work: writes a planning manifest
                 → planner-workers write isolated drafts
                 → Spec Integrator publishes one canonical spec
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
            runs build + lint; UI review is a separate opt-in role
   │
   ▼
   PASS → main agent reports to user, you /openpr when ready
   FAIL → main agent loops back to generator with the issue list
          (max 3 retries, then escalates back to user)
```

Each subagent runs in its own context window. They communicate through the canonical `.specs/<slug>.md` index, its child task/risk/amendment files, planning artifacts, and structured messages relayed by the main agent. Generator and executor consume only the integrated canonical spec.

See `core/skills/dispatch-pipeline/SKILL.md` for the full contract.

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

If you maintain a fork of Pele, your working `~/.claude/` may contain private project rules, commands, hooks, credentials, and build recipes. Sync only portable behavior into `core/`.

The original maintainer uses a gitignored local `scripts/sync-from-local.sh` because its replacement dictionary contains private identifiers. It is a first-pass helper, not part of the public distribution; fork maintainers can follow the allow-list and validation procedure in the sync SOP.

```bash
cd <pele-checkout>
git fetch origin
git worktree add .worktrees/sync-N -b chore/sync-from-local-N origin/main
cd .worktrees/sync-N
# Run your local sync helper or copy the public allow-list manually.
# Review every diff, run privacy/reference/install checks, then commit + PR.
```

The full boundary and validation checklist is in **[docs/sync-from-local.md](docs/sync-from-local.md)**.

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

Existing symlink targets update after `git pull`, but new or removed top-level entries and hook changes require reinstalling.

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
│   ├── check-before-push.sh # optional project pre-push check helper
│   ├── check-spec.sh        # PreToolUse hook helper
│   ├── run-ios.sh           # generic simulator/device runner
│   ├── trust-dir.sh         # pre-seed Claude Code folder trust
│   └── worktree-sim.sh      # per-worktree iOS Simulator lifecycle
├── core/                    # always installed
│   ├── CLAUDE.md
│   ├── rules/
│   ├── agents/
│   ├── commands/
│   ├── skills/
│   ├── templates/
│   ├── hooks/settings.hooks.json
│   └── permissions/settings.permissions.json   # conservative starter, not auto-merged
├── figma-extras/            # --figma
│   └── hooks/settings.hooks.json
└── docs/
    └── architecture.md
```

## Design notes

- **Globals over per-project**: Rules / agents / hooks live in `~/.claude/`, not in each repo. Project-specific overrides go in `<repo>/.claude/` as usual.
- **Progressive disclosure**: `CLAUDE.md` is an *index*, not a manual. Each entry has a one-line trigger description so the model only `Read`s the body when it actually applies. Keeps context small.
- **Hard constraints via hooks**: Things that *must* happen (no Edit on `main`/`dev`, spec must exist before Edit in worktrees) are enforced as `PreToolUse` hooks — not as rule text the model can talk itself out of.
- **Independent contexts for subagents**: roles share files and structured results, never implicit conversation memory.
- **Portable by construction**: Pele ships no real project names, private paths, credentials, or mandatory project-specific build commands. Optional platform guidance remains generic and opt-in.
- **Agent-readable docs**: Files under `core/` are written for the next agent that reads them, not for humans browsing the repo. Narrative examples, Why-essays, analogies, and historical context are stripped; trigger conditions, SOP steps, route tables, prompt templates, structured output schemas, and hard constraints are kept. See the `agent-readable-docs` rule for the keep/delete checklist.

## License

MIT — see [LICENSE](LICENSE).

## Credits

Inspired by months of working with Claude Code on a real-world codebase. The structure is debt repayment for everything that's gone wrong: forgetting to clarify, drifting mid-implementation, mock tests passing while prod broke, "I'll fix the spec later", and so on.

Pele has eruptions. Channel them.
