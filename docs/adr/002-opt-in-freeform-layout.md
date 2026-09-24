# ADR 002: Opt-in freeform placement in Markdown

- Status: Accepted
- Date: 2026-09-24

## Context

ADR 001 kept the initial release template-only. Later freeform slides still
need a source-backed position format and a visible compatibility warning.

## Decision

`<!-- layout: freeform -->` opts in one slide. Each Markdown block has a
preceding `<!-- place: x,y,width,height -->` comment, measured as percentages
of the inner slide canvas. Positions must be finite, positive-sized rectangles
entirely within the canvas. Missing or malformed positions are rejected rather
than ignored. Hadar's editor warns that a plain Markdown viewer loses layout.

## Consequences

Content remains ordinary Markdown and edits still pass through Beid. Plain
viewers display the content in source order without the Hadar layout. Positions
are edited in Markdown; drag-and-drop or independent canvas state is not added.
