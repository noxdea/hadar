# frozen_string_literal: true

module Hadar
  class Application
    attr_reader :deck, :renderer, :presenter, :selected_index, :slide_list

    def initialize(deck, renderer: Renderer.new, clock: Zaniah::MONOTONIC_CLOCK, watch: true)
      raise TypeError, "deck must be a Hadar::Deck" unless deck.is_a?(Deck)
      raise TypeError, "watch must be true or false" unless watch == true || watch == false

      @deck, @renderer, @clock = deck, renderer, clock
      @selected_index = deck.empty? ? nil : 0
      @presenter = Presenter.new(deck, renderer: renderer, clock: clock)
      @windows = []
      @closed = false
      @running = false
      rebuild_slide_list
      @watcher = deck.source_path && watch ? deck.watch(on_reload: ->(_updated) { deck_reloaded }) : nil
    end

    def attach(main_window:, presenter_window: nil)
      attach_window(main_window) { |window| main_view(width: window.content_size.width, height: window.content_size.height) }
      attach_window(presenter_window) { |_window| presenter.presenter_view } if presenter_window
      self
    end

    def main_view(width:, height:)
      preview = if presenter.started?
        presenter.slide_view
      elsif selected_index
        renderer.build(deck.slide(selected_index))
      else
        Zaniah::UI::Label.new("No slides")
      end
      sidebar_width = [Float(width) * 0.24, 240.0].min
      Zaniah::Div.new.flex_row.w(width).h(height)
        .child(slide_list.build(width: sidebar_width, height: height))
        .child(Zaniah::Div.new.flex_1.child(preview))
    end

    def select_slide(index)
      raise IndexError, "slide index is outside the deck" unless index.is_a?(Integer) && (0...deck.length).cover?(index)

      slide = slide_list.select(index)
      request_frames
      slide
    end

    def start_presentation(index: selected_index)
      presenter.start(index: index)
      request_frames
      presenter
    end

    def stop_presentation
      presenter.stop
      request_frames
      presenter
    end

    def tick
      changed = @watcher&.poll(timeout: 0) || false
      request_frames if changed || presenter.started?
      changed
    end

    def run
      raise Error, "attach at least one window before running the application" if @windows.empty?
      raise Error, "application is already running" if @running

      @running = true
      until @closed || !@running || @windows.all?(&:closed?)
        tick
        @windows.dup.each { |window| window.tick unless window.closed? }
        sleep(0.016) unless @closed || !@running || @windows.all?(&:closed?)
      end
      self
    ensure
      @running = false
      close if @windows.any? && @windows.all?(&:closed?)
    end

    def close
      @closed = true
      @watcher&.close
      @windows.clear
      self
    end

    def stop
      @running = false
      self
    end

    private

    def attach_window(window, &draw)
      raise TypeError, "window must support drawing, input, ticking, closing, and frame requests" unless
        %i[draw on_input tick closed? request_frame].all? { |method| window.respond_to?(method) }

      @windows << window unless @windows.include?(window)
      window.draw(&draw)
      window.on_input { |event| handle_input(event, window) }
    end

    def handle_input(event, _window)
      return unless event.is_a?(Zaniah::Input::KeyDown)

      # Navigation bindings are added with the presentation controls milestone.
    end

    def rebuild_slide_list
      @slide_list = SlideList.new(deck, renderer: renderer, selected: selected_index,
        on_select: ->(_slide, index) { @selected_index = index })
    end

    def deck_reloaded
      @selected_index = if deck.empty?
        nil
      else
        [[selected_index || 0, 0].max, deck.length - 1].min
      end
      presenter.reconcile!
      rebuild_slide_list
      request_frames
    end

    def request_frames
      @windows.each(&:request_frame)
    end
  end
end
