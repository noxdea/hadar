# frozen_string_literal: true

module Hadar
  class Slide
    attr_reader :index, :document, :nodes, :layout, :slots, :theme

    def initialize(index:, document:, nodes:, layout: nil, theme:, deck:)
      @index, @document, @nodes, @theme, @deck = index, document, nodes.freeze, theme, deck
      @layout = Layout.select(content_nodes, requested: layout)
      @slots = build_slots.freeze
      freeze
    end

    def slot(name)
      slots.fetch(name.to_sym) do
        Slot.new(name: name, nodes: [], document: document, deck: @deck, slide_index: index)
      end
    end

    def title = slot(:title).text

    private

    def content_nodes
      nodes.reject { |node| layout_directive?(node) }
    end

    def build_slots
      content = content_nodes
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
