# Hadar

Hadar (β Centauri) is a Markdown-backed presentation app. Its deck model is a
projection of Beid's source-positioned AST: slide content and slots keep their
source nodes instead of becoming a second mutable copy. Markdown `---`
thematic breaks separate slides, and `<!-- layout: ... -->` selects one of
eight template layouts.

This initial foundation provides deck/slide/slot parsing, three JSONC themes,
layout selection, and a text-only preview tree built with Zaniah's existing
`Describe` vocabulary. Beid-backed `<!-- notes: ... -->` comments provide
speaker notes on each slide and are excluded from the visible preview. It does
not yet provide a windowed editor, image rendering, file watching, presentation
mode, or export.

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
```

Built-in themes are `minimal`, `dark`, and `warm`. Custom JSONC themes can be
loaded with `Hadar::Theme.load(path)` and passed to `Deck.parse` or
`Deck.open`.

Slots remain projections of the current Beid document. Replacing a single
node's text applies a Beid edit and returns the refreshed slot; old slots are
stale snapshots. Opened decks save atomically, preserve file permissions, and
refuse to overwrite external changes:

```ruby
deck = Hadar::Deck.open("slides.md")
deck.slide(0).slot(:title).replace_text("Revised title")
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
are not rendered by this initial preview foundation.

## Development

Run the specs with `bundle exec rake`. Hadar depends on Beid, Kochab, and
Zaniah; the latter's declarative `Describe` layer is reused directly.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
