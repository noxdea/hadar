# frozen_string_literal: true

require "okab/zaniah_vector"
require "zaniah/vector"

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
        renderer = Renderer.new(font: @font.face)
        @deck.slides.each do |slide|
          ensure_glyphs!(renderer.describe(slide))
          vector = Zaniah::Vector.record(width: WIDTH, height: HEIGHT) { renderer.build(slide) }
          page = document.page(width: WIDTH, height: HEIGHT)
          Okab::ZaniahVector.draw(page, vector)
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

      def ensure_glyphs!(node)
        if %i[text code_token].include?(node.type)
          missing = node.props.fetch(:text).codepoints.find do |codepoint|
            next false if codepoint == 0x0a || variation_selector?(codepoint)

            @font.face.glyph_id(codepoint).zero?
          end
          raise Error, "PDF font does not contain U+#{missing.to_s(16).upcase}; provide a font that covers the deck text" if missing
        end
        node.children.each { |child| ensure_glyphs!(child) }
      end

      def variation_selector?(codepoint)
        (0xfe00..0xfe0f).cover?(codepoint) || (0xe0100..0xe01ef).cover?(codepoint)
      end
    end
  end
end
