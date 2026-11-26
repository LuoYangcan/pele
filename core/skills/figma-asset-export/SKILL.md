---
name: figma-asset-export
description: Export custom iOS icons, illustrations or logos from Figma and wire them in following the target project's asset, bundle and scale conventions. Skip when there are no custom assets, the target is not iOS, or the user exports by hand.
---

# figma-asset-export

Decide first whether a graphic should be exported at all, then use Figma's exported file; never redraw it from path data.

## Read the target project's conventions first

The project's existing rules for asset source, asset catalog/bundle and scale take precedence over this skill. Read the project's AGENTS file, asset rules and neighboring assets first; use the generic defaults below only when the project has no rule.

- Project with its own asset rule doc: that rule is the single source for asset source, bundle and scale, and its exceptions override this skill.
- Generic iOS project: assets go into the target's asset catalog; bitmaps ship matching `@1x`, `@2x` and `@3x` unless the project says otherwise.

## Choose and export

| Graphic | Handling |
|---|---|
| Design-system component or a suitable SF Symbol | Do not export; reuse the component/SF Symbol. |
| Simple monochrome shape an SF Symbol can approximate | Prefer the SF Symbol; export only for pixel-level requirements. |
| Custom icon, illustration, logo, multi-color or brand graphic | Export and use the source file. |

1. Call `get_design_context` on the asset node and use its asset download URL; `get_screenshot` is a whole-node raster, not an asset file.
2. Freeze the SVG/PNG into `.specs/<slug>-assets/` and record file/node/version (when available) and SHA-256.
3. Keep Figma's export frame and optical padding. If the SVG is cropped to the glyph bbox, correct the export box to the outer-frame size from metadata.

## Format and rendering

- Monochrome scalable icons: SVG preferred; render as template per the project's practice and tint with the project's semantic color/token, never a baked-in color.
- Multi-color vectors, illustrations and logos: SVG, original rendering.
- Photos, complex gradients or bitmaps: PNG, with scales per the project rule above.

Freeze exported assets and their render mode/tint during planning; implementers only wire in frozen assets, and a changed design source goes back to Root for re-freezing. The measurement HTML from `figma-precise-extract` is for layout only and never a basis for redrawing icons.
