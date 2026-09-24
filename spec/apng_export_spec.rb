# frozen_string_literal: true

require "spec_helper"

RSpec.describe Hadar::Export::APNG do
  let(:deck) { Hadar::Deck.parse("# First\n\n---\n\n# Second\n") }

  it "encodes each rendered slide with the requested frame timing" do
    bytes = described_class.render(deck, width: 640, height: 360, duration_ms: 250, loop: 2)
    chunks = png_chunks(bytes)

    expect(bytes).to start_with("\x89PNG\r\n\x1a\n".b)
    expect(chunks.assoc("acTL").last.unpack("N2")).to eq([2, 2])
    expect(chunks.count { |type, _| type == "fcTL" }).to eq(2)
    delays = chunks.filter_map do |type, data|
      data.unpack("N5n2C2").values_at(5, 6) if type == "fcTL"
    end
    expect(delays).to eq([[1, 4], [1, 4]])
    expect(Zaniah::PNG.decode(bytes).first(2)).to eq([640, 360])
  end

  it "does not overwrite an existing file unless requested" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "slides.apng")
      File.binwrite(path, "keep these bytes")

      expect { described_class.write(deck, path, width: 64, height: 36) }
        .to raise_error(Hadar::Error, /already exists/)
      expect(File.binread(path)).to eq("keep these bytes")

      app = Hadar::Application.new(deck, watch: false)
      expect(app.export_apng(path, overwrite: true, width: 64, height: 36)).to eq(path)
      expect(File.binread(path)).to include("acTL")
    end
  end

  it "rejects invalid timing and unsafe dimensions before rendering" do
    expect { described_class.render(deck, width: 0) }.to raise_error(ArgumentError, /dimensions/)
    expect { described_class.render(deck, duration_ms: 0) }.to raise_error(ArgumentError, /duration_ms/)
    expect { described_class.render(deck, duration_ms: 65_537) }.to raise_error(ArgumentError, /frame-delay limit/)
    expect { described_class.render(deck, loop: -1) }.to raise_error(ArgumentError, /loop/)
  end

  def png_chunks(bytes)
    chunks = []
    offset = 8
    while offset < bytes.bytesize
      length = bytes.byteslice(offset, 4).unpack1("N")
      type = bytes.byteslice(offset + 4, 4)
      data = bytes.byteslice(offset + 8, length)
      chunks << [type, data]
      offset += length + 12
      break if type == "IEND"
    end
    chunks
  end
end
