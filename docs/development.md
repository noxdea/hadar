---
layout: guide
title: Development
description: Set up a checkout, run the checks, and maintain the website and user guide.
---

## On this page

- [Set up a checkout](#set-up-a-checkout)
- [Run checks](#run-checks)
- [Find the relevant code](#find-the-relevant-code)
- [Maintain the website](#maintain-the-website)
- [Update the screenshot](#update-the-screenshot)

## Set up a checkout

Use CRuby 3.2 or newer:

```sh
git clone https://github.com/noxdea/hadar.git
cd hadar
bundle install
```

For a windowed example, follow [getting started](index.md). Run its script
from the checkout with `bundle exec ruby -Ilib present.rb`.

## Run checks

```sh
bundle exec rake
bundle exec rbs -I sig -r beid -r kochab -r spica -r okab -r alhena -r zaniah validate
gem build --strict hadar.gemspec
```

The default Rake task runs the RSpec suite. Run a specific file with
`bundle exec rspec spec/hadar_spec.rb` while working on a focused change.
CI runs tests on Linux, macOS, and Windows with Ruby 3.2, 3.3, 3.4, and 4.0.

Check the 100-slide thumbnail layout and scene-build budget with:

```sh
BUDGET=1 bundle exec ruby bench/slide_list.rb
```

## Find the relevant code

| Path | Responsibility |
| --- | --- |
| `lib/hadar/deck.rb` | Source-backed deck, edits, safe saves, and reloads |
| `lib/hadar/slide.rb`, `layout.rb`, `slot.rb` | Layout selection and slot projections |
| `lib/hadar/rich_text_projection.rb`, `rich_text_writeback.rb` | Markdown to rich text and supported source-preserving edits |
| `lib/hadar/renderer.rb` | Shared slide tree for preview and export |
| `lib/hadar/application.rb`, `presenter.rb`, `slide_list.rb` | Editor, navigation, presenter, and thumbnails |
| `lib/hadar/export` | PDF, PNG sequence, and APNG |
| `assets/themes` | Built-in JSONC themes |
| `docs/adr` | Source model and layout decisions |

Keep Markdown as the editable source. Rebuild projections after successful
edits; do not introduce a second mutable copy of slide content. Unsupported
edits must leave neighboring source bytes intact.

## Maintain the website

The landing page is `index.html`, styles are in `styles.css`, and the guide
pages are Markdown files in `docs`. Jekyll renders them using
`_layouts/guide.html`. Titles and navigation live in `_config.yml`.
The content remains readable directly on GitHub.

The existing GitHub Pages publishing source is **main / (root)**. Changes
merged into `main` are built and published at
[noxdea.github.io/hadar](https://noxdea.github.io/hadar/). No application
dependencies are needed to build the website. See
[GitHub's Jekyll documentation](https://docs.github.com/en/pages/setting-up-a-github-pages-site-with-jekyll/about-github-pages-and-jekyll)
for the built-in publishing behavior.

To preview with Jekyll 3.10, matching the branch-based Pages build:

```sh
BUNDLE_GEMFILE=docs/Gemfile bundle install
BUNDLE_GEMFILE=docs/Gemfile bundle exec jekyll serve --baseurl ""
```

The separate `docs/Gemfile` keeps Jekyll out of Hadar's runtime dependencies.
Open `http://127.0.0.1:4000/` to check the landing page and guide. Check a
production build, including the `/hadar` base path:

```sh
BUNDLE_GEMFILE=docs/Gemfile bundle exec jekyll build
python3 tools/check_site.py _site
```

Keep guide links relative to their Markdown source files, such as `usage.md`.
GitHub Pages rewrites them to the generated HTML paths. The example decks in
code fences are not separate Jekyll pages. Library files, specs, tools, and
design decisions are excluded from the published site.

## Update the screenshot

The screenshot shows the actual Hadar interface using the getting-started
example. Regenerate it after changing the editor:

```sh
bundle exec ruby -Ilib tools/generate_overview.rb
```

The script writes `docs/media/overview.png` through Zaniah's headless renderer.
Review that image before updating the README and website. The screenshot is
not a browser mockup.
