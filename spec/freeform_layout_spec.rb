# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "opt-in freeform slides" do
  let(:source) do
    "<!-- layout: freeform -->\r\n\r\n" \
      "<!-- place: 5,10,40,20 -->\r\n# Heading\r\n\r\n" \
      "<!-- place: 10,40,80,40 -->\r\nBody **text**.\r\n"
  end

  it "projects source-backed blocks into percentage-positioned preview nodes" do
    deck = Hadar::Deck.parse(source)
    slide = deck.slide(0)

    expect(slide.layout).to eq(:freeform)
    expect(slide.placements).to eq(item_1: [5.0, 10.0, 40.0, 20.0], item_2: [10.0, 40.0, 80.0, 40.0])
    expect(slide.slot(:item_2).text).to eq("Body text.")
    description = Hadar::Renderer.new.describe(slide)
    expect(description.children.map(&:type)).to eq(%i[placed placed])
    expect(description.children.first.props).to eq(x: 5.0, y: 10.0, width: 40.0, height: 20.0)

    window = Zaniah::Platform.open_window(backend: :headless, width: 640, height: 360)
    window.text_system = Zaniah::TextSystem::Renderer.new
    expect { window.render(Hadar::Renderer.new.build(slide)) }.not_to raise_error
  ensure
    window&.close
  end

  it "keeps placement comments byte-for-byte through a Beid edit and save" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "deck.md")
      File.binwrite(path, source)
      deck = Hadar::Deck.open(path)
      deck.slide(0).slot(:item_1).replace_text("Revised")
      deck.save

      expect(File.binread(path)).to eq(source.sub("# Heading", "# Revised").b)
      expect(deck.slide(0).placements[:item_1]).to eq([5.0, 10.0, 40.0, 20.0])
    end
  end

  it "treats an image-only Markdown paragraph as an editable image" do
    deck = Hadar::Deck.parse("<!-- layout: freeform -->\n\n<!-- place: 10,10,80,80 -->\n![Chart](old.png)\n")
    slot = deck.slide(0).slot(:item_1)

    expect(slot.image_path).to eq("old.png")
    slot.replace_image("new.png")
    expect(deck.document.source).to include("![Chart](new.png)")
    expect(deck.slide(0).placements[:item_1]).to eq([10.0, 10.0, 80.0, 80.0])
    app = Hadar::Application.new(deck, watch: false)
    expect { app.insert_or_replace_selected_image("third.png") }.not_to raise_error
    expect(deck.document.source).to include("![Chart](third.png)")
  ensure
    app&.close
  end

  it "renders images in mixed text/image blocks instead of silently dropping them" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "chart.png")
      File.binwrite(path, "image fixture")
      deck = Hadar::Deck.parse("<!-- layout: freeform -->\n<!-- place: 1,1,80,80 -->\nLook ![chart](#{path})\n")
      placed = Hadar::Renderer.new.describe(deck.slide(0)).children.first

      expect(placed.children.map(&:type)).to eq(%i[text image])
      expect(placed.children.last.props[:path]).to eq(File.realpath(path))
    end
  end

  it "keeps heading titles and ignores nonvisual link definitions" do
    deck = Hadar::Deck.parse("<!-- layout: freeform -->\n<!-- place: 1,1,50,20 -->\n# Title\n\n[ref]: https://example.org\n")

    expect(deck.slide(0).title).to eq("Title")
    expect(deck.slide(0).slots.keys).to eq([:item_1])
  end

  it "rejects missing, malformed, duplicate, dangling, and overflowing positions" do
    cases = {
      "# Heading" => /preceding place/,
      "<!-- place: a,b,c,d -->\n# Heading" => /x,y,width,height/,
      "<!-- place: 5,5,0,10 -->\n# Heading" => /fit within/,
      "<!-- place: 90,5,20,10 -->\n# Heading" => /fit within/,
      "<!-- place: 1,1,10,10 -->\n<!-- place: 2,2,10,10 -->\n# Heading" => /followed by/,
      "<!-- place: 1,1,10,10 -->" => /followed by/
    }
    cases.each do |body, error|
      expect { Hadar::Deck.parse("<!-- layout: freeform -->\n#{body}\n") }
        .to raise_error(Hadar::Error, error)
    end
  end

  it "shows a warning only for the selected freeform slide" do
    deck = Hadar::Deck.parse(source + "\r\n---\r\n\r\n# Normal\r\n")
    app = Hadar::Application.new(deck, watch: false)
    warnings = -> do
      nodes = [app.main_view(width: 800, height: 500)]
      nodes.flat_map do |node|
        result = []
        visit = ->(entry) do
          result << entry.text if entry.is_a?(Zaniah::UI::Label)
          entry.children.each { |child| visit.call(child) } if entry.respond_to?(:children)
        end
        visit.call(node)
        result.grep(/素の Markdown ビューア/)
      end
    end

    expect(warnings.call.length).to eq(1)
    app.select_slide(1)
    expect(warnings.call).to be_empty
  ensure
    app&.close
  end

  it "requires explicit block reselection after an external reload" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "deck.md")
      blocks = ["First", "Second", "Third"].map do |text|
        "<!-- place: 1,1,50,20 -->\n#{text}\n"
      end
      File.binwrite(path, "<!-- layout: freeform -->\n" + blocks.join("\n"))
      deck = Hadar::Deck.open(path)
      app = Hadar::Application.new(deck, watch: false)
      app.select_slot(:item_2)
      File.binwrite(path, "<!-- layout: freeform -->\n" + blocks.drop(1).join("\n"))
      deck.reload
      app.send(:deck_reloaded)

      expect(app.selected_slot_name).to be_nil
      expect { app.select_slot(:item_1) }.not_to raise_error
      expect(app.selected_slot.text).to eq("Second")
    ensure
      app&.close
    end
  end
end
