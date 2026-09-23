# frozen_string_literal: true

require "spec_helper"

RSpec.describe Hadar::Application do
  it "edits the selected slide body through the in-app RichText surface and preserves untouched Markdown" do
    original = "# Source title\r\n\r\nLead **bold** text.\r\n\r\n---\r\n\r\n# Keep this slide\r\n\r\nOther text.\r\n"
    deck = Hadar::Deck.parse(original)
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

    expect(deck.document.source.b).to eq(original.sub("Lead", "Plan").b)
    expect(app.body_editor).to equal(editor)
    expect(deck.document.source).to include("**bold**", "# Keep this slide\r\n")
    window.tick
    expect(window.text_runs.map { |run| run[2] }.join).to include("Plan bold text.")
  ensure
    app&.close
    window&.close
  end

  it "keeps unsupported body syntax visible as read-only rather than offering unsafe edits" do
    markdown = "# Table\n\n| Name | Value |\n| --- | --- |\n| first | second |\n"
    app = described_class.new(Hadar::Deck.parse(markdown), watch: false)

    view = app.main_view(width: 800, height: 600)

    expect(app.body_editor).to be_nil
    expect(app.instance_variable_get(:@body_editor_error)).to match(/not supported by rich-text editing/)
    expect(view).to respond_to(:request_layout)
  ensure
    app&.close
  end
end
