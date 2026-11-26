---
name: visual-brief
description: When the user explicitly asks for a diagram, visualization or illustration ("draw a diagram", "visualize this", "show it as a diagram"), carry the structure in one inline diagram and the conclusions in 3–5 bullets. Never triggers on its own; plans, proposals and investigation conclusions default to text and tables.
---

# Visual brief

Use only when the user asks for a diagram.

1. One line framing the question.
2. One `mcp__visualize__show_widget` call (follow `mcp__visualize__read_me` first, reading only the sections you need). Without that tool, write a self-contained HTML file to the session temp directory and open it, bringing your own light / dark color variables. Do not publish it as an Artifact unless the user wants a shareable link.
3. 3–5 bullets covering only what the diagram cannot draw: judgments, risks and questions to decide. Do not restate the diagram.

Put only visual elements in the diagram; explanatory text goes in the reply body. Decisions still live in the text plan.
