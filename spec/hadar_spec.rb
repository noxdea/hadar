# frozen_string_literal: true

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
end
