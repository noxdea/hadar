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
- Add poll-based external Markdown reloads with conflict checks that preserve unsaved local edits.
- Add a window host that polls external reloads, retains selected-slide position, and renders a next-slide/notes/elapsed-time presenter view.
- Export the eight slide layouts as searchable PDF pages with embedded TrueType fonts through Okab.
- Add an in-app rich-text body editor that writes supported edits back through Beid while preserving untouched Markdown bytes.
- Add slide navigation, fullscreen controls, a Spica-backed fuzzy command palette, and configurable Zaniah keymaps.
- Export rendered slides as a conflict-safe PNG sequence.
- Save opened decks from the application with Ctrl/Cmd-S or the command palette.
- Add an in-app chooser for all layout slots, with source-preserving image insert/replace, table-cell editing, and fenced-code editing.
- Preserve a rich-text caret or selection across external Markdown reloads when it maps to unchanged source; clear it when mapping would be ambiguous.
- Support source-preserving one-level indent and outdent edits for existing bullet and numbered list items.
- Automatically place Hadar's presenter window fullscreen on a secondary display when available.
