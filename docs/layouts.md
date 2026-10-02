---
layout: guide
title: Layouts and Markdown
description: Split slides, choose semantic layouts, and opt in to positioned blocks when you need them.
---

## On this page

- [Slide boundaries](#slide-boundaries)
- [Templates and slots](#templates-and-slots)
- [Automatic selection](#automatic-selection)
- [Two-column slides](#two-column-slides)
- [Images, quotes, and code](#images-quotes-and-code)
- [Freeform placement](#freeform-placement)

## Slide boundaries

Separate slides with a Markdown thematic break, such as `---` on its own line
with blank lines around it. An initial YAML front-matter block configures the
deck instead of creating a slide boundary.

```markdown
---
theme: minimal
---
# Opening

## A short subtitle

---

# Agenda

- Introductions
- Results
- Questions
```

## Templates and slots

Add `<!-- layout: NAME -->` to select a layout explicitly. The directive uses
the names below; the Ruby API returns symbols such as `:title_body` and
`:two_column`.

| Layout | Ruby symbol | Slots | Content |
| --- | --- | --- | --- |
| `title` | `:title` | `title`, `subtitle` | One or two headings |
| `title+body` | `:title_body` | `title`, `body` | A heading with text, lists, tables, or mixed blocks |
| `two-column` | `:two_column` | `title`, `left`, `right` | A heading with `left` and `right` div directives |
| `image+text` | `:image_text` | `title`, `text`, `image` | A heading, text blocks, and a local image |
| `full-bleed-image` | `:full_bleed_image` | `image` | Image content |
| `quote` | `:quote` | `quote`, `attribution` | A block quote and attribution |
| `code` | `:code` | `title`, `code` | A heading and fenced blocks |
| `blank` | `:blank` | None | An empty template |

Explicit layouts take precedence even when the content does not fit their
slots. Use `title+body` for mixed content rather than forcing a template that
does not display all the blocks.

## Automatic selection

Without a layout comment, Hadar selects the first matching case:

1. A `left` or `right` div directive selects `two-column`.
2. A block quote selects `quote`.
3. Code blocks with only headings alongside them select `code`.
4. Images with text select `image+text`; image-only content selects `full-bleed-image`.
5. No content selects `blank`.
6. One or two headings without other blocks select `title`.
7. Everything else selects `title+body`.

A slide with fenced code plus prose or a table uses `title+body`, keeping the
mixed content visible.

## Two-column slides

Use Beid div directives to assign content to each column:

```markdown
<!-- layout: two-column -->
# Revenue

::: left
Revenue rose **18%** year over year.
:::

::: right
New customers: 42
:::
```

The title becomes `slot(:title)`, and the column content becomes `slot(:left)`
and `slot(:right)`. Plain Markdown viewers may display the `:::` markers.

## Images, quotes, and code

For an image with explanatory text:

```markdown
<!-- layout: image+text -->
# Revenue trend

Revenue increased throughout the quarter.

![Revenue chart](media/chart.png)
```

Use an existing local asset. Relative destinations resolve from the opened
deck's directory. Preview rejects remote URLs and unsupported URI schemes.

For a quotation:

```markdown
<!-- layout: quote -->
> Keep the source editable.

The Hadar team
```

For source code:

````markdown
<!-- layout: code -->
# A Ruby deck

```ruby
deck = Hadar::Deck.open("slides.md")
```
````

## Freeform placement

Freeform is an explicit per-slide opt-in. Each Markdown block needs a preceding
placement comment with `x,y,width,height` percentages:

```markdown
<!-- layout: freeform -->

<!-- place: 5,8,90,20 -->
# Quarterly report

<!-- place: 10,35,80,50 -->
Revenue increased **18%**.
```

Coordinates refer to the inner canvas after theme margins. Width and height
must be positive, and each rectangle must fit within 0–100%. Missing,
malformed, overflowing, or unused placement comments raise an error.

Blocks become source-order slots `item_1`, `item_2`, and so on. An image-only
paragraph becomes an image slot. Edit placement comments in the Markdown
source to reposition blocks; the editor does not provide drag-and-drop
positioning.

Plain Markdown viewers show the content in source order and lose the
placement. Hadar displays a compatibility warning for these slides. After an
external edit reloads a freeform slide, select the block again before editing,
because its item number may have changed.

See the [template layout decision](https://github.com/noxdea/hadar/blob/main/docs/adr/001-template-layouts.md)
and [freeform placement decision](https://github.com/noxdea/hadar/blob/main/docs/adr/002-opt-in-freeform-layout.md)
for the source model.
