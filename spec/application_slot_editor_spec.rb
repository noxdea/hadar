# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "zlib"

RSpec.describe Hadar::Application do
  def mount(deck)
    app = described_class.new(deck, watch: false)
    window = Zaniah::Platform.open_window(backend: :headless, width: 640, height: 400)
    app.attach(main_window: window)
    window.tick
    [app, window]
  end

  def press(window, label)
    node = window.accessibility_tree.find { |entry, _path| entry.role == :button && entry.label == label }
    raise "missing button: #{label}" unless node

    expect(Zaniah::Accessibility.perform(window, node, :press)).to be(true)
    window.tick
  end

  def replace_field(app, window, label, value)
    component = case label
    when "Cell text" then app.instance_variable_get(:@table_field)
    when "Code editor" then app.instance_variable_get(:@code_editor)
    end
    raise "missing text field: #{label}" unless component&.focus_handle

    window.dispatcher.focus(component.focus_handle, origin: :programmatic)
    primary = RUBY_PLATFORM.match?(/darwin|mac/) ? "cmd-a" : "ctrl-a"
    window.input(Zaniah::Input::KeyDown.new(primary, false))
    window.input(Zaniah::Input::TextInput.new(value))
    window.tick
    expect(window.dispatcher.focused).to equal(component.focus_handle)
  end

  def png_fixture
    chunk = ->(type, data) { [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N") }
    header = [1, 1].pack("N2") + [8, 6, 0, 0, 0].pack("C5")
    pixels = Zlib::Deflate.deflate("\x00\xff\x00\x00\xff".b)
    "\x89PNG\r\n\x1a\n".b + chunk.call("IHDR", header) + chunk.call("IDAT", pixels) + chunk.call("IEND", "".b)
  end

  it "switches among declared text slots and writes back only the chosen slot" do
    original = "<!-- layout: title -->\r\n# Main title\r\n## Subtitle\r\n<!-- notes: untouched -->\r\n"
    app, window = mount(Hadar::Deck.parse(original))

    expect(app.selected_slot_name).to eq(:title)
    press(window, "Subtitle")
    expect(app.selected_slot_name).to eq(:subtitle)
    expect(app.body_editor.text).to eq("Subtitle")
    app.body_editor.selection = Zaniah::TextSelection.new(0, app.body_editor.text.bytesize)
    window.dispatcher.focus(app.body_editor.focus_handle, origin: :programmatic)
    window.input(Zaniah::Input::TextInput.new("Revised subtitle"))

    expect(app.deck.document.source.b).to eq(original.sub("Subtitle", "Revised subtitle").b)
    expect(app.deck.document.source).to include("# Main title\r\n", "<!-- notes: untouched -->\r\n")
  ensure
    app&.close
    window&.close
  end

  it "inserts and replaces an image through the image-slot controls using relative paths" do
    Dir.mktmpdir do |directory|
      media = File.join(directory, "media")
      FileUtils.mkdir_p(media)
      first = File.join(media, "new chart.png")
      second = File.join(media, "replacement.png")
      File.binwrite(first, png_fixture)
      File.binwrite(second, png_fixture)
      original = "<!-- layout: image+text -->\r\n# Sales\r\n\r\nQuarterly growth.\r\n"
      path = File.join(directory, "slides.md")
      File.binwrite(path, original)
      app, window = mount(Hadar::Deck.open(path))
      choices = [first, second]
      window.define_singleton_method(:prompt_for_paths) { |**_options| [choices.shift] }

      press(window, "Image")
      press(window, "Insert image…")
      inserted = original + "\r\n![new chart.png](media/new%20chart.png)"
      expect(app.deck.document.source.b).to eq(inserted.b)

      press(window, "Replace image…")
      replaced = inserted.sub("media/new%20chart.png", "media/replacement.png")
      expect(app.deck.document.source.b).to eq(replaced.b)
      expect(app.selected_slot.image_path).to eq("media/replacement.png")
    ensure
      app&.close
      window&.close
    end
  end

  it "edits table cells and fenced code from the selected slot without rewriting neighboring Markdown" do
    original = <<~'MARKDOWN'.gsub("\n", "\r\n")
      <!-- layout: title+body -->
      # Example

      | Name | Value |
      | --- | ---: |
      | old | 3 |

      <!-- notes: preserve me -->

      ```ruby
      puts "old"
      ```
    MARKDOWN
    app, window = mount(Hadar::Deck.parse(original))
    expect(app.selected_slot_name).to eq(:body)

    replace_field(app, window, "Cell text", "revised")
    expect(app.instance_variable_get(:@table_draft)).to eq("revised")
    press(window, "Apply cell")
    expect(app.deck.document.source.b).to eq(original.sub("| old | 3 |", "| revised | 3 |").b)

    replace_field(app, window, "Code editor", "puts \"new\"\n")
    expect(app.instance_variable_get(:@code_draft)).to eq("puts \"new\"\n")
    press(window, "Apply code")
    expected = original.sub("| old | 3 |", "| revised | 3 |")
      .sub("puts \"old\"\r\n", "puts \"new\"\n")
    expect(app.deck.document.source.b).to eq(expected.b)
    expect(app.deck.document.source).to include("<!-- notes: preserve me -->\r\n", "```ruby\r\n")
  ensure
    app&.close
    window&.close
  end
end
