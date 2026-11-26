---
name: figma-precise-extract
description: For Figma UI tasks, freeze exact sizes, spacing and tokens and generate and show an H5 style preview before the Plan is finalized; also used to diagnose icon/spacing drift. Strict by default; skip when there is no Figma design, the change is not UI, or the user explicitly chose loose.
---

# figma-precise-extract

Bake Figma nodes into frozen artifacts (PNG + measurement HTML + `preview.html`). General Figma MCP usage follows the official `figma-design-to-code`; this skill only adds the rules for exact measurement, freezing and preview.

## Triggers and strictness

- Triggers: Figma UI tasks (strict by default, without the user asking); work that needs exact icon size/spacing/tokens; diagnosing "built per Figma but icons/spacing/control sizes do not line up".
- Skip: no design (implementing from a description), non-UI changes, or the user explicitly chose loose (layout skeleton + color tokens only, ±2pt tolerance on spacing/font size, no replication, no `preview.html`).

## Timing, permissions and handoff

- Before the plan is final: Root selects nodes → bakes → generates and shows `preview.html` → handles feedback that changes layout, state or scope → finalizes the plan. A plan diagram does not replace a style preview. Without native Plan, finish before the first source write.
- `<design-assets>` is this round's artifact directory. Native Plan writes PNGs, measurement HTML and `preview.html` only in a scratch/temporary directory the host allows, never source, config or plan files; stricter Plan limits win. When file writes are forbidden, use the host's allowed inline HTML preview and keep the content recoverable; when inline is also unavailable, mark "preview not done" and do not leave Plan or change permissions on your own.
- The final plan records the preview entry (path or inline reference), the visual feedback handled and the remaining differences; a preview not generated, not shown, or only returned as a path is not done. The preview does not authorize implementation; continue through the host's normal plan acceptance.
- Artifacts freeze before the plan is final and are consumed by implementation and ui-reviewer. When an artifact exposes a new behavior, scope or acceptance decision, update the plan first; an artifact never silently overrides the plan.
- After entering Default, copy the artifacts verbatim (write inline content verbatim) into the task worktree's `.specs/<slug>-assets/` without re-fetching. When they are missing or unrecoverable, complete them and show them again before the first source write, without passing a fresh fetch off as the frozen result; existing implementation authorization still holds, and only new material decisions need a question.
- Record the Figma file/node (and version when available) in the plan; acceptance uses the frozen artifacts, never a mutable latest.

## Value sources and baking

- Structure (Auto Layout, alignment, FILL/HUG/FIXED, hierarchy, asset URLs) ← `get_design_context`; numbers in its code are snapped to the framework scale (`gap-2`/`p-4`) and are not measurements.
- Size ← `get_metadata` w/h/x/y (position and size only; no Auto Layout/strokeAlign/effects there). Spacing/radius ← `get_variable_defs` tokens first, cross-checked against the Auto Layout itemSpacing/padding property values; metadata x/y deltas are cross-validation only. Take variant tokens on the exact variant node.
- `get_screenshot` is for layout and look only, never pixel measurement.

1. Use `get_metadata` to confirm the node is the visible component itself, not a padded wrapper/hit area or the whole page.
2. Compute scale = frame width (px) / target device point width (pt) first; never assume 1 (@2x/@3x designs, web designs and designs at another device width are all ≠ 1). Apply it once; every frozen value is pt.
3. Bake `<design-assets>/figma-<nodeId-safe>.html` (`:` in the nodeId becomes `-`): self-contained HTML/CSS encoding per-element size in pt, spacing/position, token name and value, alignment/sizing; annotate icons with "outer frame X×X / glyph ≈ Y". The plan records only artifact paths, scale, tokens, strictness and the asset-export list, not the per-element table.
4. Freeze `get_screenshot({nodeId, maxDimension: 4096})` as a PNG with the same name. PNG = visual truth (color/shadow/gradient/icon look), HTML = measurement truth; strokes/shadows/blur draw outside the layout box and do not count toward size.

## Sparse/degraded fallback

When `get_design_context` (with `forceCode: true`) still returns only metadata or sparse tags, block: do not hand-write a skeleton and move on (it cannot recover asset URLs); re-fetch child by child as the official skill describes, plus:

- Recurse at most 3 levels; only a subtree past that limit gets a hand-written skeleton, with the missing asset URLs flagged as a plan risk for the user or Root to accept.
- When merging into the frozen HTML, child coordinates may be relative to their own origin; offset them by the root-relative x/y from `get_metadata`.

## preview.html (strict)

`<design-assets>/preview.html`, one per slug:

- Self-contained single file with no external resources (no CDN, linked fonts or remote images); font stack `-apple-system,"SF Pro",system-ui`.
- One native-pt-wide phone frame per frozen node (e.g. 402), multiple nodes side by side with flex-wrap, each labeled with node-id and state name; stateful variants get minimal inline JS to toggle, defaulting to the primary state.
- Geometry from the measurement HTML (pt 1:1); color/glass/gradient from the PNG (approximate glass with `backdrop-filter: blur`); icons approximated with inline SVG.
- A caveats banner at the top: approximate replica for judging layout/spacing/structure; the PNG is the visual truth; placeholders such as agentName are replaced with runtime values.
- Show it together with the PNG via the host's file/browser preview or `open`. Update the affected frames, sync PNG/HTML/plan and show again only when the design source, the selected node set or an explicit user visual decision changes; when the user asks to deviate from the design, keep the original PNG and mark the difference. Ordinary implementation, review and verification rounds do not rebuild it.

## Known pitfalls

- `get_design_context` silently drops the GLASS (liquid glass) effect: trust `get_screenshot`, and if needed load `figma-use` and read `node.effects` read-only through `use_figma`.
- The hex of vibrant/tertiary fill tokens is a value flattened on white, not an opaque color: implement it as black@α with α = 1 − hex/255, and verify "fill ≈ background × (1 − α)" by sampling the render on a non-white area. Check annotated stroke values against the render too.
- Icons: metadata reports the outer frame and the SVG viewBox reports the glyph; size the box from the outer frame. When comparing, measure the icon itself (glyph/dot diameter/total width), not just its position; derive SF Symbol pointSize from the measured snapshot rather than copying the design_context font size. Bitmap @1x/2x/3x follow `figma-asset-export`.

## Hard constraints

- The implementation worker does not pull live Figma measurements or re-bake shared artifacts; missing or stale ones go back to Root.
- Annotated design values never go into project docs (AGENTS/CLAUDE/knowledge/README); docs cite code constants/token paths, and design values stay in the `.specs/` artifacts and the plan.
