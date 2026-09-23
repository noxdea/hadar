# Changelog

## [Unreleased]

- Add source-projected deck, slide, and slot models from Beid Markdown ASTs.
- Add eight standard layout definitions with directive-based and inferred selection.
- Add validated JSONC theme loading and three bundled themes.
- Add a Zaniah declarative slide preview that resolves local image slots and renders PNG, GIF, and baseline JPEG assets.
- Add Beid-backed slot text replacement and atomic, conflict-aware deck saving.
- Add Beid-backed speaker notes, excluded from slide content and preserved in source.
- Add selectable, viewport-virtualized slide thumbnails using Zaniah::UniformList.
- Expose source-backed rich-text slot editing with inline Markdown formatting and byte-preserving Beid write-back for single text-run edits.
- Insert or replace image-slot Markdown references through Beid, storing absolute local asset paths relative to the deck.
- Render Markdown tables and Antares-highlighted fenced code blocks; add byte-preserving table-cell and fenced-code body edits through Beid.
