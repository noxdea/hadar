---
layout: guide
title: Editing and presenting
description: Edit source-backed slots, save safely, reload external changes, and present with notes.
---

## On this page

- [Navigate and present](#navigate-and-present)
- [Edit text](#edit-text)
- [Edit images, tables, and code](#edit-images-tables-and-code)
- [Save and reload](#save-and-reload)
- [Speaker notes and presenter view](#speaker-notes-and-presenter-view)
- [Embed Hadar in an application](#embed-hadar-in-an-application)

## Navigate and present

The editor shows slide thumbnails, the current slide preview, and a slot
editor. Select a thumbnail to change slides. Choose a slot such as **Title**,
**Left**, or **Right** to edit its content. Slot names depend on the
[layout](layouts.md).

| Shortcut | Action |
| --- | --- |
| Right, Page Down, Space | Next slide |
| Left, Page Up | Previous slide |
| Home / End | First / last slide |
| P / F5 | Toggle presentation |
| F11 | Toggle fullscreen |
| Escape | Close the command palette, or exit presentation and fullscreen |
| Ctrl-K / Cmd-K | Open the command palette |
| Ctrl-S / Cmd-S | Save the opened deck |

Navigation and presentation shortcuts are inactive while a text field has
focus. The command palette lists slide navigation, presentation, fullscreen,
and save actions.

## Edit text

Text edits go through Beid, preserving source outside the changed range.
`replace_text` requires a slot containing exactly one source node. For
fine-grained changes, use its rich-text projection:

```ruby
deck = Hadar::Deck.open("slides.md")
deck.slide(0).slot(:title).replace_text("Revised title")
body = deck.slide(1).slot(:left).rich_text
body.replace(0..."Revenue".bytesize, "Turnover")
deck.save
```

That example uses the [getting-started deck](index.md#write-a-deck). Rich-text
ranges use UTF-8 byte offsets. Fetch a fresh slot after a successful edit;
reusing an old slot raises a stale-editor error.

Rich-text projection supports headings, paragraphs, block quotes, and text
lists. It displays bold, italic, link, and code spans from the source. Supported
edits must stay within one source-backed text run. Bold and italic can be added
to one run, or removed from a simple complete bold or italic run.

Existing bullet and numbered list items support one-level indentation changes
through `RichText#paragraph_style(..., level:)`. Changes preserve the list
marker and must not reparent neighboring items.

Edits that cross Markdown structure, add styles such as color or font size, or
use other paragraph styles are rejected. Tables, fenced code, and
strikethrough are not editable through the rich-text API; tables and fenced
code have dedicated editors.

## Edit images, tables, and code

### Images

Choose the **Image** slot, then **Insert image…** for an empty slot or
**Replace image…** for an existing image. The file chooser updates the image
reference; it does not copy the asset.

```ruby
image = deck.slide(0).slot(:image)
image.resolved_image_path
image.replace_image("media/chart.png")
```

An empty image slot accepts `insert_image("media/chart.png", alt: "Revenue")`.
Paths resolve relative to an opened deck's directory, or the working directory
for a parsed deck. Absolute paths to existing assets become relative references,
including `../` paths when the asset is outside the deck directory. Keep the
referenced files with your deck when sharing it. Remote image URLs are
unsupported.

### Tables

Select the slot containing the table, choose the table, row, and column, edit
**Cell text**, then choose **Apply cell**. Row `0` is the header; all indices
are zero-based.

```ruby
slot = deck.slide(0).slot(:body)
slot.table_rows
slot.replace_table_cell(row: 1, column: 1, value: "42", table: 0)
```

Values must be plain text. Markdown delimiters, pipes, backslashes, newlines,
and NUL bytes are rejected. Failed edits leave the source unchanged.

### Fenced code

Choose a fenced block in the code pane, edit its body, then choose **Apply
code**. Supported language names receive syntax colors through Antares/Rouge;
unknown languages remain monospace.

```ruby
slot = deck.slide(0).slot(:code)
slot.replace_code("puts 'Hello, Hadar'\n", block: 0)
```

Only closed fenced blocks can be edited. The fence, language name, and
surrounding Markdown remain intact. A missing final newline is restored with
the existing line ending. A line that would close the fence is rejected;
indented and unclosed blocks are display-only.

## Save and reload

Opened decks save atomically and preserve file permissions. Saving refuses to
overwrite external edits or write through a symbolic link. A parsed deck needs
an explicit path on its first save:

```ruby
deck = Hadar::Deck.parse("# New deck\n")
deck.save("new-slides.md")
```

To replace an existing destination deliberately, pass `overwrite: true`.
`Application#save(path, overwrite: ...)` uses the same checks. This flag also
bypasses the external-change protection, so resolve competing edits before
using it.

`Application` watches opened decks by default, keeps the selected slide index
when possible, and rebuilds editors after a successful external reload. Local
unsaved edits prevent reload from discarding either version. Editor selection
and focus survive only when they map unambiguously around the external edit.

For an integration without `Application`, check or watch explicitly:

```ruby
deck = Hadar::Deck.open("slides.md")
deck.reload_if_changed
watcher = deck.watch(on_reload: ->(_deck) { window.request_frame })
watcher.poll(timeout: 0)
```

Poll the watcher from your UI loop and call `watcher.close` when finished.
`reload_if_changed` returns whether it reloaded the document.

## Speaker notes and presenter view

Put a one-line or multiline comment on the relevant slide:

```markdown
<!-- notes:
Explain the chart's assumptions.

Call out the remaining risk.
-->
```

Read notes through `deck.slide(0).notes`. They stay in the source and are
excluded from visible slots, previews, and exported slides.

With a second display, `Application#attach` automatically opens a fullscreen
presenter window there. The presenter view contains the next slide, the current
notes, and elapsed time. An explicitly supplied `presenter_window:` remains
under the host application's control.

## Embed Hadar in an application

Use the [getting-started script](index.md#open-the-presentation-window) for a
complete event loop. For a host app that already has one, attach its windows
and call `app.tick` plus each window's `tick` from that loop.

`Renderer#build` creates an embeddable slide element. `SlideList` uses Zaniah's
virtualized list and builds thumbnail rows for the visible viewport:

```ruby
thumbnails = Hadar::SlideList.new(deck, selected: 0,
  on_select: ->(slide, index) { puts "Slide #{index + 1}: #{slide.title}" })
element = thumbnails.build(width: 280, height: 640)
thumbnails.select(1)
```
