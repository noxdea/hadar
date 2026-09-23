# frozen_string_literal: true

module Hadar
  class RichTextProjection
    Segment = Data.define(:start, :finish, :text, :node, :style, :wrappers)
    attr_reader :document, :text, :segments

    def initialize(slot)
      @document = slot.document
      @parts = join(slot.nodes.map { |node| project(node, {}, []) }, "\n")
      @text = @parts.map(&:first).join.freeze
      offset = 0
      @segments = @parts.map do |part, node, style, wrappers|
        segment = Segment.new(offset, offset + part.bytesize, part, node, style.freeze, wrappers.freeze)
        offset += part.bytesize
        segment
      end.freeze
      raise Error, "slot content is not representable as rich text" unless @text == slot.text
    end

    def build(editable: true)
      runs = @parts.map { |part, _node, style, _wrappers| {text: part, **style} }
      Zaniah::UI::RichText.new(runs, selectable: true, editable: editable)
    end

    def replace(value)
      RichTextWriteback.new(self, value).replace
    end

    private

    def project(node, style, wrappers)
      case node.type
      when :text
        leaf(node.attributes.fetch(:text, ""), node, style, wrappers)
      when :code_span
        leaf(node.attributes.fetch(:text, ""), node, style.merge(font: "monospace"), wrappers)
      when :image
        leaf(node.attributes.fetch(:label, ""), node, style, wrappers)
      when :break
        leaf("\n", node, style, wrappers)
      when :strong
        children(node.children, style.merge(bold: true), wrappers + [[:bold, node]])
      when :emphasis
        children(node.children, style.merge(italic: true), wrappers + [[:italic, node]])
      when :link
        children(node.children, style.merge(link: node.attributes.fetch(:destination)), wrappers)
      when :paragraph, :heading
        children(node.children, style, wrappers)
      when :block_quote
        join(node.children.map { |child| project(child, style, wrappers) }, "\n")
      when :list, :ordered_list
        items = node.children.each_with_index.map do |item, index|
          marker = if item.attributes[:task]
            item.attributes[:checked] ? "☑ " : "☐ "
          elsif item.attributes[:ordered]
            "#{item.attributes[:start] || index + 1}. "
          else
            "• "
          end
          [[marker, nil, {}, []], *project(item, style, wrappers)]
        end
        join(items, "\n")
      when :list_item
        children(node.children, style, wrappers)
      when :footnote_reference, :task_checkbox, :front_matter, :directive, :thematic_break
        []
      when :strikethrough
        raise Error, "strikethrough has no Zaniah rich-text style"
      else
        raise Error, "#{node.type} slots are not supported by rich-text editing"
      end
    end

    def children(nodes, style, wrappers)
      nodes.flat_map { |node| project(node, style, wrappers) }
    end

    def leaf(text, node, style, wrappers)
      text.empty? ? [] : [[text, node, style, wrappers]]
    end

    def join(groups, separator)
      groups.reject { |parts| parts.empty? || parts.all? { |part, _node, _style, _wrappers| part.empty? } }
        .each_with_object([]) do |parts, result|
          result << [separator, nil, {}, []] unless result.empty?
          result.concat(parts)
        end
    end
  end
end
