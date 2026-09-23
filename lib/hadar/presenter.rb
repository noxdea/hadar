# frozen_string_literal: true

module Hadar
  class Presenter
    attr_reader :deck, :current_index, :started_at

    def initialize(deck, renderer: Renderer.new, clock: Zaniah::MONOTONIC_CLOCK)
      raise TypeError, "deck must be a Hadar::Deck" unless deck.is_a?(Deck)
      raise TypeError, "renderer must respond to build" unless renderer.respond_to?(:build)
      raise TypeError, "clock must be callable" unless clock.respond_to?(:call)

      @deck, @renderer, @clock = deck, renderer, clock
      @current_index = deck.empty? ? nil : 0
    end

    def start(index: current_index)
      validate_index!(index)
      @current_index = index
      @started_at = @clock.call
      self
    end

    def stop
      @started_at = nil
      self
    end

    def started? = !started_at.nil?

    def current_slide
      current_index && deck.slide(current_index)
    end

    def next_slide
      return if current_index.nil? || current_index + 1 >= deck.length

      deck.slide(current_index + 1)
    end

    def notes = current_slide&.notes

    def elapsed_seconds
      return 0.0 unless started?

      [@clock.call - started_at, 0.0].max
    end

    def elapsed_text
      seconds = elapsed_seconds.floor
      format("%d:%02d", seconds / 60, seconds % 60)
    end

    def slide_view
      return Zaniah::UI::Label.new("No slides") unless current_slide

      @renderer.build(current_slide)
    end

    def presenter_view
      following = next_slide
      Zaniah::Div.new.flex_col.gap(12)
        .child(Zaniah::UI::Label.new("Next slide", size: :lg))
        .child(following ? @renderer.build(following) : Zaniah::UI::Label.new("End of deck", tone: :muted))
        .child(Zaniah::UI::Label.new("Speaker notes", size: :lg))
        .child(Zaniah::UI::Label.new(notes || "No speaker notes", wrap: :word))
        .child(Zaniah::UI::Label.new("Elapsed: #{elapsed_text}", tone: :muted))
    end

    def reconcile!
      if deck.empty?
        @current_index = nil
        @started_at = nil
      else
        @current_index = [[current_index || 0, 0].max, deck.length - 1].min
      end
      self
    end

    private

    def validate_index!(index)
      raise IndexError, "cannot start a presentation without slides" if deck.empty?
      raise IndexError, "slide index is outside the deck" unless index.is_a?(Integer) && (0...deck.length).cover?(index)
    end
  end
end
