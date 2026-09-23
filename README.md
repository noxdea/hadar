# Hadar

Hadar (β Centauri) is a Markdown-backed presentation app. Its deck model is a
projection of Beid's source-positioned AST: slide content and slots keep their
source nodes instead of becoming a second mutable copy. Markdown `---`
thematic breaks separate slides, and `<!-- layout: ... -->` selects one of
eight template layouts.

This initial foundation provides deck/slide/slot parsing, three JSONC themes,
layout selection, a text-only preview tree, and virtualized thumbnail rows built
with Zaniah's existing `Describe` and `UniformList` APIs. Beid-backed
`<!-- notes: ... -->` comments provide speaker notes on each slide and are
excluded from the visible preview. Image slots can insert and replace
source-backed Markdown references; absolute asset paths are stored relative to
the opened deck. Hadar does not copy image files, and the preview does not yet
render them. It also does not yet provide a windowed editor, file watching,
presentation mode, or export.

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
is supported for a simple complete bold/italic text run. Edits crossing Markdown
structure, using non-Markdown styles (such as color or font size), or using
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

For a deck created with `Deck.parse`, pass a new path to `save`. Replacing an
existing unrelated path requires `overwrite: true`.

## Layouts

`title`, `title+body`, `two-column`, `image+text`, `full-bleed-image`,
`quote`, `code`, and `blank` are available. Explicit layout directives take
precedence; otherwise Hadar selects a layout from the Beid AST. Image slots
are not rendered by this initial preview foundation. An empty image slot can
use `insert_image(path, alt:)`; an existing single-image slot can use
`replace_image(path)`. Relative paths are retained, while absolute paths to
existing files are made relative to the deck's directory. Insertion and
replacement update only the Markdown image destination or add one image node;
the referenced assets are not copied.

`SlideList` creates thumbnail rows only for the visible viewport, using
`Zaniah::UniformList`; `build(width:, height:)` returns the Zaniah element for
embedding in an application layout. Its `select(index)` method updates the
selection and invokes the optional `on_select` callback. Wezen is not involved
in live thumbnails; it encodes raster frames for export workflows.

## Development

Run the specs with `bundle exec rake`. Check the 100-slide virtual-list
layout/scene-build budget with `BUDGET=1 bundle exec ruby bench/slide_list.rb`;
the headless benchmark skips software pixel rasterization. Hadar depends on
Beid, Kochab, and Zaniah; its declarative `Describe` and `UniformList` APIs are
reused directly.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
