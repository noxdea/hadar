# frozen_string_literal: true

require "spec_helper"
require "spica"
require_relative "../lib/hadar/command_palette"

RSpec.describe Hadar::CommandPalette do
  it "ranks commands with Spica fuzzy matching and invokes the selected action" do
    chosen = nil
    palette = described_class.new("Next slide" => ->(*) { chosen = :next })

    palette.query = "nxt"
    expect(palette.matches.map(&:candidate)).to eq(["Next slide"])
    palette.open
    palette.choose("Next slide")

    expect(chosen).to eq(:next)
    expect(palette.open?).to be(false)
  end

  it "rejects an unknown command rather than silently closing" do
    palette = described_class.new("Next slide" => ->(*) {})

    expect { palette.choose("Missing") }.to raise_error(ArgumentError, /unknown command/)
    expect(palette.open?).to be(false)
  end
end

RSpec.describe Hadar::Application do
  it "opens a fuzzy command palette from the keymap and executes a command" do
    app = described_class.new(Hadar::Deck.parse("# First\n\n---\n\n# Second\n"), watch: false)
    window = Zaniah::Platform.open_window(backend: :headless, width: 480, height: 360)
    app.attach(main_window: window)
    window.tick

    window.input(Zaniah::Input::KeyDown.new("ctrl-k", false))
    expect(app.command_palette.open?).to be(true)
    window.tick
    app.command_palette.query = "nxt"

    expect(app.command_palette.matches.map(&:candidate)).to include("Next slide")
    app.command_palette.query = "apng"
    expect(app.command_palette.matches.map(&:candidate)).to include("Export APNG…")
    app.command_palette.choose("Next slide")
    expect(app.selected_index).to eq(1)

    window.input(Zaniah::Input::KeyDown.new("esc", false))
    expect(app.command_palette.open?).to be(false)
  ensure
    app&.close
    window&.close
  end

  it "accepts a caller-provided Zaniah keymap" do
    keymap = Zaniah::Input::Keymap.new.bind("ctrl-j", :next_slide)
    app = described_class.new(Hadar::Deck.parse("# First\n\n---\n\n# Second\n"), watch: false, keymap: keymap)
    window = Zaniah::Platform.open_window(backend: :headless, width: 480, height: 360)
    app.attach(main_window: window)

    window.input(Zaniah::Input::KeyDown.new("ctrl-j", false))

    expect(app.selected_index).to eq(1)
  ensure
    app&.close
    window&.close
  end

  it "binds Ctrl-S to the existing conflict-aware deck save" do
    require "tmpdir"
    Dir.mktmpdir("hadar-save-key") do |directory|
      path = File.join(directory, "slides.md")
      File.binwrite(path, "# Before\n")
      app = Hadar::Application.new(Hadar::Deck.open(path), watch: false)
      main = Zaniah::Platform.open_window(backend: :headless, width: 480, height: 360)
      presenter = Zaniah::Platform.open_window(backend: :headless, width: 480, height: 360)
      app.attach(main_window: main, presenter_window: presenter)
      app.deck.replace_text(app.deck.slide(0).slot(:title), "After")

      presenter.input(Zaniah::Input::KeyDown.new("ctrl-s", false))

      expect(File.read(path)).to eq("# After\n")
    ensure
      app&.close
      main&.close
      presenter&.close
    end
  end
end
