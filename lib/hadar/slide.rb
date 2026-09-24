# frozen_string_literal: true

module Hadar
  class Slide
    attr_reader :index, :document, :nodes, :layout, :slots, :theme, :notes, :placements

    def initialize(index:, document:, nodes:, layout: nil, theme:, deck:)
      @index, @document, @nodes, @theme, @deck = index, document, nodes.freeze, theme, deck
      @notes, @notes_ranges = extract_notes
      @layout = Layout.select(content_nodes, requested: layout)
      @placements = {}
      @slots = build_slots.freeze
      @placements.freeze
      freeze
    end

    def slot(name)
      slots.fetch(name.to_sym) do
        Slot.new(name: name, nodes: [], document: document, deck: @deck, slide_index: index)
      end
    end

    def title
      return slot(:title).text unless layout == :freeform

      slots.values.find { |entry| entry.nodes.first&.type == :heading }&.text.to_s
    end

    private

    def content_nodes
      nodes.reject { |node| layout_directive?(node) || speaker_note_node?(node) }
    end

    def extract_notes
      entries = nodes.filter_map do |node|
        if note_directive?(node)
          [node.range, normalize_notes(node.attributes.dig(:values, "notes"))]
        elsif node.type == :html_block
          multiline_notes(node)
        end
      end
      [entries.empty? ? nil : entries.map(&:last).join("\n\n").freeze,
       entries.flat_map { |range, _| note_ranges_for(range) }.freeze]
    end

    def multiline_notes(node)
      source = document.source
      return unless source.byteslice(node.range).match?(/\A[ \t]{0,3}<!--[ \t]*notes[ \t]*:/)

      terminator = source.b.index("-->".b, node.range.begin)
      return unless terminator && terminator + 3 <= nodes.last.range.end

      range = node.range.begin...(terminator + 3)
      values = Beid::Directive.parse(source.byteslice(range))
      return unless values&.key?("notes")

      [range, normalize_notes(values.fetch("notes"))]
    end

    def note_ranges_for(range)
      nodes.filter_map do |node|
        node.range if node.range.begin < range.end && range.begin < node.range.end
      end
    end

    def normalize_notes(value)
      value.to_s.sub(/\A(?:\r\n|\r|\n)/, "").sub(/(?:\r\n|\r|\n)\z/, "")
    end

    def note_directive?(node)
      node.type == :directive && node.attributes[:kind] == :html_comment &&
        node.attributes.dig(:values, "notes")
    end

    def speaker_note_node?(node)
      note_directive?(node) || @notes_ranges.any? do |range|
        node.range.begin < range.end && range.begin < node.range.end
      end
    end

    def build_slots
      content = content_nodes
      return build_freeform_slots(content) if layout == :freeform

      definition = Layout.fetch(layout)
      mapping = definition.slots.to_h { |name| [name, []] }
      case layout
      when :title
        headings = content.select { |node| node.type == :heading }
        mapping[:title] = headings.take(1)
        mapping[:subtitle] = headings.drop(1)
      when :title_body
        heading = content.find { |node| node.type == :heading }
        mapping[:title] = [heading].compact
        mapping[:body] = content.reject { |node| node.equal?(heading) }
      when :two_column
        mapping[:title] = content.find { |node| node.type == :heading }&.then { |node| [node] } || []
        content.each do |node|
          next unless node.type == :directive && node.attributes[:kind] == :div

          target = node.attributes[:name].to_s.to_sym
          mapping[target] = node.children if %i[left right].include?(target)
        end
      when :image_text
        image = content.flat_map { |node| descendants(node, :image) }.first
        mapping[:image] = [image].compact
        mapping[:title] = content.find { |node| node.type == :heading }&.then { |node| [node] } || []
        mapping[:text] = content.reject { |node| node.equal?(mapping[:title].first) || contains?(node, image) }
      when :full_bleed_image
        mapping[:image] = content.flat_map { |node| descendants(node, :image) }
      when :quote
        mapping[:quote] = content.select { |node| node.type == :block_quote }
        mapping[:attribution] = content.reject { |node| node.type == :block_quote }
      when :code
        mapping[:title] = content.find { |node| node.type == :heading }&.then { |node| [node] } || []
        mapping[:code] = content.select { |node| node.type == :code_block }
      end
      mapping.to_h do |name, entries|
        [name, Slot.new(name: name, nodes: entries, document: document,
          deck: @deck, slide_index: index)]
      end
    end

    def build_freeform_slots(content)
      pending = nil
      slots = {}
      content.each do |node|
        next if node.type == :link_definition

        if placement_directive?(node)
          raise Error, "freeform placement must be followed by one content block" if pending

          pending = parse_placement(node.attributes.dig(:values, "place"))
          next
        end
        raise Error, "freeform content requires a preceding place directive" unless pending

        name = :"item_#{slots.length + 1}"
        body = node.type == :paragraph && node.children.one? && node.children.first.type == :image ? node.children.first : node
        slots[name] = Slot.new(name: name, nodes: [body], document: document,
          deck: @deck, slide_index: index)
        @placements[name] = pending.freeze
        pending = nil
      end
      raise Error, "freeform placement must be followed by one content block" if pending

      slots
    end

    def placement_directive?(node)
      node.type == :directive && node.attributes[:kind] == :html_comment &&
        node.attributes[:values]&.key?("place")
    end

    def parse_placement(value)
      unless value.to_s.match?(/\A\s*\d+(?:\.\d+)?\s*,\s*\d+(?:\.\d+)?\s*,\s*\d+(?:\.\d+)?\s*,\s*\d+(?:\.\d+)?\s*\z/)
        raise Error, "place must contain x,y,width,height percentages"
      end
      x, y, width, height = value.split(",").map { |part| Float(part) }
      unless width.positive? && height.positive? && x + width <= 100 && y + height <= 100
        raise Error, "freeform placement must fit within the slide (0–100%)"
      end

      [x, y, width, height]
    end

    def layout_directive?(node)
      node.type == :directive && node.attributes[:kind] == :html_comment &&
        node.attributes[:values]&.key?("layout")
    end

    def descendants(node, type)
      [node, *node.children.flat_map { |child| descendants(child, type) }].select { |entry| entry.type == type }
    end

    def contains?(node, target)
      target && (node.equal?(target) || node.children.any? { |child| contains?(child, target) })
    end
  end
end
