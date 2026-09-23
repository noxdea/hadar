# frozen_string_literal: true

module Hadar
  class RichTextProjection
    Segment = Data.define(:start, :finish, :text, :node, :style, :wrappers, :list_item, :list_level)
    attr_reader :document, :text, :segments, :list_context, :paragraph_styles

    def initialize(slot)
      @document = slot.document
      @list_context = {}
      @parts = join(slot.nodes.map { |node| project(node, {}, [], -1, nil) }, "\n")
      @text = @parts.map(&:first).join.freeze
      offset = 0
      @segments = @parts.map do |part, node, style, wrappers, list_item, list_level|
        segment = Segment.new(offset, offset + part.bytesize, part, node, style.freeze, wrappers.freeze, list_item, list_level)
        offset += part.bytesize
        segment
      end.freeze
      @paragraph_styles = Array.new(@text.count("\n") + 1) { {} }
      @segments.each do |segment|
        next unless segment.list_level

        first = @text.byteslice(0...segment.start).to_s.count("\n")
        last = @text.byteslice(0...segment.finish).to_s.count("\n")
        (first..last).each { |line| @paragraph_styles[line] = {level: segment.list_level} }
      end
      raise Error, "slot content is not representable as rich text" unless @text == slot.text
    end

    def build(editable: true)
      runs = @parts.map { |part, _node, style, _wrappers, _item, _level| {text: part, **style} }
      value = Zaniah::UI::RichText.new(runs, selectable: true, editable: editable)
      line_start = 0
      @paragraph_styles.each_with_index do |style, index|
        line_end = @text.b.index("\n".b, line_start) || @text.bytesize
        value.paragraph_style(line_start...line_end, level: style[:level]) if style.key?(:level)
        line_start = line_end + 1
      end
      value
    end

    def replace(value)
      RichTextWriteback.new(self, value).replace
    end

    private

    def project(node, style, wrappers, list_level, parent_item)
      case node.type
      when :text
        leaf(node.attributes.fetch(:text, ""), node, style, wrappers, parent_item, list_level)
      when :code_span
        leaf(node.attributes.fetch(:text, ""), node, style.merge(font: "monospace"), wrappers, parent_item, list_level)
      when :image
        leaf(node.attributes.fetch(:label, ""), node, style, wrappers, parent_item, list_level)
      when :break, :softbreak
        leaf("\n", node, style, wrappers, parent_item, list_level)
      when :strong
        children(node.children, style.merge(bold: true), wrappers + [[:bold, node]], list_level, parent_item)
      when :emphasis
        children(node.children, style.merge(italic: true), wrappers + [[:italic, node]], list_level, parent_item)
      when :link
        children(node.children, style.merge(link: node.attributes.fetch(:destination)), wrappers, list_level, parent_item)
      when :paragraph, :heading
        children(node.children, style, wrappers, list_level, parent_item)
      when :block_quote
        join(node.children.map { |child| project(child, style, wrappers, list_level, parent_item) }, "\n")
      when :list, :ordered_list
        level = list_level + 1
        items = node.children.each_with_index.map do |item, index|
          @list_context[item.object_id] = {level: level, list: node, previous: node.children[index - 1],
            parent: parent_item}
          marker = if item.attributes[:task]
            item.attributes[:checked] ? "☑ " : "☐ "
          elsif item.attributes[:ordered]
            "#{item.attributes[:start] || index + 1}. "
          else
            "• "
          end
          [[marker, item, {}, [], item, level], *project(item, style, wrappers, level, item)]
        end
        join(items, "\n")
      when :list_item
        join(node.children.map { |child| project(child, style, wrappers, list_level, node) }, "\n")
      when :footnote_reference, :task_checkbox, :front_matter, :directive, :thematic_break
        []
      when :strikethrough
        raise Error, "strikethrough has no Zaniah rich-text style"
      else
        raise Error, "#{node.type} slots are not supported by rich-text editing"
      end
    end

    def children(nodes, style, wrappers, list_level, parent_item)
      nodes.flat_map { |node| project(node, style, wrappers, list_level, parent_item) }
    end

    def leaf(text, node, style, wrappers, list_item, list_level)
      text.empty? ? [] : [[text, node, style, wrappers, list_item, list_item ? list_level : nil]]
    end

    def join(groups, separator)
      groups.reject { |parts| parts.empty? || parts.all? { |part, _node, _style, _wrappers, _item, _level| part.empty? } }
        .each_with_object([]) do |parts, result|
          result << [separator, nil, {}, [], nil, nil] unless result.empty?
          result.concat(parts)
        end
    end
  end
end
