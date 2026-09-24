# frozen_string_literal: true

# APP-SPECIFIC: presenter commands and keymap remain local; Q6 found no shared three-app contract.
module Hadar
  class Application
    attr_reader :deck, :renderer, :presenter, :selected_index, :selected_slot_name, :slide_list, :keymap, :body_editor

    def self.presenter_display(displays)
      unless displays.is_a?(Array) && displays.all? { |display| display.is_a?(Zaniah::Platform::Display) }
        raise TypeError, "displays must be an Array of Zaniah::Platform::Display values"
      end
      return if displays.length < 2

      return displays[1] unless displays.any?(&:primary)

      displays.find { |display| !display.primary } || displays[1]
    end

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
        .bind("ctrl-s", :save)
        .bind("cmd-s", :save)
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
      @selected_slot_name = default_slot_name(deck.slide(@selected_index)) if @selected_index
      @presenter = Presenter.new(deck, renderer: renderer, clock: clock)
      @windows = []
      @main_window = @presenter_window = nil
      @owned_presenter_window = nil
      @fullscreen = {main: false, presenter: false}
      @transition_generation = {main: 0, presenter: 0}
      @transition_initial_frame = {main: false, presenter: false}
      @closed = false
      @running = false
      @command_palette = nil
      @body_editor = nil
      @body_editor_index = nil
      @body_editor_error = nil
      @table_selection = @table_draft = nil
      @code_block_index = 0
      @code_draft = nil
      rebuild_slide_list
      @watcher = deck.source_path && watch ? deck.watch(on_reload: ->(_updated) { deck_reloaded }) : nil
    end

    def attach(main_window:, presenter_window: nil)
      @main_window = main_window
      attach_window(main_window) do |window|
        main_view(width: window.content_size.width, height: window.content_size.height)
      end
      unless presenter_window
        presenter_window = automatic_presenter_window(main_window)
        @owned_presenter_window = presenter_window
      end
      @presenter_window = presenter_window
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
      workspace = Zaniah::Div.new.flex_row.flex_1
        .child(Zaniah::Div.new.flex_1.child(transition_view(preview, :main)))
      unless presenter.started?
        editor, error = slot_editor_for_selected_slide
        editor_width = [[(Float(width) - sidebar_width) * 0.36, 420].min, 160].max
        slot_title = selected_slot_name&.to_s&.capitalize || "No slots"
        editor_pane = Zaniah::Div.new.w(editor_width).h_full.p(12).gap(8)
          .style(flex_direction: :column, border: 1, border_color: deck.theme.colors.fetch("muted"))
        editor_pane.child(Zaniah::UI::Label.new(slot_title, size: :sm))
        if selected_index && deck.slide(selected_index).layout == :freeform
          editor_pane.child(Zaniah::UI::Label.new("Freeform — このスライドは素の Markdown ビューアでは崩れます", tone: :muted))
        end
        editor_pane.child(slot_selector) if selected_index && deck.slide(selected_index).slots.any?
        editor_pane.child(editor.w_full.flex_1) if editor
        editor_pane.child(Zaniah::UI::Label.new("Editing unavailable: #{error}", tone: :muted)) if error
        workspace.child(editor_pane)
      end
      view = Zaniah::Div.new.flex_row.w(width).h(height)
        .child(slide_list.build(width: sidebar_width, height: height))
        .child(workspace)
      view.child(@command_palette) if @command_palette
      view
    end

    def command_palette = @command_palette

    def export_png_sequence(directory, width: 1280, height: 720)
      Export::PNGSequence.write(deck, directory, renderer: renderer, width: width, height: height)
    end

    def export_apng(path, width: 1280, height: 720, duration_ms: Export::APNG::DEFAULT_DURATION_MS, loop: 0, overwrite: false)
      Export::APNG.write(deck, path, renderer: renderer, width: width, height: height,
        duration_ms: duration_ms, loop: loop, overwrite: overwrite)
    end

    def save(path = nil, overwrite: false)
      path ? deck.save(path, overwrite: overwrite) : deck.save(overwrite: overwrite)
    end

    def selected_slot
      return unless selected_index && selected_slot_name

      deck.slide(selected_index).slot(selected_slot_name)
    end

    def select_slot(name)
      raise Error, "there is no selected slide" unless selected_index
      raise TypeError, "slot name must be a String or Symbol" unless name.is_a?(String) || name.is_a?(Symbol)

      slot_name = name.to_sym
      slot = deck.slide(selected_index).slots.fetch(slot_name) { raise IndexError, "slot is not available on this slide: #{slot_name}" }
      return slot if selected_slot_name == slot_name

      @selected_slot_name = slot_name
      reset_slot_editor
      slot
    end

    def select_table_cell(table:, row:, column:)
      slot = selected_slot || raise(Error, "there is no selected slot")
      rows = slot.table_rows(table: table)
      rows.fetch(row).fetch(column)
      @table_selection = [table, row, column]
      @table_draft = nil
      request_frames
      @table_selection
    end

    def select_code_block(index)
      slot = selected_slot || raise(Error, "there is no selected slot")
      block = slot.nodes.select { |node| node.type == :code_block }.fetch(index)
      @code_block_index, @code_draft = index, nil
      request_frames
      block
    end

    def insert_or_replace_selected_image(path)
      slot = selected_slot || raise(Error, "there is no selected slot")
      raise Error, "select the image slot first" unless image_slot?(slot)

      updated = slot.empty? ? slot.insert_image(path) : slot.replace_image(path)
      finish_slot_edit
      updated
    end

    def replace_selected_table_cell(value)
      slot = selected_slot || raise(Error, "there is no selected slot")
      table, row, column = @table_selection || default_table_selection(slot)
      updated = slot.replace_table_cell(row: row, column: column, value: value, table: table)
      finish_slot_edit
      updated
    end

    def replace_selected_code(text)
      slot = selected_slot || raise(Error, "there is no selected slot")
      updated = slot.replace_code(text, block: @code_block_index)
      finish_slot_edit
      updated
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
        @windows.dup.each do |window|
          window.tick unless window.closed?
          close_owned_presenter_window if window.equal?(@main_window) && window.closed?
          restore_reloaded_body_editor_focus(window) if window.equal?(@main_window)
        end
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
      close_owned_presenter_window
      @windows.clear
      self
    end

    def stop
      @running = false
      self
    end

    private

    def automatic_presenter_window(main_window)
      return unless main_window.respond_to?(:displays)

      display = self.class.presenter_display(main_window.displays)
      return unless display

      backend, options = presenter_backend(main_window)
      return unless backend

      window = Zaniah::Platform.open_window(backend: backend, **options,
        width: main_window.content_size.width, height: main_window.content_size.height,
        scale_factor: main_window.scale_factor, title: "Hadar Presenter")
      if window.respond_to?(:fullscreen_on)
        raise Error, "could not place the presenter window on the secondary display" unless window.fullscreen_on(display)
        @fullscreen[:presenter] = true
      else
        raise Error, "could not place the presenter window on the secondary display" unless window.move_to_display(display)
        if window.respond_to?(:toggle_fullscreen)
          window.toggle_fullscreen
          @fullscreen[:presenter] = true
        end
      end
      window
    rescue StandardError
      window&.close unless window&.closed?
      raise
    end

    def presenter_backend(window)
      ancestors = window.class.ancestors.filter_map(&:name)
      return [:mac, {}] if ancestors.include?("Zaniah::Platform::Mac::Window")
      return [:linux, {display_server: :wayland}] if ancestors.include?("Zaniah::Platform::Linux::WaylandWindow")
      return [:linux, {display_server: :x11}] if ancestors.include?("Zaniah::Platform::Linux::Window")
      return [:windows, {}] if ancestors.include?("Zaniah::Platform::Windows::Window")
      return [:headless, {}] if ancestors.include?("Zaniah::Platform::Headless::Window")

      [nil, {}]
    end

    def close_owned_presenter_window
      window = @owned_presenter_window
      return unless window

      @owned_presenter_window = nil
      window.close unless window.closed?
    end

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
      when :save
        save
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
        "Save" => ->(*) { save },
        "Export PNG sequence…" => ->(*) { prompt_png_sequence_directory },
        "Export APNG…" => ->(*) { prompt_apng_path }
      }
    end

    def prompt_png_sequence_directory
      unless @main_window.respond_to?(:prompt_for_paths)
        raise Error, "this window backend cannot choose a directory; call export_png_sequence(directory)"
      end

      directory = @main_window.prompt_for_paths(directories: true).first
      export_png_sequence(directory) if directory && !directory.empty?
    end

    def prompt_apng_path
      unless @main_window.respond_to?(:prompt_for_paths)
        raise Error, "this window backend cannot choose a file; call export_apng(path)"
      end

      path = @main_window.prompt_for_paths(save: true).first
      return unless path && !path.empty?

      path = "#{path}.apng" if File.extname(path).empty?
      export_apng(path, overwrite: true)
    end

    def slot_editor_for_selected_slide
      return [nil, nil] unless selected_index
      unless selected_slot_name
        @body_editor_error ||= deck.slide(selected_index).layout == :freeform ?
          "select a block to edit after reloading this freeform slide" : "this slide has no editable slots"
        return [nil, @body_editor_error]
      end

      slot = selected_slot
      if image_slot?(slot)
        pending_body_editor_focus(:clear) if @pending_body_editor_reload && @pending_body_editor_reload[:slot] == slot.name
        [image_slot_editor(slot), @body_editor_error]
      elsif slot.nodes.any? { |node| %i[table code_block].include?(node.type) }
        pending_body_editor_focus(:clear) if @pending_body_editor_reload && @pending_body_editor_reload[:slot] == slot.name
        panels = []
        panels << table_slot_editor(slot) if slot.nodes.any? { |node| node.type == :table }
        panels << code_slot_editor(slot) if slot.nodes.any? { |node| node.type == :code_block }
        [Zaniah::Div.new.flex_col.gap(12).children(panels), @body_editor_error]
      else
        rich_text_slot_editor(slot)
      end
    rescue Error, ArgumentError, IndexError, TypeError => error
      @body_editor_error = error.message
      [nil, @body_editor_error]
    end

    def rich_text_slot_editor(slot)
      key = [selected_index, selected_slot_name]
      return [@body_editor, @body_editor_error] if @body_editor_index == key
      if slot.empty?
        @body_editor_error = "the #{slot.name} slot is empty"
        pending_body_editor_focus(:clear) if @pending_body_editor_reload
        return [nil, @body_editor_error]
      end

      @body_editor_index = key
      @body_editor = slot.rich_text
      restore_body_editor_selection
      [@body_editor, @body_editor_error]
    rescue Error => error
      @body_editor = nil
      @body_editor_error = error.message
      pending_body_editor_focus(:clear) if @pending_body_editor_reload
      [nil, @body_editor_error]
    end

    def slot_selector
      buttons = deck.slide(selected_index).slots.keys.map do |name|
        Zaniah::UI::Button.new(name.to_s.capitalize, size: :sm,
          variant: name == selected_slot_name ? :secondary : :ghost)
          .key([:hadar_slot, selected_index, name])
          .on_click { select_slot(name) }
      end
      Zaniah::UI::ButtonGroup.new(*buttons)
    end

    def image_slot_editor(slot)
      return Zaniah::UI::Label.new("Select an image slot to insert or replace an image.") unless image_slot?(slot)
      if !slot.empty? && !(slot.nodes.one? && slot.nodes.first.type == :image)
        return Zaniah::UI::Label.new("This image slot contains multiple images and cannot be edited safely.", tone: :muted)
      end

      panel = Zaniah::Div.new.flex_col.gap(8)
      panel.child(Zaniah::UI::Label.new(slot.empty? ? "No image selected" : "Image: #{slot.image_path}", tone: :muted))
      panel.child(Zaniah::UI::Button.new(slot.empty? ? "Insert image…" : "Replace image…", variant: :secondary)
        .on_click { safely_edit_slot { prompt_for_image } })
      panel
    end

    def table_slot_editor(slot)
      tables = slot.nodes.select { |node| node.type == :table }
      table, row, column = @table_selection || default_table_selection(slot)
      rows = slot.table_rows(table: table)
      return Zaniah::UI::Label.new("This table has no editable cells.", tone: :muted) if rows.empty? || rows.all?(&:empty?)

      row = rows.index { |cells| !cells.empty? } if rows[row]&.empty?
      column = [column, rows[row].length - 1].min

      cell = rows.fetch(row).fetch(column)
      panel = Zaniah::Div.new.flex_col.gap(8)
        .child(Zaniah::UI::Label.new("Edit one plain-text cell; Markdown delimiters and newlines are not accepted.", tone: :muted))
      panel.child(Zaniah::UI::Select.new(tables.each_index.map { |index| ["Table #{index + 1}", index] },
        label: "Table", value: table).on_change do |value, _event, _context|
          rows = slot.table_rows(table: value)
          unless rows.empty? || rows.all?(&:empty?)
            row = [row, rows.length - 1].min
            row = rows.index { |cells| !cells.empty? } if rows[row].empty?
            select_table_cell(table: value, row: row, column: [column, rows[row].length - 1].min)
          end
        end)
      panel.child(Zaniah::UI::Select.new(rows.each_index.map { |index| ["Row #{index + 1}", index] },
        label: "Row", value: row).on_change do |value, _event, _context|
          cells = rows.fetch(value)
          select_table_cell(table: table, row: value, column: [column, cells.length - 1].min) unless cells.empty?
        end)
      panel.child(Zaniah::UI::Select.new(rows[row].each_index.map { |index| ["Column #{index + 1}", index] },
        label: "Column", value: column).on_change do |value, _event, _context|
          select_table_cell(table: table, row: row, column: value)
        end)
      field_value = @table_draft.nil? ? cell : @table_draft
      if !@table_field || @table_field.value != field_value
        @table_field = Zaniah::UI::TextField.new(field_value, label: "Cell text")
          .on_change { |value, _context| @table_draft = value }
      end
      panel.child(@table_field)
      panel.child(Zaniah::UI::Button.new("Apply cell", size: :sm)
        .on_click { safely_edit_slot { replace_selected_table_cell(@table_draft.nil? ? cell : @table_draft) } })
      panel
    end

    def code_slot_editor(slot)
      blocks = slot.nodes.select { |node| node.type == :code_block }
      block = blocks.fetch(@code_block_index)
      panel = Zaniah::Div.new.flex_col.gap(8)
      panel.child(Zaniah::UI::Label.new("Code preview is syntax-highlighted when Antares supports its language.", tone: :muted))
      panel.child(Zaniah::UI::Select.new(blocks.each_index.map { |index| ["Block #{index + 1}", index] },
        label: "Code block", value: @code_block_index).on_change do |index, _event, _context|
          select_code_block(index)
        end) if blocks.length > 1
      editor_key = [selected_index, selected_slot_name, @code_block_index]
      editor_value = @code_draft.nil? ? slot.text_for(block) : @code_draft
      if !@code_editor || @code_editor_key != editor_key
        @code_editor_key = editor_key
        @code_editor = Zaniah::UI::CodeEditor.new(editor_value, language: block.attributes[:info])
          .w_full.flex_1.on_change { |text, _context| @code_draft = text }
      elsif @code_editor.value != editor_value
        @code_editor.buffer.replace(0...@code_editor.buffer.bytesize, editor_value)
      end
      panel.child(@code_editor)
      panel.child(Zaniah::UI::Button.new("Apply code", size: :sm)
        .on_click { safely_edit_slot { replace_selected_code(@code_draft.nil? ? slot.text_for(block) : @code_draft) } })
      panel
    end

    def prompt_for_image
      unless @main_window&.respond_to?(:prompt_for_paths)
        raise Error, "this window backend cannot choose an image file"
      end

      path = @main_window.prompt_for_paths.first
      insert_or_replace_selected_image(path) if path && !path.empty?
    end

    def safely_edit_slot
      yield
    rescue Error, ArgumentError, IndexError, TypeError => error
      @body_editor_error = error.message
      request_frames
      nil
    end

    def default_table_selection(slot)
      rows = slot.table_rows
      [0, rows.length > 1 ? 1 : 0, 0]
    end

    def finish_slot_edit
      @body_editor = @body_editor_index = nil
      @body_editor_error = @table_draft = @code_draft = nil
      @table_field = @code_editor = @code_editor_key = nil
      request_frames
    end

    def reset_slot_editor
      @body_editor = @body_editor_index = @body_editor_error = nil
      @table_selection = @table_draft = nil
      @code_block_index, @code_draft = 0, nil
      @table_field = @code_editor = @code_editor_key = nil
      @pending_body_editor_reload = nil
      request_frames
    end

    def reset_slot_editor_state_after_reload
      @body_editor = @body_editor_index = @body_editor_error = nil
      @table_selection = @table_draft = nil
      @code_block_index, @code_draft = 0, nil
      @table_field = @code_editor = @code_editor_key = nil
    end

    def default_slot_name(slide)
      slide.slots.key?(:body) ? :body : slide.slots.keys.first
    end

    def image_slot?(slot)
      slot.name == :image || (slot.nodes.one? && slot.nodes.first.type == :image)
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
          @selected_slot_name = default_slot_name(deck.slide(index))
          reset_slot_editor
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
      previous_index = selected_index
      previous_slot = selected_slot_name
      previous_editor = @body_editor if @body_editor_index == [previous_index, previous_slot]
      previous_focus = previous_editor && @main_window&.dispatcher&.focused.equal?(previous_editor.focus_handle)
      @pending_body_editor_reload = if previous_editor
        {index: previous_index, slot: previous_slot, text: previous_editor.text, selection: previous_editor.selection,
         focus: previous_focus ? :pending : :none}
      end
      @selected_index = if deck.empty?
        nil
      else
        [[selected_index || 0, 0].max, deck.length - 1].min
      end
      @pending_body_editor_reload = nil if @selected_index != previous_index
      @selected_slot_name = if @selected_index && deck.slide(@selected_index).layout == :freeform
        nil # Positional item IDs may now refer to different blocks; require explicit reselection.
      elsif @selected_index && deck.slide(@selected_index).slots.key?(previous_slot)
        previous_slot
      else
        @selected_index && default_slot_name(deck.slide(@selected_index))
      end
      reset_slot_editor_state_after_reload
      presenter.reconcile!
      rebuild_slide_list
      request_frames
    end

    def restore_body_editor_selection
      pending = @pending_body_editor_reload
      return unless pending && pending[:index] == selected_index && pending[:slot] == selected_slot_name

      selection = remap_text_selection(pending[:text], @body_editor.text, pending[:selection])
      @body_editor.selection = selection || Zaniah::TextSelection.new(0)
      pending_body_editor_focus(pending[:focus] == :pending && selection ? :restore :
        (pending[:focus] == :pending ? :clear : :none))
    end

    def pending_body_editor_focus(action)
      @pending_body_editor_reload[:focus] = action if @pending_body_editor_reload
    end

    def restore_reloaded_body_editor_focus(window)
      pending = @pending_body_editor_reload
      return unless pending
      if pending[:index] != selected_index || pending[:slot] != selected_slot_name
        window.dispatcher.focus(nil, origin: :programmatic) unless pending[:focus] == :none
        @pending_body_editor_reload = nil
        return
      end

      case pending[:focus]
      when :restore
        window.dispatcher.focus(@body_editor&.focus_handle, origin: :programmatic)
      when :clear
        window.dispatcher.focus(nil, origin: :programmatic)
      end
      @pending_body_editor_reload = nil
    end

    def remap_text_selection(old_text, new_text, selection)
      return selection if old_text == new_text

      old_clusters = Zaniah::Unicode.grapheme_clusters(old_text)
      new_clusters = Zaniah::Unicode.grapheme_clusters(new_text)
      prefix = 0
      while prefix < old_clusters.length && prefix < new_clusters.length && old_clusters[prefix] == new_clusters[prefix]
        prefix += 1
      end
      suffix = 0
      while suffix < old_clusters.length - prefix && suffix < new_clusters.length - prefix &&
          old_clusters[old_clusters.length - suffix - 1] == new_clusters[new_clusters.length - suffix - 1]
        suffix += 1
      end

      old_prefix_end = old_clusters.take(prefix).join.bytesize
      old_suffix_start = old_clusters.take(old_clusters.length - suffix).join.bytesize
      new_suffix_start = new_clusters.take(new_clusters.length - suffix).join.bytesize
      range = selection.range

      if selection.collapsed?
        position = selection.head
        return Zaniah::TextSelection.new(position) if position < old_prefix_end
        return Zaniah::TextSelection.new(position + new_suffix_start - old_suffix_start) if position > old_suffix_start
        return if old_prefix_end == old_suffix_start
        return Zaniah::TextSelection.new(position) if position == old_prefix_end
        return Zaniah::TextSelection.new(position + new_suffix_start - old_suffix_start) if position == old_suffix_start

        return
      end

      if range.end <= old_prefix_end
        selection
      elsif range.begin >= old_suffix_start
        delta = new_suffix_start - old_suffix_start
        Zaniah::TextSelection.new(selection.anchor + delta, selection.head + delta)
      end
    end

    def request_frames
      @windows.each(&:request_frame)
    end
  end
end
