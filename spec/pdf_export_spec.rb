# frozen_string_literal: true

require "tmpdir"
require "tempfile"
require "zlib"
require "okab"
require_relative "../lib/hadar/export/pdf"

RSpec.describe Hadar::Export::PDF do
  it "writes each standard layout as a searchable PDF page and embeds local images" do
    Dir.mktmpdir do |directory|
      File.binwrite(File.join(directory, "chart.png"), png_fixture)
      source = <<~MARKDOWN
        <!-- layout: title -->
        # Cover
        ## Subtitle

        ---

        <!-- layout: title+body -->
        # Summary

        Body text.

        ---

        <!-- layout: two-column -->
        # Split

        ::: left
        Left column.
        :::

        ::: right
        Right column.
        :::

        ---

        <!-- layout: image+text -->
        # Picture

        Caption text.

        ![Chart](chart.png)

        ---

        <!-- layout: full-bleed-image -->
        ![Chart](chart.png)

        ---

        <!-- layout: quote -->
        > Quoted text.

        Attribution.

        ---

        <!-- layout: code -->
        # Example

        ```ruby
        puts :ok
        ```

        ---

        <!-- layout: blank -->
      MARKDOWN
      path = File.join(directory, "slides.md")
      File.binwrite(path, source)
      deck = Hadar::Deck.open(path)
      pdf = described_class.render(deck)

      expect(deck.slides.map(&:layout)).to eq(%i[title title_body two_column image_text full_bleed_image quote code blank])
      expect(pdf.scan("/Type /Page ").length).to eq(8)
      expect(pdf.scan("/Subtype /Image").length).to eq(2)
      expect(pdf).to start_with("%PDF-1.7\n".b)
      Tempfile.create(["hadar", ".pdf"]) do |file|
        file.binmode
        file.write(pdf)
        file.flush
        if system("qpdf", "--version", out: File::NULL, err: File::NULL)
          expect(system("qpdf", "--check", file.path, out: File::NULL, err: File::NULL)).to be(true)
        end
        if system("pdftotext", "-v", out: File::NULL, err: File::NULL)
          extracted = IO.popen(["pdftotext", file.path, "-"], &:read)
          %w[Cover Subtitle Summary Body Split Left Right Picture Caption Quoted Attribution Example puts].each do |text|
            expect(extracted).to include(text)
          end
        end
      end
    end
  end

  it "supports Japanese extraction when given a font that contains Japanese glyphs" do
    font = ENV["HADAR_TEST_FONT"] || ENV["OKAB_TEST_FONT"]
    skip "Set HADAR_TEST_FONT to a Japanese TrueType font and install pdftotext" unless
      font && system("pdftotext", "-v", out: File::NULL, err: File::NULL)

    deck = Hadar::Deck.parse("# 四半期報告\n\n本文です。\n")
    Dir.mktmpdir do |directory|
      path = File.join(directory, "slides.pdf")
      described_class.write(deck, path, font: font)
      extracted = IO.popen(["pdftotext", path, "-"], &:read)

      expect(extracted).to include("四半期報告", "本文です。")
    end
  end

  it "rejects a font that cannot render the deck instead of emitting missing glyphs" do
    deck = Hadar::Deck.parse("# unsupported \u{10FFFF}\n")

    expect { described_class.render(deck) }
      .to raise_error(Hadar::Error, /does not contain U\+/)
  end

  it "matches the PNG slide layout when PDF rasterization is available" do
    skip "pdftoppm is unavailable" unless system("pdftoppm", "-v", out: File::NULL, err: File::NULL)

    deck = Hadar::Deck.parse("# Visual match\n\nThe same slide tree.\n")
    Dir.mktmpdir do |directory|
      pdf_path = File.join(directory, "slide.pdf")
      File.binwrite(pdf_path, described_class.render(deck))
      png_path = Hadar::Export::PNGSequence.write(deck, directory,
        width: described_class::WIDTH, height: described_class::HEIGHT).first
      prefix = File.join(directory, "pdf")
      expect(system("pdftoppm", "-f", "1", "-l", "1", "-singlefile", "-r", "72",
        "-png", pdf_path, prefix, out: File::NULL, err: File::NULL)).to be(true)

      expected = Zaniah::PNG.decode(File.binread(png_path))
      actual = Zaniah::PNG.decode(File.binread("#{prefix}.png"))
      expect(actual.first(2)).to eq(expected.first(2))
      difference = expected.last.bytes.zip(actual.last.bytes).sum { |left, right| (left - right).abs }
      expect(difference.fdiv(expected.last.bytesize * 255)).to be < 0.005
    end
  end

  def png_fixture
    chunk = ->(type, data) { [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N") }
    header = [1, 1, 8, 6, 0, 0, 0].pack("NNC5")
    pixels = Zlib::Deflate.deflate("\x00\xff\x00\x00\xff".b)
    "\x89PNG\r\n\x1a\n".b + chunk.call("IHDR", header) + chunk.call("IDAT", pixels) + chunk.call("IEND", "".b)
  end
end
