# ADR 001: Template layouts over a free-form canvas

- Status: Accepted
- Date: 2026-09-23

## Context

Markdown is linear and structural, while a free-form slide canvas depends on
coordinates. Silently adding canvas positions would make GUI edits impossible
to preserve in the Markdown source.

## Decision

The first version uses eight named layouts with semantic slots. An optional
`<!-- layout: ... -->` directive selects a template; otherwise Hadar infers
one from the parsed Markdown structure. A free-form canvas is out of scope.

## Consequences

Template content can remain a projection of the source AST and can be edited
without duplicating slide state. Users do not get arbitrary element placement;
reconsider only for a later format that can represent positions explicitly.
