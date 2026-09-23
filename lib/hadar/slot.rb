# frozen_string_literal: true

require "uri"

module Hadar
  class Slot
    attr_reader :name, :nodes, :document, :slide_index

    def initialize(name:, nodes:, document:, deck:, slide_index:)
      @name = name.to_sym
      @nodes = nodes.freeze
      @document = document
      @deck, @slide_index = deck, slide_index
      freeze
    end

    def empty? = nodes.empty?

    def markdown
      nodes.map { |node| document.source.byteslice(node.range) }.join("\n")
    end

    def text
      nodes.map { |node| plain_text(node) }.reject(&:empty?).join("\n")
    end

    def text_for(node)
      raise TypeError, "node must be a Beid::Node" unless node.is_a?(Beid::Node)
      raise Error, "node is not part of this slot" unless nodes.include?(node)

      plain_text(node)
    end

    def table_rows(table: 0)
      node = table_nodes.fetch(valid_index!(table, "table")) do
        raise IndexError, "table index is outside the slot"
      end
      node.children.filter_map do |row|
        row.children.map { |cell| plain_text(cell) } if row.type == :table_row
      end
    end

    def image_path
      return if nodes.empty?
      raise Error, "image_path requires a slot containing exactly one image" unless nodes.one? && nodes.first.type == :image

      destination = nodes.first.attributes.fetch(:destination)
      destination.match?(/\Ahttps?:\/\//i) ? destination : URI::DEFAULT_PARSER.unescape(destination)
    end

    def resolved_image_path
      path = image_path
      path && @deck.resolve_image_path(path)
    end

    def replace_text(text)
      @deck.replace_text(self, text)
    end

    def rich_text(editable: true)
      value = RichTextProjection.new(self).build(editable: editable)
      return value unless editable

      deck, slide_index, name, source_document = @deck, @slide_index, @name, @document
      value.on_change do |_text, rich_text|
        raise Error, "rich text editor is stale; rebuild it from the current slot" unless deck.document.equal?(source_document)

        deck.slide(slide_index).slot(name).replace_rich_text(rich_text)
        source_document = deck.document
      end
      value
    end

    def replace_rich_text(value)
      @deck.replace_rich_text(self, value)
    end

    def replace_image(path)
      @deck.replace_image(self, path)
    end

    def insert_image(path, alt: nil)
      @deck.insert_image(self, path, alt: alt)
    end

    def replace_table_cell(row:, column:, value:, table: 0)
      @deck.replace_table_cell(self, row: row, column: column, value: value, table: table)
    end

    def replace_code(text, block: 0)
      @deck.replace_code(self, text, block: block)
    end

    def owned_by?(deck) = @deck.equal?(deck)

    private

    def table_nodes = nodes.select { |node| node.type == :table }

    def valid_index!(index, name)
      raise TypeError, "#{name} index must be an Integer" unless index.is_a?(Integer)
      raise IndexError, "#{name} index must not be negative" if index.negative?

      index
    end

    def plain_text(node)
      case node.type
      when :text, :code_span then node.attributes.fetch(:text, "")
      when :image then node.attributes.fetch(:label, "")
      when :break, :softbreak then "\n"
      when :task_checkbox then ""
      when :code_block then code_block_text(node)
      when :html_block then node.attributes.fetch(:text, "")
      when :ordered_list, :list
        node.children.each_with_index.map { |item, index| list_item_text(item, index) }.join("\n")
      when :table
        node.children.map { |row| plain_text(row) }.join("\n")
      when :table_row
        node.children.map { |cell| plain_text(cell) }.join(" | ")
      when :block_quote
        node.children.map { |child| plain_text(child) }.join("\n")
      else node.children.map { |child| plain_text(child) }.join
      end
    end

    def list_item_text(node, index)
      marker = if node.attributes[:task]
        node.attributes[:checked] ? "☑ " : "☐ "
      elsif node.attributes[:ordered]
        "#{node.attributes[:start] || index + 1}. "
      else
        "• "
      end
      marker + node.children.map { |child| plain_text(child) }.reject(&:empty?).join("\n")
    end

    def code_block_text(node)
      lines = document.source.byteslice(node.range).to_s.scan(/.*?(?:\r\n|\r|\n|\z)/m).reject(&:empty?)
      if node.attributes[:fence]
        lines.shift
        lines.pop if node.attributes[:closed]
        lines.join
      else
        lines.map { |line| line.sub(/\A(?:    |\t)/, "") }.join
      end
    end
  end
end
