# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Hadar::Export::PNGSequence do
  it "renders one numbered PNG per slide at the requested dimensions" do
    deck = Hadar::Deck.parse("# First\n\n---\n\n# Second\n")

    Dir.mktmpdir do |directory|
      output = File.join(directory, "frames")
      app = Hadar::Application.new(deck, watch: false)
      paths = app.export_png_sequence(output, width: 96, height: 54)

      expect(paths.map { |path| File.basename(path) }).to eq(["slide-001.png", "slide-002.png"])
      paths.each do |path|
        width, height, rgba = Zaniah::PNG.decode(File.binread(path))
        expect([width, height]).to eq([96, 54])
        expect(rgba.bytesize).to eq(96 * 54 * 4)
      end
    end
  end

  it "does not overwrite an existing sequence or leave partial output on collision" do
    deck = Hadar::Deck.parse("# First\n\n---\n\n# Second\n")

    Dir.mktmpdir do |directory|
      output = File.join(directory, "frames")
      FileUtils.mkdir_p(output)
      existing = File.join(output, "slide-002.png")
      File.binwrite(existing, "keep these bytes")

      expect { described_class.write(deck, output, width: 64, height: 36) }
        .to raise_error(Hadar::Error, /already exists: slide-002\.png/)
      expect(File.binread(existing)).to eq("keep these bytes")
      expect(Dir.children(output)).to eq(["slide-002.png"])
    end
  end

  it "rejects unsafe viewport dimensions before creating output" do
    expect { described_class.write(Hadar::Deck.parse("# Slide\n"), "/tmp/unused", width: 0) }
      .to raise_error(ArgumentError, /positive integers/)
    expect { described_class.write(Hadar::Deck.parse("# Slide\n"), "/tmp/unused", width: 6000, height: 6000) }
      .to raise_error(ArgumentError, /32000000 pixels/)
  end
end
