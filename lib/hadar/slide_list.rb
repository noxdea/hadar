# frozen_string_literal: true

module Hadar
  class SlideList
    DEFAULT_ROW_HEIGHT = 180

    attr_reader :deck, :element, :selected_index

    def initialize(deck, renderer: Renderer.new, selected: nil,
      row_height: DEFAULT_ROW_HEIGHT, on_select: nil)
      raise TypeError, "deck must be a Hadar::Deck" unless deck.is_a?(Deck)
      raise TypeError, "renderer must respond to build" unless renderer.respond_to?(:build)
      raise TypeError, "on_select must be callable" if on_select && !on_select.respond_to?(:call)

      @deck, @renderer, @selected_index, @on_select = deck, renderer, selected, on_select
      @row_height = Float(row_height)
      raise ArgumentError, "row_height must be finite and positive" unless @row_height.finite? && @row_height.positive?
      validate_selection!(selected) unless selected.nil?

      @element = Zaniah::UniformList.new(count: deck.length, row_height: @row_height) do |index|
        render_slide(index)
      end
    end

    def build(width:, height:)
      [width, height].each do |dimension|
        unless dimension.is_a?(Numeric) && dimension.finite? && dimension.positive?
          raise ArgumentError, "list width and height must be finite and positive"
        end
      end
      element.style(width: width, height: height)
    end

    def select(index)
      validate_selection!(index)
      @selected_index = index
      slide = deck.slide(index)
      @on_select&.call(slide, index)
      slide
    end

    private

    def render_slide(index)
      slide = deck.slide(index)
      selected = index == selected_index
      Zaniah::Div.new.key(index).w_full.h_full.overflow_hidden
        .border(selected ? 3 : 1)
        .border_color(slide.theme.colors.fetch(selected ? "accent" : "muted"))
        .on_click do |_event, context|
          select(index)
          context.window.request_frame
        end
        .child(thumbnail_for(slide))
    end

    def thumbnail_for(slide)
      preview = @renderer.build(slide)
      compact_text(preview)
    end

    def compact_text(element)
      element.wrap(:none) if element.is_a?(Zaniah::Text)
      element.children.each { |child| compact_text(child) }
      element
    end

    def validate_selection!(index)
      unless index.is_a?(Integer) && (0...deck.length).cover?(index)
        raise IndexError, "slide index is outside the deck"
      end
    end
  end
end
