# frozen_string_literal: true

require "spica"

module Hadar
  class CommandPalette < Zaniah::UI::Modal
    attr_reader :query

    def initialize(commands)
      @commands = commands.to_h.freeze
      @index = Spica::Index.new(@commands.keys)
      @session = @index.session
      @query = ""
      super(Zaniah::Div.new, title: "Command palette", open: false, width: 520)
    end

    def query=(value)
      @session.query = value
      @query = @session.query
    end

    def matches(limit = 20) = @session.matches(limit)

    def choose(label, event = nil, context = nil)
      command = @commands.fetch(label) { raise ArgumentError, "unknown command: #{label}" }
      command&.call(event, context)
      dismiss(event, context)
    end

    def build(cx)
      field = Zaniah::UI::SearchInput.new(query, placeholder: "Search commands…")
        .on_change do |value, context|
          self.query = value
          context.window.request_frame
        end
      results = Zaniah::Div.new.gap(cx.theme.spacing[1]).children(matches.map do |match|
        Zaniah::UI::Button.new(match.candidate, variant: :ghost).w_full.on_click do |event, context|
          choose(match.candidate, event, context)
        end
      end)
      @content = Zaniah::Div.new.gap(cx.theme.spacing[2]).child(field).child(results)
      super
    end

    def tui_cells(*) = "> #{query}\n" + matches.map(&:candidate).join("\n")

    def accessibility_node(cx)
      return unless open?

      node(:dialog, label: "Command palette", states: {modal: true}, children: [
        Zaniah::Accessibility.node(role: :searchbox, label: "Search commands", value: query),
        Zaniah::Accessibility.node(role: :list,
          children: matches.map { |match| Zaniah::Accessibility.node(role: :listitem, label: match.candidate) })
      ], actions: [:dismiss])
    end
  end
end
