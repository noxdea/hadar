# frozen_string_literal: true

module Hadar
  class Application
    attr_reader :deck, :renderer, :presenter, :selected_index, :slide_list, :keymap

    def self.default_keymap(clock: Zaniah::MONOTONIC_CLOCK)
      Zaniah::Input::Keymap.new(clock: clock)
        .bind("right", :next_slide, context: "!in_text_field")
        .bind("pagedown", :next_slide, context: "!in_text_field")
        .bind("space", :next_slide, context: "!in_text_field")
        .bind("left", :previous_slide, context: "!in_text_field")
        .bind("pageup", :previous_slide, context: "!in_text_field")
        .bind("home", :first_slide, context: "!in_text_field")
        .bind("end", :last_slide, context: "!in_text_field")
        .bind("p", :toggle_presentation, context: "!in_text_field")
        .bind("f5", :toggle_presentation, context: "!in_text_field")
        .bind("f11", :toggle_fullscreen)
        .bind("ctrl-k", :toggle_command_palette)
        .bind("cmd-k", :toggle_command_palette)
        .bind("esc", :escape)
    end

    def initialize(deck, renderer: Renderer.new, clock: Zaniah::MONOTONIC_CLOCK, watch: true, keymap: nil)
      raise TypeError, "deck must be a Hadar::Deck" unless deck.is_a?(Deck)
      raise TypeError, "watch must be true or false" unless watch == true || watch == false
      unless keymap.nil? || keymap.is_a?(Zaniah::Input::Keymap)
        raise TypeError, "keymap must be a Zaniah::Input::Keymap or nil"
      end

      @deck, @renderer, @clock = deck, renderer, clock
      @keymap = keymap || self.class.default_keymap(clock: clock)
      @selected_index = deck.empty? ? nil : 0
      @presenter = Presenter.new(deck, renderer: renderer, clock: clock)
      @windows = []
      @main_window = @presenter_window = nil
      @fullscreen = {main: false, presenter: false}
      @transition_generation = {main: 0, presenter: 0}
      @transition_initial_frame = {main: false, presenter: false}
      @closed = false
      @running = false
      @command_palette = nil
      rebuild_slide_list
      @watcher = deck.source_path && watch ? deck.watch(on_reload: ->(_updated) { deck_reloaded }) : nil
    end

    def attach(main_window:, presenter_window: nil)
      @main_window = main_window
      @presenter_window = presenter_window
      attach_window(main_window) do |window|
        main_view(width: window.content_size.width, height: window.content_size.height)
      end
      attach_window(presenter_window) do |_window|
        transition_view(presenter.presenter_view, :presenter)
      end if presenter_window
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
      view = Zaniah::Div.new.flex_row.w(width).h(height)
        .child(slide_list.build(width: sidebar_width, height: height))
        .child(Zaniah::Div.new.flex_1.child(transition_view(preview, :main)))
      view.child(@command_palette) if @command_palette
      view
    end

    def command_palette = @command_palette

    def export_png_sequence(directory, width: 1280, height: 720)
      PNGSequence.write(deck, directory, renderer: renderer, width: width, height: height)
    end

    def select_slide(index)
      raise IndexError, "slide index is outside the deck" unless index.is_a?(Integer) && (0...deck.length).cover?(index)

      slide = slide_list.select(index)
      request_frames
      slide
    end

    def next_slide
      navigate_to(selected_index + 1) if selected_index && selected_index + 1 < deck.length
    end

    def previous_slide
      navigate_to(selected_index - 1) if selected_index && selected_index.positive?
    end

    def first_slide
      navigate_to(0) unless deck.empty?
    end

    def last_slide
      navigate_to(deck.length - 1) unless deck.empty?
    end

    def toggle_fullscreen(window: :presenter)
      target = window_for(window)
      raise Error, "#{window} window backend does not support fullscreen" unless target.respond_to?(:toggle_fullscreen)

      target.toggle_fullscreen
      @fullscreen[window] = !@fullscreen.fetch(window)
    end

    def fullscreen?(window: :presenter)
      window_for(window)
      @fullscreen.fetch(window)
    end

    def start_presentation(index: selected_index)
      presenter.start(index: index)
      if selected_index == index
        begin_slide_transition
      else
        slide_list.select(index)
      end
      request_frames
      presenter
    end

    def stop_presentation
      presenter.stop
      begin_slide_transition
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

    def handle_input(event, window)
      return unless event.is_a?(Zaniah::Input::KeyDown) && !event.is_held

      key = Zaniah::Input::Keystroke.normalize(event.keystroke)
      target = window.equal?(@presenter_window) ? :presenter : :main
      action = keymap.dispatch(key, context: key_context(window))
      return if action.nil? || action == :pending

      case action
      when :next_slide
        next_slide
      when :previous_slide
        previous_slide
      when :first_slide
        first_slide
      when :last_slide
        last_slide
      when :toggle_presentation
        presenter.started? ? stop_presentation : start_presentation
      when :toggle_fullscreen
        fullscreen_window = target == :main && presenter.started? && @presenter_window ? :presenter : target
        toggle_fullscreen(window: fullscreen_window)
      when :toggle_command_palette
        toggle_command_palette if target == :main
      when :escape
        if @command_palette&.open?
          @command_palette.close
        else
          stop_presentation if presenter.started?
          fullscreen_window = @presenter_window && @fullscreen[:presenter] ? :presenter : target
          toggle_fullscreen(window: fullscreen_window) if fullscreen?(window: fullscreen_window)
        end
      end
    end

    def toggle_command_palette
      unless @command_palette
        require_relative "command_palette"
        @command_palette = CommandPalette.new(command_actions)
      end
      @command_palette.open(!@command_palette.open?)
      request_frames
      @command_palette
    rescue LoadError => error
      raise Error, "the command palette requires Spica: #{error.message}"
    end

    def command_actions
      {
        "Next slide" => ->(*) { next_slide },
        "Previous slide" => ->(*) { previous_slide },
        "First slide" => ->(*) { first_slide },
        "Last slide" => ->(*) { last_slide },
        "Toggle presentation" => ->(*) { presenter.started? ? stop_presentation : start_presentation },
        "Toggle fullscreen" => ->(*) { toggle_fullscreen(window: :main) },
        "Export PNG sequence…" => ->(*) { prompt_png_sequence_directory }
      }
    end

    def prompt_png_sequence_directory
      unless @main_window.respond_to?(:prompt_for_paths)
        raise Error, "this window backend cannot choose a directory; call export_png_sequence(directory)"
      end

      directory = @main_window.prompt_for_paths(directories: true).first
      export_png_sequence(directory) if directory && !directory.empty?
    end

    def key_context(window)
      (window.dispatcher.focused&.ancestors || []).reverse.each_with_object({}) do |handle, context|
        context.merge!(handle.context)
      end
    end

    def rebuild_slide_list
      @slide_list = SlideList.new(deck, renderer: renderer, selected: selected_index,
        on_select: ->(_slide, index) do
          next if @selected_index == index

          @selected_index = index
          presenter.go_to(index) if presenter.started?
          begin_slide_transition
          request_frames
        end)
    end

    def navigate_to(index)
      unless index.is_a?(Integer) && (0...deck.length).cover?(index)
        raise IndexError, "slide index is outside the deck"
      end
      return deck.slide(index) if index == selected_index

      slide_list.select(index)
    end

    def begin_slide_transition
      @transition_generation.each_key do |surface|
        next if surface == :presenter && !@presenter_window

        @transition_generation[surface] += 1
        @transition_initial_frame[surface] = true
      end
    end

    def transition_view(element, surface)
      initial_frame = @transition_initial_frame.fetch(surface)
      @transition_initial_frame[surface] = false if initial_frame
      request_frames if initial_frame

      Zaniah::Div.new.key([:hadar_slide_transition, surface, @transition_generation.fetch(surface)])
        .w_full.h_full.opacity(initial_frame ? 0.0 : 1.0)
        .transition(:opacity, duration: 0.24, easing: :ease_out)
        .child(element)
    end

    def window_for(name)
      target = case name
      when :main then @main_window
      when :presenter then @presenter_window
      else raise ArgumentError, "window must be :main or :presenter"
      end
      raise Error, "#{name} window is not attached" unless target

      target
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
