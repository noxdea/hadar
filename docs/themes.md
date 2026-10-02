---
layout: guide
title: Themes
description: Select a built-in theme or customize slide colors, typography, and spacing with JSONC.
---

## On this page

- [Built-in themes](#built-in-themes)
- [Custom themes](#custom-themes)
- [Theme validation](#theme-validation)

## Built-in themes

Hadar includes three themes:

| Name | Appearance | Title / body size | Margin / gap |
| --- | --- | --- | --- |
| `minimal` | White background, dark text, blue accent | 44 / 26 | 64 / 24 |
| `dark` | Midnight background, light text, blue accent | 44 / 26 | 64 / 24 |
| `warm` | Paper background, brown text, warm accent | 46 / 27 | 68 / 26 |

Set a theme in the deck's initial YAML front matter:

```markdown
---
theme: dark
---
# Quarterly report
```

Without a theme, Hadar uses `minimal`. The Ruby API can also select one:

```ruby
theme = Hadar::Theme.builtin("dark")
deck = Hadar::Deck.open("slides.md", theme: theme)
```

An explicit `theme:` argument takes precedence over front matter.

## Custom themes

Save a JSONC file, for example `presentation.jsonc`. JSONC accepts comments:

```jsonc
{
  // Unspecified values keep Hadar's defaults.
  "name": "Ocean",
  "colors": {
    "background": "#102638",
    "text": "#f4f8fc",
    "muted": "#b7c9da",
    "accent": "#79b8ff"
  },
  "font": {
    "family": "sans-serif",
    "title_size": 44,
    "body_size": 26
  },
  "spacing": {
    "margin": 64,
    "gap": 24
  }
}
```

Load it through the API:

```ruby
theme = Hadar::Theme.load("presentation.jsonc")
deck = Hadar::Deck.open("slides.md", theme: theme)
```

An opened deck can also use `theme: presentation.jsonc` in front matter; the
path resolves from the deck's directory. A parsed deck resolves it from the
working directory. If the named custom file does not exist, theme selection
falls back to `minimal`; use `Theme.load` explicitly when a missing theme
should raise an error.

## Theme validation

Theme files must be JSON objects no larger than 256 KiB. Unknown keys are
rejected. Omitted sections and values inherit the minimal defaults.

- `name` must be a nonempty string.
- Colors use six- or eight-digit hex strings: `#RRGGBB` or `#RRGGBBAA`.
- `font.family` must be a nonempty string naming an available font family.
- Title and body sizes must be finite numbers from 8 to 160.
- Margin and gap must be finite numbers from 0 to 512.

Make sure the fonts installed on the rendering machine cover your text.
[PDF export](export.md#searchable-pdf) requires a TrueType-outline font with
every visible character; its explicit `font:` argument selects the embedded
font.
