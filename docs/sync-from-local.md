# Sync from local `~/.claude/`

Pele is a curated public distribution of the maintainer's working harness. Sync only portable behavior: no private identifiers, absolute home paths, credentials, unpublished helpers, or project-specific commands.

The maintainer-local `scripts/sync-from-local.sh` performs the copy and token-replacement pass. It is gitignored because its replacement dictionary contains private identifiers; every sync still requires manual diff review.

## Public boundary

| Local content | Sync? | Constraint |
|---|---:|---|
| `CLAUDE.md` | Yes | Keep the index portable and all links resolvable |
| `agents/{planner,planner-worker,spec-integrator,generator,executor,ui-reviewer}.md` | Yes | Preserve role write boundaries and structured contracts |
| Workflow rules and stubs | Yes | No private paths or project-only assumptions |
| Portable platform rules, including Swift/iOS rules | Yes | Optional, generic, and usable outside the maintainer's projects |
| `templates/*.md` | Yes | Keep referenced paths inside the public install |
| Universal commands | Yes | Use `~/.claude/` public install paths |
| Listed skills and required helper files | Yes | Include every file referenced by a shipped skill |
| `scripts/{trust-dir,worktree-sim}.sh` | Yes | Synced helper scripts |
| `scripts/run-ios.sh` | Manual | Keep Pele's environment-configurable public implementation |
| `skills/*/evals/` | No | Local fixtures may contain private data |
| Project rules, commands, credentials, hooks, or build recipes | No | Keep in the private harness or project repo |

The helper's file arrays are the mechanical allow-list. Extend them only when the new file satisfies this boundary.

## Procedure

### 1. Create a sync worktree

```bash
cd <pele-checkout>
git fetch origin
git worktree add .worktrees/sync-N -b chore/sync-from-local-N origin/main
cd .worktrees/sync-N
mkdir -p .specs
touch .specs/sync-N.skip
```

Never sync directly on `main`.

### 2. Run the local helper

```bash
<pele-checkout>/scripts/sync-from-local.sh --dry-run
<pele-checkout>/scripts/sync-from-local.sh
```

The helper copies allow-listed files, rewrites known private tokens, flags context-sensitive lines, and runs a privacy scan. Dry-run previews copy candidates; it cannot fully preview replacements before copied content exists.

### 3. Review and re-decouple

Review `git diff` end to end:

- Replace hardcoded build/lint/test commands with the project's documented command plus optional examples.
- Replace project paths and module names with descriptive placeholders.
- Remove references to private rules, hooks, skills, or scripts.
- Preserve public implementations that are more portable than the local source.
- Confirm every shipped Markdown path and skill helper resolves inside the repository or is explicitly host-provided.
- Update `README.md`, `docs/architecture.md`, and `core/rules/index.md` when roles or workflow contracts change.

If a recurring private token escaped, update the gitignored local helper before the next sync.

### 4. Validate

```bash
# Private-data tripwires
rg -n '\.yangcan-agents|/Users/|BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|gh[opsu]_[A-Za-z0-9]+' \
  core README.md docs scripts

# Shell syntax
find . -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n

# Install surface
./install.sh --project "$(mktemp -d)" --dry-run
```

Also verify:

- no dangling Markdown links or `~/.claude/...` references;
- JSON files parse with `jq`;
- `.specs/`, `.reviews/`, and private fixtures are absent from the commit;
- `git diff --check` passes.

### 5. Publish

Use a conventional commit. Push the sync branch and open a PR against `main`; include the substantive workflow changes and privacy-scan result. Do not merge from the sync worktree.
