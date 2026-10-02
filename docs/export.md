---
layout: guide
title: Export
description: Write searchable PDFs, numbered PNG slides, or an animated PNG from the same deck.
---

## On this page

- [Choose an output](#choose-an-output)
- [Searchable PDF](#searchable-pdf)
- [PNG sequence](#png-sequence)
- [Animated PNG](#animated-png)
- [Output limits and troubleshooting](#output-limits-and-troubleshooting)

## Choose an output

All exporters accept a `Hadar::Deck` and work without attaching a native
window. PNG and APNG use Zaniah's headless renderer. Speaker notes stay out of
exported slides; freeform placement is included.

| Format | Use | Default output | Existing destination |
| --- | --- | --- | --- |
| PDF | Searchable handouts and sharing | One 960 × 540 page per slide | Replaced by `PDF.write` |
| PNG sequence | Individual slide images | 1280 × 720 per slide | Matching frame names are refused |
| APNG | An animated slide deck | 1280 × 720, 3 seconds per slide, infinite loop | Refused unless `overwrite: true` |

## Searchable PDF

```ruby
require "hadar"

deck = Hadar::Deck.open("slides.md")
Hadar::Export::PDF.write(deck, "slides.pdf", font: "/path/to/font.ttf")
```

Replace the font path with an installed TrueType-outline font that contains
every visible character. Omit `font:` to use Zaniah's local font database.
CFF-outline fonts and missing glyphs raise an error. For Japanese slides,
provide a TrueType-outline font covering the Japanese text.

PDF uses the same element tree as the PNG renderer, with searchable text and
one 16:9 page per slide. Local PNG and JPEG images are embedded. Remote images
and other image formats are rejected.

`PDF.write` replaces an existing destination. Use a new output path when you
need to keep a previous export. `PDF.render(deck, font: ...)` returns PDF
bytes if your application manages file writing itself.

## PNG sequence

```ruby
Hadar::Export::PNGSequence.write(deck, "slides-png",
  width: 1280, height: 720)
```

This returns the generated paths and writes `slide-001.png`, `slide-002.png`,
and so on. Numbering uses at least three digits, expanding for larger decks.
The output directory is created if needed. Existing matching filenames or
symbolic links cause an error before rendering; unrelated files are retained.
Use a fresh directory for another export.

An application instance can call
`app.export_png_sequence("slides-png", width: 1280, height: 720)`.

## Animated PNG

```ruby
Hadar::Export::APNG.write(deck, "slides.apng",
  width: 1280, height: 720, duration_ms: 2500, loop: 0)
```

Every slide becomes a frame. `duration_ms` applies to each frame and defaults
to `3000`. `loop: 0` repeats indefinitely; a positive value sets the loop
count. To replace an existing regular file, pass `overwrite: true`.
Symbolic-link destinations are refused.

`APNG.render(deck, ...)` returns the encoded bytes. `Application#export_apng`
accepts the same output options:

```ruby
app.export_apng("slides.apng", duration_ms: 2500, overwrite: true)
```

## Output limits and troubleshooting

PNG and APNG dimensions must be positive integers totaling at most
32,000,000 pixels per frame. APNG duration must be a positive integer that
fits its reduced 16-bit frame-delay numerator; loop count must be a
nonnegative integer.

If rendering fails:

- **Missing image:** keep the referenced asset at the path resolved from the
  deck directory. The editor saves references and does not copy files.
- **Remote image:** replace the URL with a local asset; slide preview and
  export do not fetch remote images.
- **PDF font error:** use a TrueType-outline font containing every character.
- **PNG filename collision:** export into a fresh directory.
- **APNG destination exists:** choose another filename or deliberately use
  `overwrite: true`.
- **Rejected freeform position:** check that every block has a valid placement
  and fits inside the inner canvas.

APNG builds the animation in memory. For many high-resolution slides, use a
PNG sequence to write each frame separately.
