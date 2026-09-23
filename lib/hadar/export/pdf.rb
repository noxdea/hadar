# frozen_string_literal: true

module Hadar
  module Export
    class PDF
      WIDTH, HEIGHT = 960, 540

      def self.render(deck, font: nil)
        new(deck, font: font).render
      end

      def self.write(deck, path, font: nil)
        File.binwrite(path, render(deck, font: font))
        path
      end

      def initialize(deck, font: nil)
        raise TypeError, "deck must be a Hadar::Deck" unless deck.is_a?(Deck)

        @deck = deck
        @font = load_font(font)
      end

      def render
        document = Okab::Document.new(title: @deck.slides.first&.title, creator: "Hadar")
        @deck.slides.each do |slide|
          page = document.page(width: WIDTH, height: HEIGHT)
          paint_background(page, slide.theme)
          paint_slide(page, slide)
          document.outline(slide.title, page: page) unless slide.title.empty?
        end
        document.render
      end

      private

      def load_font(font)
        loaded = case font
        when String then Okab::Font.load(font)
        when Okab::Font then font
        when Alhena::Font then Okab::Font.new(font)
        when nil
          family = @deck.theme.font.fetch("family")
          Okab::Font.new(Zaniah::TextSystem::FontDB.new.find(family: family == "sans-serif" ? nil : family))
        else
          raise TypeError, "font must be a path, Okab::Font, or Alhena::Font"
        end
        raise Error, "Okab PDF export currently requires a TrueType-outline font" if loaded.face.cff?

        loaded
      rescue Okab::Error, Alhena::Error, Zaniah::Error => error
        raise Error, "cannot load PDF font: #{error.message}"
      end

      def paint_background(page, theme)
        page.rect(0, 0, WIDTH, HEIGHT).fill(rgb(theme.colors.fetch("background")))
      end

      def paint_slide(page, slide)
        margin = slide.theme.spacing.fetch("margin")
        gap = slide.theme.spacing.fetch("gap")
        title_size = slide.theme.font.fetch("title_size")
        body_size = slide.theme.font.fetch("body_size")
        text_color = rgb(slide.theme.colors.fetch("text"))
        muted = rgb(slide.theme.colors.fetch("muted"))
        width = WIDTH - margin * 2

        case slide.layout
        when :title
          text(page, slide.slot(:title).text, margin, HEIGHT * 0.57, width, title_size, text_color, :center)
          text(page, slide.slot(:subtitle).text, margin, HEIGHT * 0.40, width, body_size, muted, :center)
        when :two_column
          paint_title(page, slide, margin, width, title_size, text_color)
          column_width = (width - gap) / 2
          y = HEIGHT - margin - title_size - gap - body_size
          text(page, slide.slot(:left).text, margin, y, column_width, body_size, text_color)
          text(page, slide.slot(:right).text, margin + column_width + gap, y, column_width, body_size, text_color)
        when :image_text
          paint_title(page, slide, margin, width, title_size, text_color)
          y = HEIGHT - margin - title_size - gap - body_size
          text(page, slide.slot(:text).text, margin, y, width * 0.48, body_size, text_color)
          paint_image(page, slide.slot(:image), margin + width * 0.52, margin,
            width * 0.48, HEIGHT - margin * 2 - title_size - gap)
        when :full_bleed_image
          paint_image(page, slide.slot(:image), 0, 0, WIDTH, HEIGHT, cover: true)
        when :quote
          text(page, slide.slot(:quote).text, margin + width * 0.08, HEIGHT * 0.62,
            width * 0.84, title_size, text_color, :center)
          text(page, slide.slot(:attribution).text, margin, HEIGHT * 0.28, width, body_size, muted, :center)
        when :code
          paint_title(page, slide, margin, width, title_size, text_color)
          y = HEIGHT - margin - title_size - gap - body_size
          text(page, slide.slot(:code).text, margin, y, width, body_size, text_color)
        when :blank
          nil
        else
          paint_title(page, slide, margin, width, title_size, text_color)
          y = HEIGHT - margin - title_size - gap - body_size
          text(page, slide.slot(:body).text, margin, y, width, body_size, text_color)
        end
      end

      def paint_title(page, slide, margin, width, size, color)
        text(page, slide.slot(:title).text, margin, HEIGHT - margin - size, width, size, color)
      end

      def text(page, value, x, y, width, size, color, align = :left)
        return if value.nil? || value.empty?

        value = value.gsub(/\r\n?/, "\n")
        ensure_glyphs!(value)
        page.text_block(value, x: x, y: y, width: width, font: @font, size: size,
          line_height: size * 1.3, align: align, color: color)
      end

      def paint_image(page, slot, x, y, width, height, cover: false)
        return if slot.empty?

        image = Okab::Image.decode(File.binread(slot.resolved_image_path))
        scales = [width / image.width, height / image.height]
        scale = cover ? scales.max : scales.min
        draw_width, draw_height = image.width * scale, image.height * scale
        page.clip { |path| path.rect(x, y, width, height) } if cover
        page.image(image, x: x + (width - draw_width) / 2, y: y + (height - draw_height) / 2,
          width: draw_width, height: draw_height)
      rescue Okab::Error, SystemCallError => error
        raise Error, "cannot export image: #{error.message}"
      end

      def ensure_glyphs!(value)
        missing = value.codepoints.find do |codepoint|
          next false if codepoint == 0x0a || variation_selector?(codepoint)

          @font.face.glyph_id(codepoint).zero?
        end
        return unless missing

        raise Error, "PDF font does not contain U+#{missing.to_s(16).upcase}; provide a font that covers the deck text"
      end

      def rgb(color)
        color.delete_prefix("#").scan(/../).first(3).map { |component| component.to_i(16) / 255.0 }
      end

      def variation_selector?(codepoint)
        (0xfe00..0xfe0f).cover?(codepoint) || (0xe0100..0xe01ef).cover?(codepoint)
      end
    end
  end
end
