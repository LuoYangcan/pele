---
name: figma-precise-extract
description: For Figma UI tasks, generate an H5 style preview and freeze exact sizes, spacing and tokens before the Plan is finalized; also used to diagnose icon/spacing drift. Strict by default; skip when there is no Figma design, the change is not UI, or the user explicitly chose loose strictness.
---

# figma-precise-extract

Resolve installed paths per the [host adapter](../../rules/host-adapter.md) before running helpers.

This skill bakes the output of four tools into a measurement-grade frozen HTML: structure comes from `get_design_context`, exact numbers from `get_metadata` and `get_variable_defs`, converted to pt by the design base scale. The implementation owner reads the frozen artifacts and does not re-fetch live data while writing code.

## Triggers / does not trigger

Triggers:

- a Figma UI task previewing styles and freezing design inputs before the Plan is finalized; strict by default, without requiring the user to ask for it
- any figma→code task that needs exact icon size / spacing / token
- diagnosing "implemented per figma but icon / spacing / control size does not line up"

Does not trigger:

- no figma design (implementing from a verbal description)
- non-UI change
- user explicitly chose loose strictness (layout skeleton + color tokens only; spacing / font size may vary ±2pt)

## Timing and artifact directory

- **Plan stage**: after Root selects the design nodes, run the baking SOP below, generate and show the H5 preview, handle user feedback that changes layout, state or scope, and only then finalize the plan. A plan diagram does not replace a page style preview.
- **Permissions and location**: `<design-assets>` below is this round's design-artifact directory. Native Plan writes PNGs, measurement HTML and `preview.html` only in a scratch/temporary directory the host explicitly allows, never project source, config or plan files. Stricter Plan restrictions win; when file writes are forbidden, use the host's allowed inline HTML preview, and when even inline display is unavailable, mark the preview as not done — do not leave Plan or change permissions on your own to produce files.
- **Showing and feedback**: the final plan records the preview entry (file path or inline artifact/message reference), the visual feedback handled, and the remaining differences; the inline route keeps the same round's captured HTML, measurement data and PNG content, or a recoverable reference, for the implementation handoff. A preview not generated or not shown cannot be recorded as done. The preview itself does not authorize implementation; continue through the host's existing plan acceptance/implementation authorization flow, without adding a fixed confirmation phrase.
- **Implementation handoff**: after entering Default, copy existing files verbatim, or write recoverable inline content verbatim, into the task worktree's `.specs/<slug>-assets/`, and update references and the design identity record below; do not re-fetch or regenerate the preview. When the preview/artifacts are missing or unrecoverable, complete them and show them again before the first source write, without passing a fresh fetch off as the existing frozen result; existing implementation authorization still holds, and only newly surfaced material decisions need a question.

## Division of labor across the four tools (core mental model)

| Tool | What it gives you | Numeric trustworthiness |
|---|---|---|
| `get_design_context` | **Layout structure + reference HTML/CSS skeleton**: Auto Layout (itemSpacing / per-side padding / alignment / FILL-HUG-FIXED) + a block of reference code + asset download URLs | ❌ numbers in the code are snapped to the target framework's scale (`gap-2`/`p-4`) and are **not measurements**; but structure / Auto Layout semantics + the HTML skeleton are **only here** |
| `get_metadata` | **Exact pixel geometry**: per-node id / type / name / x / y / width / height (children included) | ✅ the only source of exact pixels |
| `get_variable_defs` | **Exact tokens**: spacing / size / radius / color variable name → value | ✅ the design intent for spacing / icon size / corner radius |
| `get_screenshot` | Rendered raster, long edge compressed by maxDimension | ⚠️ for checking layout / confirming a node was drawn, **not for measuring** pixels |

Baking = **take the structural skeleton from get_design_context and override its snapped numbers with get_metadata (sizes) + get_variable_defs (spacing/tokens), converted to pt by the scale**. Do not expect one tool to give everything: structure ← design_context, exact pixels ← metadata, tokens ← variable_defs.

## Baking SOP

1. **Pick the right node**: run `get_metadata` on the target node first to see the layer tree and confirm you grabbed the **visible component itself**, not a padded wrapper / hit area. A wrong node-id in the URL (pointing at the page / a parent node) yields whole-screen geometry.

2. **Compute the design base scale (compute it first, never default to 1)**: `scale = figma frame width (px) / target device point width (pt)`. Only =1 means px==pt (frame width exactly 375/390/393/414/428/430); @2x/@3x (frame 786/1179) or non-device-width designs (1440 web design, a 414 design on a 393 device) give scale ≠ 1, and every layout number must be divided by it. **Trap**: skipping this step biases every number by the same constant and keeps the proportions self-consistent → neither the eye nor a compressed-image self-check catches it. Apply it **once** while baking; every number frozen into the HTML is pt.

3. **Get the structural skeleton** ← `get_design_context({nodeId, forceCode: true})`: Auto Layout structure / alignment / sizing modes / layer hierarchy + a block of reference HTML/CSS + asset download URLs. `forceCode: true` prevents a large node from degrading to metadata only; if it still returns metadata only (no structure / no asset URLs) or sparse data (only `<frame>`/`<text>` tags with no styles) → go to "Large-node degradation fallback" below and re-fetch child by child, level by level, and **do not hand-write the skeleton** (hand-writing cannot recover the exported asset URLs). **Keep the structure, do not trust the numbers inside it.**

4. **Fetch exact numbers to override the skeleton's values**:
   - size ← `get_metadata`: exact w/h/x/y per icon / key control child node, converted to pt by the scale
   - spacing / corner radius ← `get_variable_defs` tokens first (tokenized values are exact and unambiguous) + cross-check against the Auto Layout itemSpacing / padding **property values** in design_context (not the generated code's classes); metadata x/y deltas are cross-validation only (SPACE_BETWEEN / padding / stroke overflow make them disagree with the declared value)
   - token ← `get_variable_defs` (call it on the exact variant node for variants): size / spacing / radius / color variable name → value, not just colors

5. **Bake into frozen HTML** → `<design-assets>/figma-<nodeId-safe>.html` (`<nodeId-safe>` = nodeId with `:` replaced by `-`): write step 3's structural skeleton + step 4's overridden exact numbers as self-contained HTML/CSS, all numbers stored in pt, tokens keeping both value and name. The implementation owner reads only this artifact.

6. **Screenshot is visual reference only** ← `get_screenshot({nodeId, maxDimension: 4096})` frozen as PNG: strokes (outside/center), shadows and blur are drawn outside the layout box → they do not count toward size. **PNG = visual source of truth** (color / shadow / gradient / rendered look), **HTML = measurement source of truth** (size / spacing / pt).

7. **Icons specifically (frame vs glyph)**: a Figma icon is usually a fixed outer frame (24×24) wrapping a smaller glyph (~20) + optical padding. metadata reports the **outer frame**, the exported SVG viewBox reports the **glyph**. Set the box to the metadata outer-frame size (converted to pt); record "outer frame X×X / glyph ≈ Y" in an HTML comment. With Code Connect, prefer resolving the icon to the real component over re-deriving it from geometry. Export bitmap assets once each at @1x/2x/3x into the asset catalog (see `"$HARNESS_ROOT/core/skills/figma-asset-export/SKILL.md"`), do not convert them inside the HTML.

## Large-node degradation fallback (when design_context returns sparse data)

When the design is too large, `get_design_context` may return only sparse tags or metadata. The critical omissions are the structural skeleton and the asset URLs; hand-writing cannot recover the assets, and the implementation owner is forced into approximate icons.

**Block; do not proceed to the next step in the sparse state.** For a degraded node N, re-fetch child by child, level by level:

1. `get_metadata(N)` enumerates N's first-level child ids + each one's x/y/w/h relative to the root.
2. Call `get_design_context({nodeId, forceCode: true})` on each first-level child separately — smaller nodes mostly no longer degrade, so you get back each one's structure + asset URLs.
3. Split a still-degraded child one more level down (recursively), **depth limit 3 levels** (or a cumulative child-node cap), to prevent an MCP call explosion.
4. A subtree still sparse past the limit → fall back to a hand-written skeleton and flag the missing asset URLs under risks/open items in the final plan; before implementation, the user or Root must decide whether to accept it.

**Coordinate-alignment trap (mandatory when merging)**: a separately re-fetched child's structure / coordinates may be relative to **its own origin (0,0)**, not the parent frame. When merging back into the frozen HTML you **must** offset by each child's **x/y relative to the root** from step 1's metadata, otherwise all children pile up at (0,0) — silently destroying the layout, invisible to both the eye and a compressed-image self-check (same class as the scale trap).

While the design source, the selected nodes and the user's visual decisions are unchanged and the artifacts are recoverable, implementation and UI acceptance reuse the same set of frozen artifacts; updating and re-showing follow the preview rules below.

## What the frozen HTML contains

The baked HTML is equivalent to this per-element precision table (encoded directly into the HTML/CSS, numbers already in pt):

| Element | Exact size (pt) | Spacing / position | token | Notes |
|---|---|---|---|---|
| frame | 375×200 | outer padding 16 | `spacing/md=16` | — |
| icon: bell | 24×24 (outer frame) | gap 8 to title | `icon/size/md=24` | glyph ≈ 20, padding 2 |
| title | height 22 | baseline centered with icon | `text/title 17pt semibold` | — |
| primary button | height 44 | — | `radius/md=8` | — |

Size = metadata converted to pt; spacing = variable_defs tokens first + cross-checked against design_context itemSpacing; token = variable_defs; alignment/sizing from design_context. The final plan or ExecPlan records only artifact paths, scale, tokens, strictness and the asset-export list, not the inlined per-element table.

## preview.html fidelity preview (strict tasks)

Beyond the frozen PNG and the measurement HTML, a strict task generates a third artifact at the end of baking, `<design-assets>/preview.html`, and opens it together with the frozen PNG before the final plan is finalized so the user can judge fidelity in a browser; use the host's file/browser preview tool or `open` — returning only a file path does not count as shown. Permissions, feedback and the implementation handoff follow "Timing and artifact directory" above. The PNG remains the source of truth for color, shadow and icon feel.

Triggers: strict figma→code tasks. loose skips it (skeleton + color tokens only, no replication needed).

Generation spec (one merged file per slug):

- Self-contained single file: full `<!DOCTYPE html>` + inline CSS/JS, **no external resources at all** (no CDN / linked fonts / remote images; it must open under CSP and offline). Use the system font stack `-apple-system,"SF Pro",system-ui` (SF Pro on macOS).
- One native-pt-wide phone frame per frozen node (scale already applied, width = device point width such as 402), multiple nodes **side by side** (flex-wrap), each frame labeled with node-id + state name.
- Geometry comes from the measurement HTML (spacing / size / corner radius / font size 1:1 in pt); color / glass / gradient come from the PNG (approximate glass with `backdrop-filter: blur`); approximate icons with inline SVG (SF Symbol is unavailable).
- Stateful variants (collapsed↔expanded / selection toggle / empty↔full) → add minimal inline JS to toggle on click, showing the primary state by default.
- A caveats banner at the top: "Approximate replica: judge layout / spacing / structure; PNG = visual source of truth (glass / color / icons are finer there); placeholders such as agentName have been replaced with runtime values".
- The filename is fixed as `preview.html`. Generate it once during baking; when the design source (file/node/version), the selected node set, or an explicit user decision on the visual approach changes, update the affected nodes' phone frames and show it again, syncing the corresponding PNG/measurement HTML and the final plan. When the user asks to deviate from the design, keep the original PNG and mark the difference; do not pass a revised preview off as the design source. Ordinary implementation iterations, code review and verification rounds neither rebuild nor rewrite this file.

## Hard constraints

- ❌ Do not freeze sizes / spacing from `get_design_context`'s generated code into the HTML as exact values (they are snapped to the framework scale, especially Tailwind / design-system clients) — you **must** override with metadata (size) / tokens (spacing) before freezing
- ❌ Do not hand-write a skeleton and move on when `get_design_context` returns sparse data (metadata only / no asset URLs) — go through "Large-node degradation fallback" and re-fetch child by child, level by level (hand-writing cannot recover the exported asset URLs); merged children must be offset by their metadata x/y relative to the root
- ❌ Do not look for Auto Layout / alignment / strokeAlign / effects in `get_metadata` (it has only position / size); do not trust its x/y deltas alone for spacing
- ❌ Do not draw conclusions by eyeballing pixels in a `get_screenshot` raster
- ❌ The implementation worker does not pull live Figma measurements or re-bake shared artifacts; hand missing/stale ones back to Root to update
- ❌ Design-spec annotated values do not go into project docs (AGENTS/CLAUDE/knowledge/README) — docs follow the real code data and cite code constants / token definition paths; design values stay in the `.specs/` frozen artifacts and the final plan
- ✅ All HTML numbers are pt (the scale is applied once during baking); size ← metadata, spacing ← variable_defs tokens + design_context itemSpacing, structure ← design_context
- ✅ Set the icon box from the outer-frame size; with Code Connect, prefer resolving to the real component

## Where this sits in plan-first delivery

- **Root/planning → source prep**: per "Timing and artifact directory", generate and show `figma-*.png`, `figma-*.html` and `preview.html` before the Plan is finalized; the Default stage reuses them and checks them against the nodes the final plan selected. Without native Plan, complete this before the first source write.
- Also record the Figma file/node/version (when the provider supplies it) and the SHA-256 of every frozen artifact; with no immutable version, the bundle digest of this frozen artifact set is the design identity for UI review, and no mutable latest is pulled during acceptance.
- If an artifact exposes new observable behavior, scope, architecture or acceptance decisions, Root must return to DISCOVER/PLAN_READY and update the authoritative plan; a later-generated HTML/PNG must not silently override the final plan.
- **implementation owner**: implements from the frozen HTML/PNG, does not pull live design measurements.
- **ui-reviewer**: after a runnable build PASSes, compares visually against the frozen PNG per strictness and cases; exact sizes come from the HTML.

## Why (core)

Numbers in `get_design_context`'s generated code may be snapped to the framework scale; use `get_metadata` for exact pixels and `get_variable_defs` for tokens, converted uniformly to pt when freezing.
