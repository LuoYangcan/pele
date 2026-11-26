---
name: dead-code
description: Scan recent code changes for "zombie code" — newly-added or modified symbols that no caller references. Use when the user explicitly asks for dead-code cleanup, preferably once after the final implementation diff is stable. Skip when there are no Swift changes or implementation is still in progress.
---

# dead-code

After repeated agent iteration, **zombie code** is often left behind — methods, types, enum cases, and orphan files that live in the repo with no caller at all. It compiles, CI passes, but it is dead. When the user explicitly invokes it, this skill scans **recent changes**, lists the suspected zombies for the user to decide on, and **never deletes automatically**.

> The current implementation supports **Swift** projects only (it relies on [Periphery](https://github.com/peripheryapp/periphery)'s SourceKit index). Other language ecosystems can follow the same skeleton — scan → filter to the changed scope → tier → user decides — with a different underlying tool (e.g. TypeScript: `ts-prune`, Python: `vulture`, Go: `unused`, Kotlin: `detekt --baseline` + the `unused` rule).
>
> `/review` does not invoke this skill.

## Trigger conditions

**Triggers** (the user explicitly says):

- "scan for zombie code", "clean up the methods nobody uses"
- "did this change leave abandoned code", "dead code check"
- "run the dead-code skill"
- After the final implementation diff is stable, Root wants one concentrated cleanup
- Before pushing a PR, self-review unused code

**Does not trigger**:

- No Swift file changes in the current diff (this skill only understands Swift)
- The user is mid-implementation and explicitly says "leave it, scan when I'm done"
- The task is fixing lint / typos / copy — such changes do not produce zombies

## Scan scope

The default scope is **`<main-branch>...HEAD` in the current worktree plus uncommitted changes**, assembled with the commands below (substitute your project's main branch for `dev` / `main`):

```bash
# base = merge-base against origin/<main-branch> (fall back to the local branch / HEAD~1)
MAIN=dev   # or main / master, adjust to the project
BASE=$(git merge-base HEAD origin/$MAIN 2>/dev/null \
       || git merge-base HEAD $MAIN 2>/dev/null \
       || echo HEAD~1)

# changed / added Swift files
{
  git diff --name-only --diff-filter=AMR "$BASE" -- '*.swift'    # committed but not pushed yet
  git diff --name-only -- '*.swift'                              # unstaged
  git diff --name-only --cached -- '*.swift'                     # staged
  git ls-files --others --exclude-standard -- '*.swift'          # untracked new files
} | sort -u
```

If the user **specifies the scope manually** ("only the last 3 commits" / "look at PR-123" / "all of main"), compute the diff with `$BASE` replaced by the scope they gave — do not force the default.

> ⚠️ **Do not scan main-branch history**: this skill is designed for work in progress. If the user asks "how much dead code does the whole project have", point them at a full `periphery scan` instead of this skill — a full-project result is too large to review by hand.

## Prerequisite: detect Periphery

```bash
which periphery || echo "MISSING"
```

- **Installed** → take the [Periphery path](#path-a-periphery-primary-path)
- **Not installed** → give the user two options (let them choose):
  1. "I can prompt you to install it: `brew install periphery`, then re-run this skill"
  2. "Or take the LSP fallback path — slower, lower coverage. Want the fallback?"

  Act on the user's answer. **Do not** run `brew install` yourself (global side effect, needs authorization).

## Path A: Periphery (primary path)

### A.1 Prepare the Periphery config

If the project already has `.periphery.yml`, use it; otherwise generate a temporary config (**Periphery ≥ 3.0 schema**):

```bash
# for an Xcode workspace
cat > /tmp/periphery-deadcode.yml <<'EOF'
project: <YourApp>.xcworkspace                # or <YourApp>.xcodeproj
schemes:
  - <YourAppiOS>                              # replace with the real scheme (see `xcodebuild -workspace ... -list`)
retain_public: true                           # public API is exposed across packages; this repo alone cannot prove it unreferenced
retain_objc_accessible: true
retain_unused_protocol_func_params: true
EOF
```

> ⚠️ **Important 3.x yml field changes**: `project:` now accepts both `.xcworkspace` and `.xcodeproj` (there is no separate `workspace:` field any more). `targets:` was removed; targets are derived from the scheme. An `invalid key 'workspace'` error means the version does not match.

`retain_public: true` is **critical** — in a multi-package SPM project (typically a layered structure like `packages/common/*` + `packages/ios/{Core,UI,...}` + `packages/ios/Business/*`), many `public` symbols exist for cross-package use; Periphery of course finds no caller inside a single target, but they are not zombies.

If the project is SPM-only (no xcworkspace), change it to:

```yaml
project: Path/To/Package.swift
```

Unsure of the scheme name → run `xcodebuild -workspace <YourApp>.xcworkspace -list | sed -n '/Schemes:/,$p' | head -30` and look.

### A.2 Run the scan

```bash
periphery scan --config /tmp/periphery-deadcode.yml --format json > /tmp/periphery-output.json 2> /tmp/periphery-stderr.log
```

Expected timings (measured on a typical multi-package iOS app):

- **First run (no index)**: 5-10 minutes (Periphery triggers a full SourceKit index)
- **Later runs (Xcode/Periphery cache warm)**: 1-2 minutes
- **`--skip-build` reuses the previous index**: 5-10 seconds (fits back-to-back re-runs and quick yml tweaks)

```bash
# if you are sure no Swift file changed since the last scan, add --skip-build to reuse the index
periphery scan --config /tmp/periphery-deadcode.yml --format json --skip-build > /tmp/periphery-output.json 2> /tmp/periphery-stderr.log
```

When the build fails Periphery reports it on stderr — **do not** silently ignore it; show the key stderr lines to the user and ask whether to fix the build first.

### A.3 Filter to recent changes

Periphery outputs the full unused list (hundreds of entries on an older project), but this skill only cares about **zombies produced by this round of changes**.

#### A.3.1 JSON schema (measured on Periphery 3.7.4)

Each record looks like this:

```json
{
  "location": "/abs/path/to/File.swift:15:1",
  "kind": "function.method.instance",
  "name": "suspend()",
  "hints": ["unused"],
  "accessibility": "internal",
  "modifiers": [],
  "attributes": [],
  "modules": ["<YourAppiOS>"],
  "ids": [...]
}
```

**Key fields**:

- `.location` is an **absolute path** + `:line:col` (not relative! when filtering, either convert changed-files to absolute or match with an endswith pattern)
- `.kind` is a dot-separated namespaced string: `var.instance` / `var.static` / `var.parameter` / `function.method.instance` / `function.method.static` / `function.constructor` / `function.operator.infix` / `struct` / `class` / `enum` / `protocol` / `typealias` / `extension.struct` / `module` (`module` = unused import)
- `.hints` is an array; common values: `unused` (declaration has no caller), `assignOnlyProperty` (assigned but never read). Both are zombie candidates
- `.accessibility` ∈ {`open`, `public`, `internal`, `fileprivate`, `private`} — use it together with the exemption list's cross-package `public` rule

#### A.3.2 Intersect Periphery results with this round's changes

```bash
# convert changed files to absolute paths (Periphery locations are absolute)
REPO=$(git rev-parse --show-toplevel)
sed "s|^|$REPO/|" /tmp/changed-files.txt > /tmp/changed-files-abs.txt

# extract Periphery results, filter by absolute file path
jq -r '.[] | "\(.location)\t\(.kind)\t\(.name)\t\(.accessibility)\t\(.hints | join(","))"' /tmp/periphery-output.json \
  | awk -F'\t' '
      NR==FNR { abs[$0]=1; next }
      {
        # location looks like "/abs/path/File.swift:15:1" — cut the file path at the first ":"
        n = index($1, ":")
        file = substr($1, 1, n - 1)
        if (file in abs) print
      }
    ' /tmp/changed-files-abs.txt - \
  > /tmp/periphery-changed.tsv
```

**Note**: filtering to changed files is not enough — if an old symbol in an old file loses its last caller (because this round's diff deleted the caller), it is a zombie, but the Periphery report only shows a line in that old file, which is not in changed-files. Add a second filtering pass:

```bash
# collect every deleted symbol reference in the changed files — these can turn old symbols unused
git diff "$BASE" -- '*.swift' | grep -E '^-' | grep -oE '\b[A-Z][A-Za-z0-9_]*\b|\b[a-z][A-Za-z0-9_]*\(' | sort -u > /tmp/possibly-orphaned-refs.txt

# any symbol name in the full Periphery result that matches the above also becomes a candidate
jq -r '.[] | "\(.location)\t\(.kind)\t\(.name)\t\(.accessibility)\t\(.hints | join(","))"' /tmp/periphery-output.json \
  | grep -F -f /tmp/possibly-orphaned-refs.txt \
  >> /tmp/periphery-changed.tsv
```

Merge and dedupe the two filtered results to get the **zombie candidate list for this round's changes**.

### A.4 Confidence tiering

Split the candidate list into two tiers:

| Tier | Meaning | Example |
|------|------|------|
| **High confidence** | private/internal symbol, declared in this round's changes, 0 refs from both Periphery and LSP findReferences | a newly added `private func formatThing()` with no caller |
| **Low confidence** | public symbol / @objc / possibly called by reflection / inside a protocol extension / carries a @Test attribute / a SwiftUI `body`-only helper | `public func setupUI()` in some VC with no caller in this repo — but a subclass may override it |

List low-confidence items separately, **do not proactively suggest deleting them**; they are for the user's reference only.

## Path B: LSP fallback (no Periphery)

### B.1 Extract symbols added by this round's changes

```bash
git diff "$BASE" -- '*.swift' \
  | grep -E '^\+' \
  | grep -E '^\+\s*((public|internal|private|fileprivate|open)\s+)?(static\s+|class\s+|mutating\s+|final\s+)*(func|class|struct|enum|protocol|typealias|extension|case|var|let)\s+' \
  > /tmp/added-symbols.txt
```

The regex yields **candidate lines**, which need further processing:

- Get file:line (use `git diff --unified=0` to align line numbers, or grep that line's line number in the file)
- Get the symbol name (`func fooBar(...)` → `fooBar`)

### B.2 Run LSP findReferences on each candidate symbol

```text
LSP(operation="findReferences", filePath=<path>, line=<line>, character=<col>)
```

By returned reference count:

- **== 1** (the declaration itself only) → high-confidence zombie
- **2-3, all in the same file** → low-confidence (may just be `private` internal use, but may also be an in-class placeholder)
- **>3 or across files** → not a zombie, skip

### B.3 grep re-check

LSP misses these cases: protocol default implementations, `@dynamicMemberLookup`, `@objc` exposure, `#selector(...)` references, `String(describing:)` reflection. So for high-confidence candidates, **grep the symbol name once more with a whole-word match**:

```bash
rg -n -w "<symbol>" --type swift
```

Keep it as high-confidence only when the match count == 1 (the declaration itself); otherwise degrade it to low-confidence.

> ⚠️ Path B is slower and less complete than Path A, and **cannot** replace Periphery. LSP does not understand Swift overloads, generic derivation, or protocol witnesses — one false positive that makes the user delete live code is a serious incident. **Tell the user to hand-check every Path B conclusion**; do not give a strong "just delete it" recommendation.

## Exemption list (not treated as zombies)

Do **not** count the following symbols as zombies even at 0 refs — filter them out of the results:

| Pattern | Reason |
|------|------|
| `public` symbols in a shared / common / platform-foundation package (the `packages/common/*`, `packages/ios/{Core,UI,...}` layering in a multi-package SPM project) | exposed across packages; a single repo cannot decide |
| marked `@objc` / `@objcMembers` / `@IBAction` / `@IBOutlet` | called via Obj-C runtime / IB reflection; static analysis cannot see it |
| `@Test` / `func test...()` under `Tests/` / `*Tests/` | launched by XCTest / Swift Testing runtime reflection |
| SwiftUI `#Preview { ... }` / `PreviewProvider` | launched by Xcode preview |
| `static func == / hash(into:) / func encode(to:) / init(from:)` | protocol witness; static analysis easily misses it |
| `deinit` / `init?(coder:)` | called by system reflection |
| a method in an extension that satisfies a protocol requirement (even when nothing calls it on this type) | protocol witness |
| marked `@available(*, deprecated)` | already on the deprecation path; this skill does not nag again |

List the exemption rules **explicitly in the report** — so the user knows which symbols this skill skipped, avoiding the "I thought it scanned that" blind spot.

## Output report (mandatory format)

After the scan you **must** output using this markdown template, so the user sees it at a glance:

```markdown
# Dead-code scan report

**Scope**: `<base>...HEAD + uncommitted` (N Swift files changed)
**Tool**: Periphery <version> / LSP fallback
**Elapsed**: about X minutes

## High confidence (deletion suggested, K items)

| # | File | Line | Symbol | Kind | Reason |
|---|------|------|--------|------|---------|
| 1 | `path/to/Foo.swift` | 42 | `formatThing` | private func | Periphery + LSP 0 refs, added this round |
| 2 | ... | ... | ... | ... | ... |

## Low confidence (needs a human check, M items)

| # | File | Line | Symbol | Kind | Reason | Suggested check |
|---|------|------|--------|------|---------|------------|
| 1 | `path/to/Bar.swift` | 17 | `setupUI` | public func | public symbol, 0 refs in this repo | global grep + go through every place that imports this type |
| 2 | ... | ... | ... | ... | ... | ... |

## Exemption list (P items skipped)

- `public` cross-package symbols: N
- `@objc` marked: N
- Tests / Preview / protocol witness: N

Tell me if you want the exemption details.

## Next step

Pick one:
- **(A) I delete all K high-confidence items for you** — one deletion pass, then run the relevant build on the final candidate
- **(B) You name the ones to delete** — give me the numbers, e.g. "1, 3, 5"
- **(C) Just the deletion command list**, you edit by hand
- **(D) Change nothing** for now
```

> Reasons in the report must be **specific**: "Periphery + LSP 0 refs, added this round" is good; "unused" is useless.

## Deletion phase (only when the user picks A or B)

After the user picks A / B:

1. Delete the selected high-confidence declarations in one pass and clean up adjacent comments/blank lines; do not refactor along the way.
2. Per `post-change-verify`, run the relevant build once on the final candidate. On failure, restore or adjust the specific mis-deleted item based on the compiler evidence, then re-run only the invalidated gate.
3. Do not commit; leave the diff and the verification evidence for the user to review.

## Known limits

- **Periphery timing**: the first scan takes 5-10 minutes (build + index). Later runs hit the cache at 1-2 minutes. `--skip-build` reuses the previous index and drops to 5-10 seconds (see A.2).
- **Cross-language bridges are invisible**: bridging headers where Swift calls C / C++, and bridges Swift exposes to Obj-C, may be used via reflection. The exemption list covers most of it, but not 100%.
- **Runtime dynamic dispatch**: `#selector(target.action)`, KVO key paths, `String(describing:)` reflection, and `UIViewController.performSegue(withIdentifier:)` are in principle invisible to static analysis. The **low-confidence tier** exists to leave room for human review of these cases.
- **Generics / protocol associated-type inference**: Periphery occasionally false-positives on generic helpers. If the user says "this is obviously in use", move it into the exemption notes immediately; do not argue.

## Out of scope

- ❌ **Does not auto `brew install` Periphery** — global side effect; let the user authorize it
- ❌ **Does not scan main-branch history** — designed for work in progress; run `periphery scan` directly for a full scan
- ❌ **Does not auto-commit** — only edits files; the diff is left for the user to review
- ❌ **Does not replace SwiftLint / project lint** — those check a different class of problem (style, complexity); this skill only checks "no caller"
- ❌ **Does not replace `/review`** — `/review` is a full code review; this skill covers the dead-code dimension only
- ❌ **Does not delete non-Swift code** — does not scan `.m` / `.mm` / `.cpp` / `.ts`; write a separate skill when the project extends to other languages
- ❌ **Does not touch files before a decision** — report, then wait for the user to pick

## Relationship to other skills / rules

- **cleanup backend**: Claude uses `/simplify`; Codex uses `codex-simplify`. Cleanup fixes automatically; this skill only looks at unused code — report first, delete only after the user selects.
- **`plan-first-delivery`**: when the user explicitly asks, run one concentrated scan after the final implementation diff is stable; Root adopts the deletions and integrates.
- **`post-change-verify`**: this skill does not replace final verification; after deletion, Root or `command-runner` verifies the final candidate.

## Why (core)

Frequent agent iteration tends to leave three kinds of zombies: old methods never deleted / half-finished work never removed / whole files orphaned. The positioning is "light automation + human decision" — the agent cannot see runtime reflection, so it must not delete on its own; a human has no patience to scan 50 files, so the tool strips non-zombie noise like public API / @objc / tests.
