# Pele

> Volcanic harness for coding agents — opinionated rules, agents, and workflow that put a strong model in charge of planning and a general model in charge of typing.

Pele is a set of global rules, subagents, slash commands, and hooks distilled from real day-to-day use. It installs for **Claude Code, Codex, or both** — the same workflow content, mapped onto each host's own config layout. Its **plan-first, model-tiered delivery** keeps a strong planning-tier model as the Root: native Plan mode produces a decision-complete plan, a general-model `implementer` subagent writes the code inside frozen boundaries, and the Root reviews the diff, integrates, verifies, and commits each feature unit — with independent verifier / UI-review gates when risk warrants.

Named after [Pele](https://en.wikipedia.org/wiki/Pele_(deity)), the Hawaiian volcano goddess: she controls the eruption.

## What you get

### Host support

| | Claude Code | Codex |
|---|---|---|
| Install | `./install.sh` (default) | `./install.sh --host codex` |
| Config dir | `~/.claude/` | `~/.codex/` (or `$CODEX_HOME`) |
| Index file | `CLAUDE.md` | `AGENTS.md` |
| Agent definitions | `agents/*.md` | `agents/*.toml` |
| Slash commands | `commands/` | `prompts/` |
| Hooks | merged into `settings.json` | not applicable |
| Per-project install | `--project <path>` | global only |

`--host both` installs for both. Skills written for one host's tooling (`codex-simplify`, the Codex review backend) are filtered out of the other host's install automatically.

Drop-in install adds the following under the host's config dir:

| Layer | Contents |
|---|---|
| **index** | `CLAUDE.md` / `AGENTS.md` — progressively discloses rules / skills / agents on demand |
| **rules/** | Workflow policies (verification ladder, iteration checkpoints, commit style) plus portable Swift/iOS guidance |
| **agents/** | `implementer` · `verifier` · `ui-reviewer` · `command-runner` (shipped as both `.md` and `.toml`) |
| **commands/** | `/openpr` · `/ship` · `/review` · `/pr-review` · `/cleanup-and-exit` (`/clean-and-exit` alias) |
| **skills/** | `plan-first-delivery` and worktree orchestration, architecture/review helpers, optional iOS UI and Figma workflows |
| **scripts/** | `run-ios.sh` · `worktree-sim.sh` · `worktree-bootstrap.sh` · `validation-receipt.sh` · `trust-dir.sh` and hook helpers |
| **templates/** | `exec-plan-template.md` (single-file ExecPlan for cross-session / multi-writer / audited work) |
| **hooks/** | Protected-branch guard · per-prompt clarification reminder |
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

Symlinks `core/` into the host config dir (`~/.claude/`, or `~/.codex/` with `--host codex`). Pele's rules / agents / skills apply across every project that host opens on this machine.

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
@.claude/pele-index.md
```

Pele installs `<path>/.claude/pele-index.md` as the entry point — but `install.sh` deliberately does **not** modify your `CLAUDE.md` / `AGENTS.md`. Without that one `@` line, Claude Code won't pick up the index automatically.

Pass `--figma` only in global mode; project mode deliberately does not merge global hooks.

### What install does

1. **Symlinks** `core/` (and `--figma` content if enabled) into the target `.claude/` directory — `~/.claude/` in global mode, `<path>/.claude/` in project mode. Editing an already-linked source takes effect immediately; adding or removing top-level entries requires reinstalling.
2. **Backs up** any pre-existing files in the target directory to `<target>.backup-<timestamp>/` before linking. Nothing is destroyed.
3. **Merges hooks** into the target `settings.json` using `jq`. Your `model`, `mcpServers`, `permissions`, and other keys are preserved. The pre-merge `settings.json` is also backed up.

   For a conservative permission-policy starter, see `core/permissions/settings.permissions.json`. It is **not** auto-merged; add only the command patterns you trust.

### Requirements

- macOS / Linux (zsh or bash)
- `git`, `jq` (for hook merging — optional but recommended)
- At least one host: [Claude Code](https://docs.anthropic.com/claude/docs/claude-code) or Codex

## Plan-first delivery

The default behavior changes when you have a code-writing request:

```
You: "implement feature X"
   │
   ▼
[Plan mode]   the Root — a strong planning-tier model (e.g. /model fable) —
              explores read-only, clarifies, produces the final plan:
              the single source of requirement truth
   │
   ▼ you approve and switch back to Default mode
[Root]        creates an isolated worktree (.worktrees/<slug>) from
              origin/<base>, freezes decision-complete units with
              explicit file ownership
   │
   ▼
[implementer] a general implementation-tier model writes the code inside
              its frozen boundary; returns the diff + open questions —
              never commits, never decides material questions
   │
   ▼
[Root]        reviews the actual diff, integrates, commits each verified
              feature unit, runs post-change verify
              (cheap lint/check → build → targeted tests)
   │
   ▼
   orthogonal gates when they hit:
     independent [verifier] for risky diffs
     [ui-reviewer] for Figma / animation / complex UI
     parallel implementers for mutually exclusive write domains
   │
   ▼
   PASS → Root reports; you /ship or /openpr when ready
   FAIL → narrow repair by the Root, or re-dispatch to the implementer
          with the failure evidence; repeated failures escalate to you
```

Micro-edits, integration fixes, and narrow repairs stay with the Root — spawning a worker for a one-line change costs more than it saves. Everything else is typed by the cheaper implementation tier under the strong model's plan, and the Root remains the only writer of shared interfaces and final merges.

See `core/skills/plan-first-delivery/SKILL.md` for the full contract.

## Customize

Pele uses **symlinks**, so you customize by editing the source files in `<pele-checkout>`:

- Add a new rule → `core/rules/<name>.md` + add an entry to `core/CLAUDE.md` index
- Add a new subagent → `core/agents/<name>.md`, then reference it from a skill (e.g. `plan-first-delivery`)
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
│   ├── bootstrap.sh              # used by the curl one-liner
│   ├── check-before-push.sh      # optional project pre-push check helper
│   ├── run-ios.sh                # generic simulator/device runner
│   ├── trust-dir.sh              # pre-seed Claude Code folder trust
│   ├── worktree-sim.sh           # per-worktree iOS Simulator lifecycle
│   ├── worktree-bootstrap.sh     # one-shot task-worktree create + init
│   ├── validation-receipt.sh     # fingerprint-bound verification receipts
│   ├── review-input-snapshot.sh  # freeze the diff a reviewer will judge
│   ├── review-result.sh          # structured review verdict helper
│   └── sync-xcode-skills.sh      # export Apple platform skills from local Xcode
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
    ├── architecture.md
    └── sync-from-local.md
```

## Design notes

- **Globals over per-project**: Rules / agents / hooks live in `~/.claude/`, not in each repo. Project-specific overrides go in `<repo>/.claude/` as usual.
- **Progressive disclosure**: `CLAUDE.md` is an *index*, not a manual. Each entry has a one-line trigger description so the model only `Read`s the body when it actually applies. Keeps context small.
- **Hard constraints via hooks**: Things that *must* happen (no Edit/Write on protected branches — changes go through `.worktrees/` isolation) are enforced as `PreToolUse` hooks — not as rule text the model can talk itself out of.
- **Independent contexts for subagents**: roles share files and structured results, never implicit conversation memory.
- **Portable by construction**: Pele ships no real project names, private paths, credentials, or mandatory project-specific build commands. Optional platform guidance remains generic and opt-in.
- **Agent-readable docs**: Files under `core/` are written for the next agent that reads them, not for humans browsing the repo. Narrative examples, Why-essays, analogies, and historical context are stripped; trigger conditions, SOP steps, route tables, prompt templates, structured output schemas, and hard constraints are kept. See the `agent-readable-docs` rule for the keep/delete checklist.

## License

MIT — see [LICENSE](LICENSE).

## Credits

Inspired by months of working with Claude Code on a real-world codebase. The structure is debt repayment for everything that's gone wrong: forgetting to clarify, drifting mid-implementation, mock tests passing while prod broke, "I'll fix the spec later", and so on.

Pele has eruptions. Channel them.
