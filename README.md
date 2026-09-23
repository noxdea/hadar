# Hadar

Hadar (β Centauri) is a Markdown-backed presentation app. Its deck model is a
projection of Beid's source-positioned AST: slide content and slots keep their
source nodes instead of becoming a second mutable copy. Markdown `---`
thematic breaks separate slides, and `<!-- layout: ... -->` selects one of
eight template layouts.

This initial foundation provides deck/slide/slot parsing, three JSONC themes,
layout selection, and a text-only preview tree built with Zaniah's existing
`Describe` vocabulary. It does not yet provide a windowed editor, round-trip
editing, image rendering, file watching, presentation mode, or export.

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

tree = Hadar::Renderer.new.describe(deck.slide(0))
element = Hadar::Renderer.new.build(deck.slide(0))
```

Built-in themes are `minimal`, `dark`, and `warm`. Custom JSONC themes can be
loaded with `Hadar::Theme.load(path)` and passed to `Deck.parse` or
`Deck.open`.

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
