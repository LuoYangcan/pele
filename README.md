# Pele

> Volcanic harness for coding agents — opinionated rules, agents, and workflow that put a strong model in charge of planning and a general model in charge of typing.

Pele is a set of global rules, subagents, slash commands, and hooks distilled from real day-to-day use. It installs for **Claude Code, Codex, or both** — the same workflow content, mapped onto each host's own config layout. Its **plan-first, model-tiered delivery** keeps a strong planning-tier model as the Root: native Plan mode produces a decision-complete plan that an independent `plan-challenger` reviews for over-design before it is finalized, a general-model `implementer` subagent writes the code inside frozen boundaries, and the Root reviews, integrates, and verifies each feature unit — with independent verifier / UI-review gates when risk warrants. Each verified feature unit becomes a local commit unless the user or project policy says otherwise; push and PRs still need explicit authorization.

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
| Hooks | managed entries merged into `settings.json` | managed entries merged into `hooks.json`; review and enable them with Codex `/hooks` |
| Per-project install | `--project <path>` | `--project <path>` |

`--host both` installs for both. Skills written for one host's tooling (`codex-simplify`, the Codex review backend) are filtered out of the other host's install automatically. Codex `/review` uses the Codex review backend; Claude Code retains its native legacy backend.

Drop-in install adds the following under the host's config dir:

| Layer | Contents |
|---|---|
| **index** | `CLAUDE.md` / `AGENTS.md` — progressively discloses rules / skills / agents on demand |
| **rules/** | Workflow policies (verification ladder, iteration checkpoints, commit style) plus portable Swift/iOS guidance |
| **agents/** | `plan-challenger` · `implementer` · `verifier` · `ui-reviewer` · `command-runner`; Codex also generates `explorer` and `pr-reviewer` |
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

Symlinks host content into `<path>/.claude/` and/or `<path>/.codex/`. A Codex project installation also exposes skills through `<path>/.agents/skills/`. Pele's rules / agents / skills then apply only when that host opens the project.

```bash
./install.sh --project /path/to/your-project
./install.sh --project /path/to/your-project --dry-run
```

For Codex, the installer appends one marked managed entry to `<path>/AGENTS.md` that reads `.codex/pele-index.md`; it leaves all existing instructions intact and removes only that entry on uninstall. Claude Code keeps its existing project entry-point behavior and installs `.claude/pele-index.md` without replacing a root instruction file.

Pass `--figma` only in global mode; project mode deliberately does not merge global hooks.

### What install does

1. **Symlinks** host content into the selected `.claude/` and/or `.codex/` directory. Codex project skills are also linked under `.agents/skills/`. Editing a linked source takes effect immediately; adding or removing top-level entries requires reinstalling.
2. **Backs up** conflicting files before linking, including links from an older Pele checkout. Reinstallation is idempotent without claiming unrelated links.
3. **Merges hooks** by stable Pele ownership. Third-party hooks, unknown settings, and a user-modified Pele hook are preserved. Codex receives an owned `hooks.json` entry for the protected-branch script, while `/hooks` remains the user's trust and enablement control.

   For a conservative permission-policy starter, see `core/permissions/settings.permissions.json`. It is **not** auto-merged; add only the command patterns you trust.

### Requirements

- macOS / Linux (zsh or bash)
- `git`, `jq` (required by the protected-branch hook), and Python 3.11+. Set `PYTHON_BIN=/path/to/python3.11-or-newer` when the default `python3` is older.
- At least one host: [Claude Code](https://docs.anthropic.com/claude/docs/claude-code) or Codex

### Model policy and doctor

Codex agent models are rendered from the shared policy. See [docs/model-policy.md](docs/model-policy.md) for override precedence and the full schema. Inspect a resolved role without changing config:

```bash
python3 "$HARNESS_ROOT/scripts/model-policy.py" show implementer
```

Run `scripts/check-install.sh` to validate temporary Claude/Codex installs, hooks, generated TOML, dry-run behavior, and uninstall ownership.

## Plan-first delivery

The default behavior changes when you have a code-writing request:

```
You: "implement feature X"
   │
   ▼
[Plan mode]   the Root — a strong planning-tier model (e.g. /model fable) —
              explores, clarifies, produces the final plan:
              the single source of requirement truth
   │
   ▼
[plan-challenger] a fresh read-only reviewer challenges the candidate
              for over-design, over-strict validation, and over-protection
              before it is finalized (one review + one targeted recheck)
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

For project-specific overrides, use the host's standard `.claude/` or `.codex/` mechanisms. To locate portable helpers from an installed shell command, initialize the root in that command:

```bash
HARNESS_ROOT="$("${CODEX_HOME:-$HOME/.codex}"/scripts/harness-root.sh)"
"$HARNESS_ROOT/scripts/validation-receipt.sh" --help
```

Do not rely on a previous command's shell environment; initialize `HARNESS_ROOT` again for each command and pass it to subagents when they need the same checkout.

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

`uninstall.sh` removes links that still point at its own checkout, removes only unmodified managed hook entries, and removes its marked AGENTS.md entry while preserving surrounding user text. It also asks the model-policy helper to remove only generated agent TOML files whose recorded hash still matches.

Existing symlink targets update after `git pull`, but new or removed top-level entries and hook changes require reinstalling.

## Uninstall

```bash
<pele-checkout>/uninstall.sh                                # global mode
<pele-checkout>/uninstall.sh --project /path/to/your-project   # project mode
```

Removes only links pointing into `<pele-checkout>`, unmodified managed hooks, and its managed AGENTS.md entry. Does **not** auto-restore from `<target>.backup-*/` — those are kept for you to restore manually if needed:

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
