# Hadar

Hadar (β Centauri) is a Markdown-backed presentation app. Its deck model is a
projection of Beid's source-positioned AST: slide content and slots keep their
source nodes instead of becoming a second mutable copy. Markdown `---`
thematic breaks separate slides, and `<!-- layout: ... -->` selects one of
eight template layouts.

Hadar provides deck/slide/slot parsing, three JSONC themes, layout selection, a
declarative preview tree, and virtualized thumbnail rows built with Zaniah's
existing `Describe` and `UniformList` APIs. Its selected-slide editor can switch
among every declared layout slot. Text slots use Zaniah `RichText` and Beid;
image slots provide insert/replace actions, while tables and fenced code expose
source-preserving cell/body editors. Unsupported syntax remains visible but
read-only. Beid-backed
`<!-- notes: ... -->` comments provide speaker notes on each slide and are
excluded from the visible preview. Image slots can insert and replace
source-backed Markdown references; absolute asset paths are stored relative to
the opened deck. Local image slots render through Zaniah's image decoder (PNG,
GIF, and baseline JPEG); relative references resolve from the deck's directory.
Missing, unreadable, and unsupported images fail preview construction with a
`Hadar::Error`. Remote URLs are not fetched. Hadar does not copy image files;
saving continues to write only the Markdown source. Its window host polls for
external Markdown edits and can show a next-slide, notes, and elapsed-time
presenter view. The host supports slide navigation, fullscreen, a fuzzy command
palette, and PNG-sequence export. It does not place windows on separate displays.

## Installation

```ruby
gem "hadar"
```

## Usage

```ruby
require "hadar"

deck = Hadar::Deck.parse(<<~MARKDOWN)
  ---
  theme: dark
  ---
  # Quarterly report

  ## 2026 Q3

  ---

  <!-- layout: two-column -->
  # Revenue

  ::: left
  Revenue rose 18% year over year.
  :::

  ::: right
  New customers: 42
  :::
MARKDOWN

deck.slide(1).layout         # => :two_column
deck.slide(1).slot(:left).text
deck.slide(0).notes           # => nil when no speaker notes are present

tree = Hadar::Renderer.new.describe(deck.slide(0))
element = Hadar::Renderer.new.build(deck.slide(0))

thumbnails = Hadar::SlideList.new(deck, selected: 0,
  on_select: ->(slide, index) { puts "Selected slide #{index + 1}: #{slide.title}" })
list_element = thumbnails.build(width: 280, height: 640)
```

Built-in themes are `minimal`, `dark`, and `warm`. Custom JSONC themes can be
loaded with `Hadar::Theme.load(path)` and passed to `Deck.parse` or
`Deck.open`.

Slots remain projections of the current Beid document. `slot.rich_text` returns
a Zaniah rich-text editor whose bold, italic, link, and code spans come from the
Markdown source. Text edits are written back through Beid immediately when they
stay within one source-backed text run, preserving all other source bytes and
existing markers. Bold and italic may be added to one source-backed run; removal
is supported for a simple complete bold/italic text run. Existing bullet and
numbered list items can be indented or outdented one level at a time through
`RichText#paragraph_style(..., level:)`; edits preserve the original list marker
and reject changes that would reparent neighboring items. Edits crossing Markdown
structure, using non-Markdown styles (such as color or font size), or using other
paragraph styles are rejected rather than flattening or normalizing markup.
Rich-text projection covers headings, paragraphs, block quotes, and text lists;
tables, fenced code blocks, and Markdown strikethrough are not editable through
this API yet.
Slots returned before a successful edit are stale snapshots. Opened decks save
atomically, preserve file permissions, and refuse to overwrite external changes:

```ruby
deck = Hadar::Deck.open("slides.md")
deck.slide(0).slot(:title).replace_text("Revised title")
body = deck.slide(1).slot(:left).rich_text
body.replace(0..."Revenue".bytesize, "Turnover") # Beid updates only that source text run
deck.save
```

Opened decks can detect and reload external changes directly or through the
Zaniah platform watcher. A watcher is polled by the host's UI loop; successful
reloads update the same deck object and invoke `on_reload`. Reload refuses to
discard local unsaved Markdown edits, leaving both the in-memory and on-disk
versions untouched. The host can keep its current slide selection and rebuild
the preview after the callback:

```ruby
watcher = deck.watch(on_reload: ->(_deck) { window.request_frame })
watcher.poll(timeout: 0)
```

`deck.reload_if_changed` performs the same safe check without a platform watcher.
`Hadar::Application` wires this polling into attached windows and retains the
selected slide by index when a reload changes the deck. Its presenter view shows
the next slide, current slide's notes, and elapsed time. While presenting, each
window tick requests a fresh frame so elapsed time stays current:

```ruby
app = Hadar::Application.new(deck)
main = Zaniah::Platform.open_window(title: "Hadar")
presenter = Zaniah::Platform.open_window(title: "Hadar Presenter")
app.attach(main_window: main, presenter_window: presenter)
app.run
```

`Application#run` polls the deck and ticks both attached windows in one loop, so
the preview and presenter stay live together. The host supplies the windows;
Hadar does not position them on separate displays. Rich-text slot editors are
backed by the current Markdown source and recreated after an external reload.
They keep the caret or selection (and editor focus) when selected text maps
unambiguously around one contiguous external edit; if an edit overlaps the
selection or makes the mapping ambiguous, the selection and focus are cleared
rather than moved to unrelated text. Arrow, Page Up/Down, Home, and End navigate
slides; `P` or `F5` starts presentation,
`F11` toggles fullscreen, and `Escape` exits presentation or fullscreen.
`Ctrl/Cmd-K` opens the fuzzy command palette; `Ctrl/Cmd-S` saves an opened deck
through its conflict-aware atomic writer.

PDF export produces one searchable 16:9 page for every slide, including all
eight layouts. Pass a TrueType font that contains every visible character; the
default font is selected from Zaniah's local font database:

```ruby
Hadar::Export::PDF.write(deck, "slides.pdf", font: "/path/to/font.ttf")
```

Okab currently requires TrueType outlines for PDF embedding. Hadar exports local
PNG and JPEG images; remote images and other image formats are rejected.

PNG sequence export renders all slides at the requested dimensions using
Zaniah's headless renderer. It refuses to overwrite existing frames:

```ruby
app.export_png_sequence("slides-png", width: 1280, height: 720)
```

Speaker notes can be written as a one-line or multiline HTML comment. Their
Markdown remains in the source unchanged and does not appear in slide slots or
the preview tree:

```markdown
<!-- notes:
Explain the chart's assumptions.

Call out the remaining risk.
-->
```

Read them with `deck.slide(0).notes`.

Tables in body slots render as rows and cells. `slot.table_rows` returns plain
cell text (including the header as row `0`), and `replace_table_cell(row:,
column:, value:, table: 0)` updates exactly one cell through Beid. Indices are
zero-based. Cell values containing Markdown delimiters, pipes, or newlines are
rejected because Beid cannot currently round-trip escaped table-cell syntax
safely. In the app, choose the table-containing slot, select a table/row/column,
edit the cell text, then use **Apply cell**; invalid edits leave the source
unchanged.

Fenced code blocks render in monospace with syntax colors from Antares/Rouge
when the fence info names a supported language. Unknown language names remain
plain monospace. A slide containing other content besides its title and fenced
blocks uses the body layout so its text and tables remain visible.
`slot.replace_code(text, block: 0)` updates only the body of a
closed fenced block and preserves its fence, info string, and surrounding
Markdown. The app's code pane selects among fenced blocks and applies the edited
body without replacing neighboring content. An omitted final newline is
restored using the existing line ending;
unclosed and indented code blocks are display-only. A replacement containing a
line that would close the fence is rejected.

For a deck created with `Deck.parse`, pass a new path to `app.save(path)`.
Replacing an existing unrelated path requires `overwrite: true`. Opened decks
can use `app.save` or `Ctrl/Cmd-S`; the same external-change check applies.

## Layouts

`title`, `title+body`, `two-column`, `image+text`, `full-bleed-image`,
`quote`, `code`, and `blank` are available. Explicit layout directives take
precedence; otherwise Hadar selects a layout from the Beid AST. Image slots
render local assets through `Zaniah::Image`; use `slot.resolved_image_path` to
resolve a source destination relative to its deck. An empty image slot can use
`insert_image(path, alt:)`; an existing single-image slot can use
`replace_image(path)`. The app exposes these actions from the image slot using
the platform file chooser. Relative paths are retained, while absolute paths to
existing files are made relative to the deck's directory. Insertion and
replacement update only the Markdown image destination or add one image node;
the referenced assets are not copied. If an absolute selected asset lives
outside the deck directory, its saved relative reference points outside that
directory rather than copying the file.

`SlideList` creates thumbnail rows only for the visible viewport, using
`Zaniah::UniformList`; `build(width:, height:)` returns the Zaniah element for
embedding in an application layout. Its `select(index)` method updates the
selection and invokes the optional `on_select` callback. Wezen is not involved
in live thumbnails; it encodes raster frames for export workflows.

## Development

Run the specs with `bundle exec rake`. Check the 100-slide virtual-list
layout/scene-build budget with `BUDGET=1 bundle exec ruby bench/slide_list.rb`;
the headless benchmark skips software pixel rasterization. Hadar depends on
Beid, Antares, Kochab, Okab, Spica, and Zaniah; its declarative `Describe`,
`UniformList`, and input keymap APIs are reused directly.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
