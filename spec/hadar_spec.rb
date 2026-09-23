# frozen_string_literal: true

require "tmpdir"

RSpec.describe Hadar do
  def slide(markdown)
    Hadar::Deck.parse(markdown).slide(0)
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
end
