# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "zlib"

RSpec.describe Hadar do
  def slide(markdown)
    Hadar::Deck.parse(markdown).slide(0)
  end

  def png_fixture
    chunk = lambda do |type, data|
      [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
    end
    header = [1, 1].pack("N2") + [8, 6, 0, 0, 0].pack("C5")
    pixels = Zlib::Deflate.deflate("\x00\xff\x00\x00\xff".b)
    "\x89PNG\r\n\x1a\n".b + chunk.call("IHDR", header) + chunk.call("IDAT", pixels) + chunk.call("IEND", "".b)
  end

  def jpeg_fixture
    segment = lambda do |marker, data|
      "\xff".b + [marker, data.bytesize + 2].pack("Cn") + data
    end
    quantization = segment.call(0xdb, [0, *Array.new(64, 1)].pack("C*"))
    dc = [0, 1, 1, *Array.new(14, 0), 0, 7]
    ac = [0x10, 1, *Array.new(15, 0), 0]
    huffman = segment.call(0xc4, (dc + ac).pack("C*"))
    frame_data = [8, 8, 8, 1, 1, 0x11, 0].pack("CnnC*")
    frame = segment.call(0xc0, frame_data)
    scan = segment.call(0xda, [1, 1, 0, 0, 63, 0].pack("C*"))
    "\xff\xd8".b + quantization + huffman + frame + scan + "\x3f\xff\xd9".b
  end

  describe Hadar::Deck do
    it "projects Beid nodes into slides and slots without copying their source" do
      markdown = <<~MARKDOWN
        ---
        theme: dark
        ---
        # Quarterly report
        ## 2026 Q3

        ---
        <!-- layout: title+body -->
        # Sales

        Revenue rose **18%**.
      MARKDOWN
      deck = described_class.parse(markdown)

      expect(deck.length).to eq(2)
      expect(deck.theme.name).to eq("Midnight")
      expect(deck.slide(1).layout).to eq(:title_body)
      sales_heading = deck.document.root.children.find do |node|
        node.type == :heading && node.children.any? { |child| child.text == "Sales" }
      end
      expect(deck.slide(1).slot(:title).nodes.first).to equal(sales_heading)
      expect(deck.slide(1).slot(:body).text).to include("Revenue rose")
      expect(deck.slide(1).slot(:body).markdown).to include("**18%**")
    end

    it "uses the explicit layout directive before inference" do
      expect(slide("# Only title\n\n<!-- layout: blank -->\n").layout).to eq(:blank)
    end

    it "projects one-line and multiline speaker notes without rendering them" do
      one_line = slide("# Title\n\n<!-- notes: Say this aloud. -->\n\nVisible text.\n")
      multiline = slide(File.read(File.join(__dir__, "fixtures", "speaker_notes.md")))

      expect(one_line.notes).to eq("Say this aloud.")
      expect(multiline.notes).to eq("Call out the revised target.\n\nEmphasize the remaining risk.")
      expect(multiline.slot(:body).text).to eq("This paragraph is visible.")
      description = Hadar::Renderer.new.describe(multiline)
      expect(description.children.flat_map { |node| [node, *node.children] }
        .map { |node| node.props[:text] }.compact)
        .to eq(["Launch plan", "This paragraph is visible."])
    end

    it "preserves the speaker-notes comment byte-for-byte through edit and save" do
      original = File.binread(File.join(__dir__, "fixtures", "speaker_notes.md"))
      notes = original.match(/<!-- notes:.*?-->/m).to_s.b

      Dir.mktmpdir do |directory|
        path = File.join(directory, "deck.md")
        File.binwrite(path, original)
        deck = described_class.open(path)
        deck.slide(0).slot(:title).replace_text("Launch sequence")
        deck.save

        expect(File.binread(path)).to eq(original.sub("# Launch plan\n", "# Launch sequence\n").b)
        expect(File.binread(path)).to include(notes)
      end
    end

    it "selects each standard layout from the AST" do
      examples = {
        title: "# Title\n",
        title_with_subtitle: "# Title\n\n## Subtitle\n",
        title_body: "# Title\n\nBody\n",
        two_column: "::: left\nOne\n:::\n\n::: right\nTwo\n:::\n",
        image_text: "<!-- layout: image+text -->\n# Title\n\nText ![chart](chart.png)\n",
        full_bleed_image: "<!-- layout: full-bleed-image -->\n![chart](chart.png)\n",
        quote: "> A quotation\n",
        code: "```ruby\nputs :ok\n```\n",
        blank: "<!-- layout: blank -->\n"
      }

      examples.each do |layout, markdown|
        expected = layout == :title_with_subtitle ? :title : layout
        expect(slide(markdown).layout).to eq(expected)
      end
    end

    it "retains explicitly empty slides only when the source asks for blank" do
      expect(described_class.parse("---\n").slides).to be_empty
      expect(described_class.parse("<!-- layout: blank -->\n").slide(0).layout).to eq(:blank)
    end

    it "projects list and fenced-code block text from source nodes" do
      list = slide("# Tasks\n\n- first\n- second\n")
      code = slide("```ruby\nputs :ok\n```\n")

      expect(list.slot(:body).text).to eq("• first\n• second")
      expect(code.slot(:code).text).to eq("puts :ok\n")
    end

    it "replaces an image destination without changing its caption, title, or surrounding Markdown" do
      original = "<!-- layout: full-bleed-image -->\n\n![Quarterly *revenue*](media/old.png \"Chart source\")\n\n# Keep this heading\n"
      original = original.gsub("\n", "\r\n")
      expected = original.sub("media/old.png", "../assets/new%20chart.jpg")
      deck = described_class.parse(original)
      slot = deck.slide(0).slot(:image)

      expect(slot.image_path).to eq("media/old.png")
      updated = slot.replace_image("../assets/new chart.jpg")

      expect(deck.document.source).to eq(expected)
      expect(updated.image_path).to eq("../assets/new chart.jpg")
      expect(updated.markdown).to include("![Quarterly *revenue*](../assets/new%20chart.jpg \"Chart source\")")
      expect { slot.replace_image("stale.png") }.to raise_error(Hadar::Error, /stale/)
    end

    it "inserts an image into an empty image slot using a path relative to the deck" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "slides.md")
        image_path = File.join(directory, "media", "sales chart.png")
        FileUtils.mkdir_p(File.dirname(image_path))
        File.binwrite(image_path, "image fixture")
        original = "<!-- layout: image+text -->\r\n# Sales\r\n\r\nQuarterly growth.\r\n"
        File.binwrite(path, original)
        deck = described_class.open(path)
        slot = deck.slide(0).slot(:image)

        expect(slot).to be_empty
        updated = slot.insert_image(image_path, alt: "Sales chart")
        expected = original + "\r\n![Sales chart](media/sales%20chart.png)"

        expect(deck.document.source).to eq(expected)
        expect(updated.image_path).to eq("media/sales chart.png")
        expect(updated.nodes.one?).to be(true)
        expect(deck.save).to equal(deck)
        expect(File.binread(path)).to eq(expected.b)
      end
    end

    it "rejects image insertion into non-image layouts and unsaved decks cannot relativize absolute paths" do
      deck = described_class.parse("# Title\n\nBody.\n")
      slot = deck.slide(0).slot(:image)

      expect { slot.insert_image("media/chart.png") }
        .to raise_error(Hadar::Error, /image layout slot/)

      image_deck = described_class.parse("<!-- layout: full-bleed-image -->\n")
      expect { image_deck.slide(0).slot(:image).insert_image("/tmp/chart.png") }
        .to raise_error(Hadar::Error, /opened deck/)
    end

    it "replaces one table cell and one fenced-code body while preserving all surrounding Markdown bytes" do
      original = <<~'MARKDOWN'.gsub("\n", "\r\n")
        <!-- layout: title+body -->
        # Source

        | Name | Value |
        | --- | ---: |
        | first | **keep** |
        | old | 3 |

        <!-- notes: untouched -->

        ~~~ruby
        puts "old"
        ~~~
      MARKDOWN
      expected = original.sub("| old | 3 |", "| revised cell | 3 |")
        .sub("puts \"old\"\r\n", "puts \"new\"\r\n")
      deck = described_class.parse(original)

      body = deck.slide(0).slot(:body)
      expect(body.table_rows).to eq([%w[Name Value], %w[first keep], %w[old 3]])
      updated = body.replace_table_cell(row: 2, column: 0, value: "revised cell")
      expect(updated.table_rows[2]).to eq(["revised cell", "3"])
      deck.slide(0).slot(:body).replace_code("puts \"new\"")

      expect(deck.document.source).to eq(expected)
      expect(deck.document.source).to include("| first | **keep** |\r\n", "<!-- notes: untouched -->\r\n", "~~~ruby\r\n")
    end

    it "rejects table and code edits that cannot be isolated from neighboring Markdown" do
      source = "<!-- layout: title+body -->\n# Table\n\n| A | B |\n| --- | --- |\n| one | two |\n\n```ruby\nputs 1\n```\n"
      deck = described_class.parse(source)
      body = deck.slide(0).slot(:body)

      expect { body.replace_table_cell(row: 1, column: 0, value: "one | extra") }
        .to raise_error(ArgumentError, /plain text/)
      expect { body.replace_table_cell(row: 1, column: 0, value: "new *value*") }
        .to raise_error(ArgumentError, /must be plain text/)
      expect { body.replace_table_cell(row: -1, column: 0, value: "bad") }
        .to raise_error(IndexError, /must not be negative/)
      expect { body.replace_code("puts 1\n```\nputs 2") }
        .to raise_error(ArgumentError, /terminate its fenced block/)
      expect(deck.document.source).to eq(source)

      unclosed = described_class.parse("<!-- layout: title+body -->\n# Code\n\n```ruby\nputs 1\n")
      expect { unclosed.slide(0).slot(:body).replace_code("puts 2") }
        .to raise_error(Hadar::Error, /only closed fenced code blocks/)
      expect(unclosed.document.source).to end_with("puts 1\n")
    end

    it "replaces a slot through Beid and atomically saves only the selected source range" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "deck.md")
        original = <<~'MARKDOWN'
          ---
          theme: dark
          ---
          # **Keep _this_ title**

          ---

          <!-- layout: title+body -->
          # **Old title**

          Use *markers* and `code` here.

          - keep this list marker

          ---

          # Finish
        MARKDOWN
        original = original.gsub("\n", "\r\n")
        expected = original.sub("# **Old title**", "# Revised title")
        File.binwrite(path, original)
        File.chmod(0o640, path)
        deck = Hadar::Deck.open(path)
        previous_slot = deck.slide(1).slot(:title)

        current_slot = previous_slot.replace_text("Revised title")
        expect(deck.document.source).to eq(expected)
        expect(current_slot.text).to eq("Revised title")
        expect { previous_slot.replace_text("stale") }
          .to raise_error(Hadar::Error, /stale/)

        expect(deck.save).to equal(deck)
        expect(File.binread(path)).to eq(expected.b)
        expect(File.stat(path).mode & 0o777).to eq(0o640)
        expect(Dir.children(directory)).to eq(["deck.md"])
      end
    end

    it "projects mixed Markdown formatting into RichText and writes a run edit without changing other bytes" do
      original = <<~'MARKDOWN'
        ---
        theme: warm
        ---

        # Keep *this* heading

        Body with **bold** and _italic_, `code`, and [link](https://example.test/a_(b)).

        <!-- notes: Keep these notes. -->
      MARKDOWN
      original = original.gsub("\n", "\r\n")
      expected = original.sub("bold", "更新").sub("link", "source")

      Dir.mktmpdir do |directory|
        path = File.join(directory, "deck.md")
        File.binwrite(path, original)
        deck = described_class.open(path)
        rich_text = deck.slide(0).slot(:body).rich_text

        expect(rich_text).to be_a(Zaniah::UI::RichText)
        expect(rich_text.editable?).to be(true)
        expect(rich_text.text).to eq("Body with bold and italic, code, and link.")
        expect(rich_text.runs.find { |run| run[:text].include?("bold") }[:bold]).to be(true)
        expect(rich_text.runs.find { |run| run[:text].include?("italic") }[:italic]).to be(true)
        expect(rich_text.runs.find { |run| run[:text].include?("link") }[:link])
          .to eq("https://example.test/a_(b)")
        expect(rich_text.runs.find { |run| run[:text] == "code" }[:font]).to eq("monospace")

        offset = rich_text.text.index("bold")
        rich_text.replace(offset...(offset + "bold".bytesize), "更新")
        offset = rich_text.text[0...rich_text.text.index("link")].bytesize
        rich_text.replace(offset...(offset + "link".bytesize), "source")

        expect(deck.document.source).to eq(expected)
        expect(deck.slide(0).slot(:body).markdown).to include("**更新** and _italic_, `code`, and [source](https://example.test/a_(b))")
        deck.save
        expect(File.binread(path)).to eq(expected.b)
      end
    end

    it "rejects rich-text style changes rather than normalizing source markup" do
      source = "# Title\n\nPlain text.\n"
      deck = described_class.parse(source)
      rich_text = deck.slide(0).slot(:body).rich_text

      expect { rich_text.apply(0...5, color: "#ff0000") }
        .to raise_error(Hadar::Error, /only bold and italic/)
      expect(deck.document.source).to eq(source)
    end

    it "writes simple bold changes through Beid without rewriting adjacent Markdown" do
      source = "# Title\n\nPlain **bold** and _italic_.\n"
      deck = described_class.parse(source)
      rich_text = deck.slide(0).slot(:body).rich_text

      rich_text.apply(0...5, bold: true)
      expect(deck.document.source).to eq("# Title\n\n**Plain** **bold** and _italic_.\n")

      rich_text.apply(0...5, bold: nil)
      expect(deck.document.source).to eq(source)
    end

    it "edits formatted list text without changing list markers or other items" do
      source = "# Tasks\n\n- **first**\n- second\n"
      deck = described_class.parse(source)
      rich_text = deck.slide(0).slot(:body).rich_text

      expect(rich_text.text).to eq("• first\n• second")
      offset = rich_text.text[0...rich_text.text.index("first")].bytesize
      rich_text.replace(offset...(offset + "first".bytesize), "done")

      expect(deck.document.source).to eq("# Tasks\n\n- **done**\n- second\n")
      expect(deck.slide(0).slot(:body).markdown).to eq("- **done**\n- second\n")
    end

    it "rejects text edits crossing inline markup without flattening the source" do
      source = "# Title\n\nPlain **bold** text.\n"
      deck = described_class.parse(source)
      rich_text = deck.slide(0).slot(:body).rich_text

      expect { rich_text.replace(0...10, "replacement") }
        .to raise_error(Hadar::Error, /one Markdown text run/)
      expect(deck.document.source).to eq(source)
    end

    it "rejects a stale RichText editor after another Beid edit changes its document" do
      deck = described_class.parse("# Title\n\nOriginal text.\n")
      rich_text = deck.slide(0).slot(:body).rich_text
      deck.slide(0).slot(:body).replace_text("External edit.")
      source = deck.document.source

      expect { rich_text.insert(rich_text.text.bytesize, " stale") }
        .to raise_error(Hadar::Error, /rich text editor is stale/)
      expect(deck.document.source).to eq(source)
    end

    it "refuses to overwrite a file changed outside Hadar" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "deck.md")
        File.binwrite(path, "# Original\n")
        deck = Hadar::Deck.open(path)
        deck.slide(0).slot(:title).replace_text("Hadar edit")
        File.binwrite(path, "# External edit\n")

        expect { deck.save }.to raise_error(Hadar::Error, /changed since it was opened/)
        expect(File.binread(path)).to eq("# External edit\n")
      end
    end

    it "reloads external Markdown in-place through the polling watcher and keeps slide selection" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "deck.md")
        original = "# First\n\nOpening.\n\n---\n\n# Second\n\nOriginal body.\n"
        updated = "# First\n\nOpening.\n\n---\n\n# Revised second\n\nExternal body.\n"
        File.write(path, original)
        deck = described_class.open(path)
        thumbnails = Hadar::SlideList.new(deck, selected: 1)
        stale_slot = deck.slide(1).slot(:title)
        callbacks = []
        backend = Object.new
        backend.define_singleton_method(:poll) { |timeout:| [] }
        backend.define_singleton_method(:close) { true }
        expect(Zaniah::Platform).to receive(:watch).with(deck.source_path, latency: 0.05).and_return(backend)
        watcher = deck.watch(on_reload: ->(changed_deck) { callbacks << changed_deck })

        File.write(path, updated)

        expect(deck.external_change?).to be(true)
        expect(watcher.poll(timeout: 0)).to be(true)
        expect(deck.document.source).to eq(updated)
        expect(deck.slide(1).title).to eq("Revised second")
        expect(thumbnails.selected_index).to eq(1)
        expect(callbacks).to eq([deck])
        expect(deck.external_change?).to be(false)
        expect(watcher.poll(timeout: 0)).to be(false)
        expect { stale_slot.replace_text("stale") }.to raise_error(Hadar::Error, /stale/)

        watcher.close
      end
    end

    it "preserves local Markdown edits and the external file when reload conflicts" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "deck.md")
        File.write(path, "# Original\n")
        deck = described_class.open(path)
        deck.slide(0).slot(:title).replace_text("Local edit")
        local_source = deck.document.source
        File.write(path, "# External edit\n")

        expect { deck.reload_if_changed }
          .to raise_error(Hadar::Error, /local edits and external changes/)
        expect(deck.document.source).to equal(local_source)
        expect(File.read(path)).to eq("# External edit\n")
      end
    end

    it "keeps the current document when an external deck is not valid UTF-8" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "deck.md")
        File.write(path, "# Original\n")
        deck = described_class.open(path)
        original_document = deck.document
        File.binwrite(path, "# Invalid \xFF\n".b)

        expect { deck.reload_if_changed }.to raise_error(Hadar::Error, /not valid UTF-8/)
        expect(deck.document).to equal(original_document)
      end
    end

    it "rejects ambiguous multi-node slots without changing the document" do
      deck = described_class.parse("# Title\n\nFirst paragraph.\n\nSecond paragraph.\n")
      original = deck.document.source

      expect { deck.slide(0).slot(:body).replace_text("replacement") }
        .to raise_error(ArgumentError, /exactly one node/)
      expect(deck.document.source).to equal(original)
    end

    it "requires explicit overwrite when saving a parsed deck over an existing file" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "deck.md")
        new_path = File.join(directory, "new-deck.md")
        File.binwrite(path, "# Existing\n")
        deck = described_class.parse("# New\n")

        expect { deck.save(path) }.to raise_error(Hadar::Error, /overwrite: true/)
        expect(File.binread(path)).to eq("# Existing\n")
        deck.save(path, overwrite: true)
        expect(File.binread(path)).to eq("# New\n")

        created = described_class.parse("# Created\n")
        created.slide(0).slot(:title).replace_text("Created safely")
        created.save(new_path)
        expect(File.binread(new_path)).to eq("# Created safely\n")
      end
    end
  end

  describe Hadar::Layout do
    it "normalizes supported spelling aliases and rejects unknown layouts" do
      expect(described_class.fetch("image+text").name).to eq(:image_text)
      expect { described_class.fetch("free-form") }.to raise_error(ArgumentError)
    end
  end

  describe Hadar::Theme do
    it "loads all bundled themes as JSONC through Kochab" do
      expect(%w[minimal dark warm].map { |name| described_class.builtin(name).name })
        .to eq(%w[Minimal Midnight Paper])
    end

    it "rejects invalid colors, sizes, and unexpected keys" do
      expect { described_class.new("colors" => {"background" => "red"}) }
        .to raise_error(Hadar::Error, /color/)
      expect { described_class.new("font" => {"body_size" => 999}) }
        .to raise_error(Hadar::Error, /body_size/)
      expect { described_class.new("extra" => true) }
        .to raise_error(Hadar::Error, /unknown theme keys/)
    end
  end

  describe Hadar::Renderer do
    it "creates and builds the preview with Zaniah's existing declarative vocabulary" do
      slide = Hadar::Deck.parse("# Welcome\n\nHello, world!\n", theme: "warm").slide(0)
      renderer = described_class.new
      description = renderer.describe(slide)

      expect(description).to be_a(Zaniah::Describe::Node)
      expect(description.props.fetch(:background)).to eq("#fbf5e9")
      expect(description.children.map { |node| node.props[:text] }.compact)
        .to eq(["Welcome", "Hello, world!"])
      expect(renderer.build(slide)).to be_a(Zaniah::Element)
      expect(renderer.surface(slide).empty?).to be(false)
    end

    it "resolves deck-relative PNG and JPEG image slots and paints them through Zaniah" do
      Dir.mktmpdir do |directory|
        media = File.join(directory, "media")
        FileUtils.mkdir_p(media)
        deck_path = File.join(directory, "slides.md")
        window = Zaniah::Platform.open_window(backend: :headless, width: 320, height: 360)

        begin
          {"chart image.png" => png_fixture, "photo.jpg" => jpeg_fixture}.each do |filename, bytes|
            image_path = File.join(media, filename)
            File.binwrite(image_path, bytes)
            markdown_destination = filename.gsub(" ", "%20").then { |name| "media/#{name}" }
            File.binwrite(deck_path, "<!-- layout: full-bleed-image -->\n![Chart](#{markdown_destination})\n")
            deck = Hadar::Deck.open(deck_path)
            renderer = described_class.new
            description = renderer.describe(deck.slide(0))

            expect(description.children.map(&:type)).to eq([:image])
            expect(description.children.first.props.fetch(:path)).to eq(File.realpath(image_path))
            image = renderer.build(deck.slide(0)).children.first
            expect(image).to be_a(Zaniah::Image)
            window.render(renderer.build(deck.slide(0)), present: false)
          end

          image_path = File.join(media, "inline.png")
          File.binwrite(image_path, png_fixture)
          File.write(deck_path, "<!-- layout: image+text -->\n# Results\n\nQuarterly totals.\n\n![Chart](media/inline.png)\n")
          deck = Hadar::Deck.open(deck_path)
          renderer = described_class.new
          expect(renderer.describe(deck.slide(0)).children.map(&:type)).to include(:image)
          window.render(renderer.build(deck.slide(0)), present: false)
        ensure
          window.close
        end
      end
    end

    it "renders tables and Antares-highlighted fenced code in source order" do
      markdown = <<~MARKDOWN
        # Example

        | Name | Value |
        | :--- | ---: |
        | answer | 42 |

        ```ruby
        puts "ok"
        # note
        ```
      MARKDOWN
      slide = Hadar::Deck.parse(markdown).slide(0)
      renderer = described_class.new
      description = renderer.describe(slide)
      tree = []
      visit = ->(node) { tree << node; node.children.each { |child| visit.call(child) } }
      visit.call(description)

      table = tree.find { |node| node.type == :table }
      code = tree.find { |node| node.type == :code_block }
      tokens = tree.select { |node| node.type == :code_token }

      expect(slide.layout).to eq(:title_body)
      expect(table.props.fetch(:rows)).to eq([["Name", "Value"], ["answer", "42"]])
      expect(table.props.fetch(:alignments)).to eq([:left, :right])
      expect(code.props.fetch(:language)).to eq("ruby")
      expect(tokens.map { |token| token.props.fetch(:color) }).to include(slide.theme.colors.fetch("accent"), slide.theme.colors.fetch("muted"))
      expect(description.children.map(&:type)).to eq([:text, :table, :code_block])

      window = Zaniah::Platform.open_window(backend: :headless, width: 640, height: 480)
      begin
        expect { window.render(renderer.build(slide), present: false) }.not_to raise_error
      ensure
        window.close
      end
    end

    it "reports missing, unsupported, and remote image sources clearly" do
      Dir.mktmpdir do |directory|
        deck_path = File.join(directory, "slides.md")
        renderer = described_class.new
        File.write(deck_path, "<!-- layout: full-bleed-image -->\n![Missing](media/missing.png)\n")
        missing_deck = Hadar::Deck.open(deck_path)

        expect { renderer.build(missing_deck.slide(0)) }
          .to raise_error(Hadar::Error, /image file not found: media\/missing\.png/)

        FileUtils.mkdir_p(File.join(directory, "media"))
        File.write(File.join(directory, "media", "diagram.svg"), "<svg/>")
        File.write(deck_path, "<!-- layout: full-bleed-image -->\n![Unsupported](media/diagram.svg)\n")
        unsupported_deck = Hadar::Deck.open(deck_path)

        expect { renderer.build(unsupported_deck.slide(0)) }
          .to raise_error(Hadar::Error, /cannot render image .*unsupported image format/)

        File.write(deck_path, "<!-- layout: full-bleed-image -->\n![Remote](https://example.test/chart.png)\n")
        remote_deck = Hadar::Deck.open(deck_path)

        expect { renderer.build(remote_deck.slide(0)) }
          .to raise_error(Hadar::Error, /remote image URLs are not supported in slide preview/)
      end
    end
  end

  describe Hadar::SlideList do
    it "builds selectable thumbnails as a virtual UniformList" do
      deck = Hadar::Deck.parse("# First\n\n---\n\n# Second\n")
      selected = []
      list = described_class.new(deck, on_select: ->(slide, index) { selected << [slide, index] })

      element = list.build(width: 320, height: 360)
      window = Zaniah::Platform.open_window(backend: :headless, width: 320, height: 360)
      begin
        window.render(element, present: false)

        expect(element).to be_a(Zaniah::UniformList)
        expect(element.visible_range).to eq(0...2)
        expect(element.children.first.handlers).to include(:click)
        expect(element.children.first.children.first).to be_a(Zaniah::Element)
        expect(list.select(1)).to equal(deck.slide(1))
        expect(list.selected_index).to eq(1)
        expect(selected).to eq([[deck.slide(1), 1]])
        expect { list.select(2) }.to raise_error(IndexError)
      ensure
        window.close
      end
    end

    it "only renders viewport thumbnails while scrolling a 100-slide deck" do
      markdown = Array.new(100) { |index| "# Slide #{index + 1}" }.join("\n\n---\n\n")
      deck = Hadar::Deck.parse(markdown)
      rendered = []
      renderer = instance_double(Hadar::Renderer)
      allow(renderer).to receive(:build) do |slide|
        rendered << slide.index
        Zaniah::Div.new
      end
      list = described_class.new(deck, renderer: renderer, row_height: 180)
      element = list.build(width: 320, height: 180)

      context = Struct.new(:window).new(Struct.new(:content_size).new(Zaniah::Size.new(320, 180)))
      element.request_layout(context)
      expect(element.visible_range).to eq(0...2)
      expect(rendered).to eq([0, 1])

      element.scroll_y = 45 * 180
      element.request_layout(context)
      expect(element.visible_range).to eq(45...47)
      expect(rendered).to eq([0, 1, 45, 46])
    end

    it "rejects invalid viewport dimensions and selection indexes" do
      list = described_class.new(Hadar::Deck.parse("# Title\n"))

      expect { list.build(width: 0, height: 200) }.to raise_error(ArgumentError, /finite and positive/)
      expect { described_class.new(list.deck, selected: 1) }.to raise_error(IndexError)
    end
  end

  describe Hadar::Presenter do
    it "exposes next-slide preview, notes, and elapsed presentation time" do
      time = 10.0
      deck = Hadar::Deck.parse("# Current\n\n<!-- notes: mention the source -->\n\nBody.\n\n---\n\n# Following\n\nNext content.\n")
      presenter = described_class.new(deck, clock: -> { time })
      presenter.start(index: 0)
      time = 75.8

      expect(presenter.current_slide.title).to eq("Current")
      expect(presenter.next_slide.title).to eq("Following")
      expect(presenter.notes).to eq("mention the source")
      expect(presenter.elapsed_seconds).to eq(65.8)
      expect(presenter.elapsed_text).to eq("1:05")

      window = Zaniah::Platform.open_window(backend: :headless, width: 480, height: 360)
      begin
        expect { window.render(presenter.presenter_view, present: false) }.not_to raise_error
      ensure
        window.close
      end
    end

    it "clamps its current slide after the deck is externally reloaded" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "deck.md")
        File.write(path, "# First\n\n---\n\n# Last\n")
        deck = Hadar::Deck.open(path)
        presenter = described_class.new(deck).start(index: 1)
        File.write(path, "# Only slide\n")

        expect(deck.reload_if_changed).to be(true)
        expect(presenter.reconcile!.current_index).to eq(0)
        expect(presenter.current_slide.title).to eq("Only slide")
      end
    end
  end

  describe Hadar::Application do
    it "maps and restores the focused body selection when external text changes before it" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "deck.md")
        File.write(path, "# Slide\n\nKeep target.\n")
        deck = Hadar::Deck.open(path)
        backend = Object.new
        backend.define_singleton_method(:poll) { |timeout:| [] }
        backend.define_singleton_method(:close) { true }
        expect(Zaniah::Platform).to receive(:watch).with(deck.source_path, latency: 0.05).and_return(backend)
        app = described_class.new(deck)
        main = Zaniah::Platform.open_window(backend: :headless, width: 640, height: 480)
        app.attach(main_window: main)
        main.render(app.main_view(width: 640, height: 480), present: false)

        old_editor = app.body_editor
        old_start = old_editor.text.index("target")
        old_editor.selection = Zaniah::TextSelection.new(old_start + "target".bytesize, old_start)
        main.dispatcher.focus(old_editor.focus_handle, origin: :keyboard)
        iterations = 0
        main.on_tick do
          iterations += 1
          File.write(path, "# Slide\n\nAdded. Keep target.\n") if iterations == 1
          main.close if iterations == 4
        end

        expect { app.run }.not_to raise_error
        new_editor = app.body_editor
        new_start = new_editor.text.index("target")
        expect(new_editor.selection).to eq(Zaniah::TextSelection.new(new_start + "target".bytesize, new_start))
        expect(main.dispatcher.focused).to equal(new_editor.focus_handle)
      ensure
        app&.close
        main&.close
      end
    end

    it "clears body selection and focus when external text changes inside the selection" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "deck.md")
        File.write(path, "# Slide\n\nprefix target suffix\n")
        deck = Hadar::Deck.open(path)
        backend = Object.new
        backend.define_singleton_method(:poll) { |timeout:| [] }
        backend.define_singleton_method(:close) { true }
        expect(Zaniah::Platform).to receive(:watch).with(deck.source_path, latency: 0.05).and_return(backend)
        app = described_class.new(deck)
        main = Zaniah::Platform.open_window(backend: :headless, width: 640, height: 480)
        app.attach(main_window: main)
        main.render(app.main_view(width: 640, height: 480), present: false)

        old_editor = app.body_editor
        old_start = old_editor.text.index("target")
        old_editor.selection = Zaniah::TextSelection.new(old_start, old_start + "target".bytesize)
        main.dispatcher.focus(old_editor.focus_handle, origin: :keyboard)
        iterations = 0
        main.on_tick do
          iterations += 1
          File.write(path, "# Slide\n\nprefix replaced suffix\n") if iterations == 1
          main.close if iterations == 4
        end

        expect { app.run }.not_to raise_error
        expect(app.body_editor.selection).to eq(Zaniah::TextSelection.new(0))
        expect(main.dispatcher.focused).to be_nil
      ensure
        app&.close
        main&.close
      end
    end

    it "maps a focused caret along unchanged source text after an external edit" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "deck.md")
        File.write(path, "# Slide\n\nKeep target.\n")
        deck = Hadar::Deck.open(path)
        backend = Object.new
        backend.define_singleton_method(:poll) { |timeout:| [] }
        backend.define_singleton_method(:close) { true }
        expect(Zaniah::Platform).to receive(:watch).with(deck.source_path, latency: 0.05).and_return(backend)
        app = described_class.new(deck)
        main = Zaniah::Platform.open_window(backend: :headless, width: 640, height: 480)
        app.attach(main_window: main)
        main.render(app.main_view(width: 640, height: 480), present: false)

        old_editor = app.body_editor
        old_caret = old_editor.text.index("target")
        old_editor.selection = Zaniah::TextSelection.new(old_caret)
        main.dispatcher.focus(old_editor.focus_handle, origin: :keyboard)
        iterations = 0
        main.on_tick do
          iterations += 1
          File.write(path, "# Slide\n\nAdded. Keep target.\n") if iterations == 1
          main.close if iterations == 4
        end

        expect { app.run }.not_to raise_error
        new_editor = app.body_editor
        expect(new_editor.selection).to eq(Zaniah::TextSelection.new(new_editor.text.index("target")))
        expect(main.dispatcher.focused).to equal(new_editor.focus_handle)
      ensure
        app&.close
        main&.close
      end
    end

    it "wires polling reload to two headless views and retains the selected slide" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "deck.md")
        File.write(path, "# First\n\n---\n\n# Second\n\nOriginal.\n")
        deck = Hadar::Deck.open(path)
        backend = Object.new
        backend.define_singleton_method(:poll) { |timeout:| [] }
        backend.define_singleton_method(:close) { true }
        expect(Zaniah::Platform).to receive(:watch).with(deck.source_path, latency: 0.05).and_return(backend)
        app = described_class.new(deck)
        main = Zaniah::Platform.open_window(backend: :headless, width: 640, height: 480)
        presenter = Zaniah::Platform.open_window(backend: :headless, width: 640, height: 480)
        app.attach(main_window: main, presenter_window: presenter)
        app.select_slide(1)
        app.start_presentation
        iterations = 0
        main.on_tick do
          iterations += 1
          if iterations == 1
            File.write(path, "# First\n\n---\n\n# Revised second\n\nExternal.\n")
          elsif iterations == 3
            main.close
            presenter.close
          end
        end

        expect { app.run }.not_to raise_error
        expect(iterations).to eq(3)
        expect(app.selected_index).to eq(1)
        expect(app.slide_list.selected_index).to eq(1)
        expect(app.presenter.current_slide.title).to eq("Revised second")
        expect(app.deck.slide(1).slot(:body).text).to include("External.")
        expect(main.frame_stats[:frame_ms]).to be_positive
        expect(presenter.frame_stats[:frame_ms]).to be_positive
      end
    end

    it "rejects running before windows are attached" do
      app = described_class.new(Hadar::Deck.parse("# A slide\n"), watch: false)

      expect { app.run }.to raise_error(Hadar::Error, /attach at least one window/)
    end

    it "navigates slides from window keys without resetting presentation time" do
      now = 10.0
      deck = Hadar::Deck.parse("# One\n\n---\n\n# Two\n\n---\n\n# Three\n")
      app = described_class.new(deck, clock: -> { now }, watch: false)
      main = Zaniah::Platform.open_window(backend: :headless, width: 480, height: 360)
      app.attach(main_window: main)
      app.start_presentation
      now = 15.0

      main.input(Zaniah::Input::KeyDown.new("right", false))
      expect(app.selected_index).to eq(1)
      expect(app.presenter.current_index).to eq(1)
      expect(app.presenter.elapsed_seconds).to eq(5.0)

      main.input(Zaniah::Input::KeyDown.new("home", false))
      expect(app.presenter.current_index).to eq(0)
      main.input(Zaniah::Input::KeyDown.new("end", false))
      expect(app.presenter.current_index).to eq(2)
      expect(app.next_slide).to be_nil
    ensure
      app&.close
      main&.close
    end

    it "toggles native fullscreen on the active window and exits on Escape" do
      app = described_class.new(Hadar::Deck.parse("# One\n"), watch: false)
      main = Zaniah::Platform.open_window(backend: :headless, width: 480, height: 360)
      presenter = Zaniah::Platform.open_window(backend: :headless, width: 480, height: 360)
      toggles = 0
      presenter.define_singleton_method(:toggle_fullscreen) { toggles += 1 }
      app.attach(main_window: main, presenter_window: presenter)
      app.start_presentation

      main.input(Zaniah::Input::KeyDown.new("f11", false))
      expect(app.fullscreen?(window: :presenter)).to be(true)
      expect(toggles).to eq(1)

      main.input(Zaniah::Input::KeyDown.new("esc", false))
      expect(app.presenter.started?).to be(false)
      expect(app.fullscreen?(window: :presenter)).to be(false)
      expect(toggles).to eq(2)
    ensure
      app&.close
      main&.close
      presenter&.close
    end

    it "uses Zaniah transitions when the visible slide changes" do
      now = 0.0
      deck = Hadar::Deck.parse("# One\n\n---\n\n# Two\n")
      app = described_class.new(deck, watch: false)
      main = Zaniah::Platform.open_window(backend: :headless, width: 480, height: 360, clock: -> { now })
      app.attach(main_window: main)
      main.tick

      app.select_slide(1)
      main.tick
      transition = [:transition, [:hadar_slide_transition, :main, 1], :opacity]
      expect(main.animator.animating?(transition)).to be(false)
      expect(main.dirty?).to be(true)
      main.tick
      expect(main.animator.animating?(transition)).to be(true)

      now = 1.0
      main.tick
      expect(main.animator.animating?(transition)).to be(false)
    ensure
      app&.close
      main&.close
    end
  end
end
