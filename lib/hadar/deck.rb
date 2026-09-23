# frozen_string_literal: true

module Hadar
  class Deck
    attr_reader :document, :slides, :theme

    def self.parse(markdown, theme: nil)
      document = Beid::Document.parse(markdown)
      theme ||= theme_from_front_matter(document, Dir.pwd)
      from_document(document, theme: theme)
    end

    def self.open(path, theme: nil)
      document = Beid::Document.parse(File.read(path))
      theme ||= theme_from_front_matter(document, File.dirname(File.expand_path(path)))
      from_document(document, theme: theme)
    end

    def self.from_document(document, theme: nil)
      raise TypeError, "document must be a Beid::Document" unless document.is_a?(Beid::Document)

      theme ||= theme_from_front_matter(document, Dir.pwd)
      new(document, theme: theme)
    end

    def initialize(document, theme: nil)
      @document = document
      @theme = theme || Theme.default
      if @theme.is_a?(String)
        @theme = %w[minimal dark warm].include?(@theme.downcase) ? Theme.builtin(@theme) : Theme.load(@theme)
      end
      raise TypeError, "theme must be a Hadar::Theme" unless @theme.is_a?(Theme)
      @slides = build_slides.freeze
      freeze
    end

    def slide(index) = slides.fetch(index)
    def length = slides.length
    alias size length
    def empty? = slides.empty?

    private

    def self.theme_from_front_matter(document, directory)
      return unless document.front_matter

      match = document.front_matter.match(/^theme:\s*["']?([^\r\n"']+)["']?\s*$/)
      return unless match

      name = match[1].strip
      return Theme.builtin(name) if %w[minimal dark warm].include?(name.downcase)

      path = File.expand_path(name, directory)
      return unless File.file?(path)

      Theme.load(path)
    end
    private_class_method :theme_from_front_matter

    def build_slides
      groups = [[]]
      document.root.children.each do |node|
        if node.type == :thematic_break
          groups << []
        else
          groups.last << node
        end
      end
      groups.reject!(&:empty?)
      groups = [[]] if groups.empty? && document.source.strip.empty?
      groups.each_with_index.map do |nodes, index|
        requested = nodes.filter_map do |node|
          node.attributes.dig(:values, "layout") if node.type == :directive
        end.first
        Slide.new(index: index, document: document, nodes: nodes, layout: requested, theme: theme)
      end
    end
  end
end
