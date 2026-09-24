<h1 align="center">Hadar</h1>

<p align="center">
  <strong>Markdown-backed slide decks with source-preserving editing, live preview, and presentation export</strong>
</p>

<p align="center">
  <a href="https://rubygems.org/gems/hadar"><img src="https://img.shields.io/gem/v/hadar.svg" alt="Gem version"></a>
  <a href="https://rubygems.org/gems/hadar"><img src="https://img.shields.io/gem/dt/hadar.svg" alt="Gem downloads"></a>
  <a href="https://github.com/noxdea/hadar/actions/workflows/main.yml"><img src="https://github.com/noxdea/hadar/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/CRuby-%3E%3D%203.2-cc342d.svg" alt="CRuby 3.2 or newer">
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#editing-and-presenting">Editing and presenting</a> ·
  <a href="#export">Export</a>
</p>

---

Hadar is a Ruby presentation library built around ordinary Markdown files.
[Beid](https://github.com/noxdea/beid) keeps the source-positioned document as
the only editable copy; Hadar projects it into slides, slots, and a live
[Zaniah](https://github.com/noxdea/zaniah) preview. Use its API to embed a
presentation window in an app or export a deck without a GUI.

## Features

- Eight automatic or explicitly selected slide templates, plus opt-in freeform placement
- Source-backed text, image, table-cell, and fenced-code editing with speaker notes
- Three built-in JSONC themes (`minimal`, `dark`, `warm`) and custom themes
- Virtualized slide thumbnails, keyboard navigation, command palette, and a secondary-display presenter view
- Searchable PDF, PNG-sequence, and animated PNG (APNG) export

## Installation

Hadar requires CRuby 3.2 or newer. Install the gem or add `gem "hadar"` to
your Gemfile:

```sh
gem install hadar
```

Hadar is a library; it does not install a `hadar` command. Windowed use
requires a Zaniah-supported display backend. PNG and APNG export use Zaniah's
headless renderer.

## Quick start

Separate slides with Markdown thematic breaks. Hadar selects a layout from
each slide's content unless you add a `layout` comment:

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

deck.slide(1).layout          # => :two_column
deck.slide(1).slot(:left).text # => "Revenue rose 18% year over year."
tree = Hadar::Renderer.new.describe(deck.slide(0))
```

`Renderer#build` returns a Zaniah element for embedding in a preview.

## Editing and presenting

### Source-backed slots

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
Zaniah platform watcher. Reload refuses to discard unsaved local edits. A
watcher is polled by the host's UI loop; successful reloads update the same
deck object and invoke `on_reload`:

```ruby
watcher = deck.watch(on_reload: ->(_deck) { window.request_frame })
watcher.poll(timeout: 0)
```

`deck.reload_if_changed` performs the same safe check without a watcher.

### Application and controls

`Hadar::Application` wires the watcher into attached windows and keeps the
selected slide index on reload. Its presenter view shows the next slide,
current notes, and elapsed time:

```ruby
app = Hadar::Application.new(deck)
main = Zaniah::Platform.open_window(title: "Hadar")
app.attach(main_window: main)
app.run
```

`Application#run` polls and ticks its windows. With a second display, Hadar
opens its own fullscreen presenter window there; an explicitly passed
`presenter_window:` stays under the host's control. After an external reload,
rich-text editors are recreated. Their selection and focus survive only when
they map unambiguously around the edit.

Arrow keys, Page Up/Down, Home, and End navigate slides. `P` or `F5` starts
presentation; `F11` toggles fullscreen; `Escape` exits either mode.
`Ctrl/Cmd-K` opens the command palette, and `Ctrl/Cmd-S` saves an opened deck.

### Notes and block editors

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

### Layouts and themes

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

Built-in themes are `minimal`, `dark`, and `warm`. Custom JSONC themes can be
loaded with `Hadar::Theme.load(path)` and passed to `Deck.parse` or
`Deck.open`. A deck can also set a built-in theme in YAML front matter with
`theme: dark`.

Freeform placement is an explicit per-slide opt-in. Add `<!-- layout: freeform -->`
and one `<!-- place: x,y,width,height -->` immediately before each Markdown
block. Coordinates are percentages of the slide's inner canvas (after theme
margins); every rectangle must fit inside 0–100%. An image-only paragraph is
placed as an image. For example:

```markdown
<!-- layout: freeform -->

<!-- place: 5,8,90,20 -->
# Quarterly report

<!-- place: 10,35,80,50 -->
Revenue increased **18%**.
```

The content stays readable in a plain Markdown viewer, but its placement does
not. Hadar marks freeform slides in the editor with a compatibility warning.
Missing, malformed, or overflowing positions are errors; Hadar never silently
drops a block. Edit the directives in the Markdown source to reposition items.
After an external edit reloads a freeform slide, select its block again before
editing; source-order item numbers may have changed.

`SlideList` creates thumbnail rows only for the visible viewport, using
`Zaniah::UniformList`. `build(width:, height:)` returns a Zaniah element;
`select(index)` updates the selection and invokes `on_select` when supplied:

```ruby
thumbnails = Hadar::SlideList.new(deck, selected: 0,
  on_select: ->(slide, index) { puts "Selected slide #{index + 1}: #{slide.title}" })
element = thumbnails.build(width: 280, height: 640)
```

## Export

```ruby
Hadar::Export::PDF.write(deck, "slides.pdf", font: "/path/to/font.ttf")
Hadar::Export::PNGSequence.write(deck, "slides-png", width: 1280, height: 720)
Hadar::Export::APNG.write(deck, "slides.apng", width: 1280, height: 720,
  duration_ms: 2500)
```

PDF creates one searchable 16:9 page per slide from the same element tree used
by PNG export, including freeform placement.
It needs a TrueType-outline font containing every visible character; without
`font:`, Hadar uses Zaniah's local font database. PDF embeds local PNG and JPEG
images, but rejects remote and other image formats. PNG-sequence export refuses
to replace existing frames. APNG defaults to three seconds per slide and
infinite looping; an existing target requires `overwrite: true`.
`Application#export_png_sequence` and
`#export_apng` wrap the corresponding exporters.

## Development

```sh
bundle install
bundle exec rake
```

Check the 100-slide thumbnail layout/scene-build budget with
`BUDGET=1 bundle exec ruby bench/slide_list.rb`. See the
[template-layout](docs/adr/001-template-layouts.md) and
[freeform-placement](docs/adr/002-opt-in-freeform-layout.md) decisions for the
source model.

## License

Hadar is released under the [MIT License](LICENSE.txt).
