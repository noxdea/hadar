# frozen_string_literal: true

module Hadar
  module Layout
    Definition = Data.define(:name, :slots)

    DEFINITIONS = [
      Definition.new(:title, %i[title subtitle]),
      Definition.new(:title_body, %i[title body]),
      Definition.new(:two_column, %i[title left right]),
      Definition.new(:image_text, %i[title text image]),
      Definition.new(:full_bleed_image, %i[image]),
      Definition.new(:quote, %i[quote attribution]),
      Definition.new(:code, %i[title code]),
      Definition.new(:blank, []),
      Definition.new(:freeform, [])
    ].freeze
    private_constant :Definition

    NAMES = DEFINITIONS.map(&:name).freeze
    ALIASES = {
      "title+body" => :title_body,
      "title-body" => :title_body,
      "two-column" => :two_column,
      "image+text" => :image_text,
      "image-text" => :image_text,
      "full-bleed-image" => :full_bleed_image
    }.freeze

    def self.fetch(name)
      normalized = normalize(name)
      DEFINITIONS.find { |definition| definition.name == normalized } ||
        raise(ArgumentError, "unknown slide layout: #{name.inspect}")
    end

    def self.select(nodes, requested: nil)
      return fetch(requested).name if requested && !requested.to_s.empty?

      types = nodes.map(&:type)
      div_names = nodes.select { |node| node.type == :directive && node.attributes[:kind] == :div }
        .map { |node| node.attributes[:name] }
      return :two_column if div_names.include?("left") || div_names.include?("right")
      return :quote if types.include?(:block_quote)
      return :code if types.include?(:code_block) && (types - %i[heading code_block]).empty?

      images = nodes.any? { |node| contains_type?(node, :image) }
      text = nodes.any? { |node| text?(node) }
      return :image_text if images && text
      return :full_bleed_image if images
      return :blank if nodes.empty?

      headings = nodes.count { |node| node.type == :heading }
      return :title if headings.between?(1, 2) && nodes.all? { |node| node.type == :heading }

      :title_body
    end

    def self.normalize(name)
      key = name.to_s.strip.downcase
      ALIASES.fetch(key) { key.tr("-", "_").to_sym }
    end
    private_class_method :normalize

    def self.contains_type?(node, type)
      node.type == type || node.children.any? { |child| contains_type?(child, type) }
    end
    private_class_method :contains_type?

    def self.text?(node)
      return false if node.type == :image
      if node.type == :text
        text = node.attributes.fetch(:text, "")
        return !text.strip.empty?
      end
      return true if %i[code_block html_block].include?(node.type)

      node.children.any? { |child| text?(child) }
    end
    private_class_method :text?
  end
end
