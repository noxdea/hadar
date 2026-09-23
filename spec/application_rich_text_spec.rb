# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Hadar::Application do
  it "edits the selected slide body through the in-app RichText surface and preserves untouched Markdown" do
    original = "# Source title\r\n\r\nLead **bold** text.\r\n\r\n---\r\n\r\n# Keep this slide\r\n\r\nOther text.\r\n"
    Dir.mktmpdir("hadar-save") do |directory|
      path = File.join(directory, "slides.md")
      File.binwrite(path, original)
      deck = Hadar::Deck.open(path)
      app = described_class.new(deck, watch: false)
      window = Zaniah::Platform.open_window(backend: :headless, width: 640, height: 400)
      app.attach(main_window: window)
      window.tick

      editor = app.body_editor
      expect(editor).to be_a(Zaniah::UI::RichText)
      expect(editor.text).to eq("Lead bold text.")
      window.dispatcher.focus(editor.focus_handle, origin: :programmatic)
      editor.selection = Zaniah::TextSelection.new(0, 4)
      window.input(Zaniah::Input::TextInput.new("Plan"))

      edited = original.sub("Lead", "Plan")
      expect(deck.document.source.b).to eq(edited.b)
      expect(app.body_editor).to equal(editor)
      expect(deck.document.source).to include("**bold**", "# Keep this slide\r\n")
      window.input(Zaniah::Input::KeyDown.new("ctrl-s", false))
      expect(File.binread(path)).to eq(edited.b)
      window.tick
      expect(window.text_runs.map { |run| run[2] }.join).to include("Plan bold text.")
    ensure
      app&.close
      window&.close
    end
  end

  it "offers the source-preserving table editor instead of flattening table Markdown into rich text" do
    markdown = "# Table\n\n| Name | Value |\n| --- | --- |\n| first | second |\n"
    app = described_class.new(Hadar::Deck.parse(markdown), watch: false)

    view = app.main_view(width: 800, height: 600)

    expect(app.body_editor).to be_nil
    expect(app.selected_slot_name).to eq(:body)
    expect(view).to respond_to(:request_layout)
  ensure
    app&.close
  end

  it "drops the prior slide editor when the selected slide has no body slot" do
    markdown = "# First\n\nBody text.\n\n---\n\n<!-- layout: blank -->\n"
    app = described_class.new(Hadar::Deck.parse(markdown), watch: false)
    window = Zaniah::Platform.open_window(backend: :headless, width: 640, height: 400)
    app.attach(main_window: window)
    window.tick
    expect(app.body_editor).to be_a(Zaniah::UI::RichText)

    app.select_slide(1)
    window.tick

    expect(app.body_editor).to be_nil
    expect(app.instance_variable_get(:@body_editor_error)).to eq("this slide has no editable slots")
  ensure
    app&.close
    window&.close
  end
end
