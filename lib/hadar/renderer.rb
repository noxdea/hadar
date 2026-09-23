# frozen_string_literal: true

module Hadar
  class Renderer
    def initialize
      @font_db = nil
      @fonts = {}
      @vocabulary = build_vocabulary
    end

    def describe(slide)
      raise TypeError, "slide must be a Hadar::Slide" unless slide.is_a?(Slide)

      children = Array(content_for(slide)).compact
      Zaniah::Describe::Node.new(:slide, {
        background: slide_theme(slide).colors.fetch("background"),
        margin: slide_theme(slide).spacing.fetch("margin"),
        gap: slide_theme(slide).spacing.fetch("gap")
      }, children, "slide-#{slide.index}")
    end

    def build(slide)
      Zaniah::Describe.build(describe(slide), vocabulary: @vocabulary,
        on_event: ->(_id, _payload) {})
    end

    def surface(slide)
      Zaniah::Describe::Surface.new(vocabulary: @vocabulary,
        on_event: ->(_id, _payload) {}).replace(describe(slide))
    end

    private

    def build_vocabulary
      db = self
      Zaniah::Describe::Vocabulary.build do
        node :slide, props: {background: :string, margin: :number, gap: :number} do |props, children|
          Zaniah::Element.new.flex_col.w_full.h_full.bg(props.fetch(:background))
            .p(props.fetch(:margin)).style(gap: props.fetch(:gap)).children(children)
        end
        node :stack, props: {gap: :number} do |props, children|
          Zaniah::Element.new.flex_col.style(gap: props.fetch(:gap)).children(children)
        end
        node :columns, props: {gap: :number} do |props, children|
          Zaniah::Element.new.flex_row.style(gap: props.fetch(:gap)).children(children)
        end
        node :text, props: {text: :string, size: :number, color: :string,
          family: :string}, children: :none do |props, _children|
          font = db.send(:font, props.fetch(:family))
          Zaniah::Text.new(props.fetch(:text), size: props.fetch(:size),
            color: props.fetch(:color), font: font, wrap: :word)
        end
        node :image, props: {path: :string}, children: :none do |props, _children|
          path = props.fetch(:path)
          begin
            Zaniah::Image.new(path).w_full
          rescue StandardError => error
            raise Error, "cannot render image #{path.inspect}: #{error.message}"
          end
        end
      end
    end

    def font(family)
      @fonts[family] ||= begin
        @font_db ||= Zaniah::TextSystem::FontDB.new
        @font_db.find(family: family == "sans-serif" ? nil : family)
      end
    end

    def content_for(slide)
      theme = slide_theme(slide)
      gap = theme.spacing.fetch("gap")
      case slide.layout
      when :title
        stack([
          text_node(slide.slot(:title).text, theme.font.fetch("title_size"), theme),
          text_node(slide.slot(:subtitle).text, theme.font.fetch("body_size"), theme, color: theme.colors.fetch("muted"))
        ].reject(&:nil?), gap)
      when :two_column
        heading = text_node(slide.slot(:title).text, theme.font.fetch("title_size"), theme)
        columns = node(:columns, {gap: gap}, [
          stack(text_nodes(slide.slot(:left).text, theme), gap),
          stack(text_nodes(slide.slot(:right).text, theme), gap)
        ])
        [heading, columns].compact
      when :image_text
        [text_node(slide.slot(:title).text, theme.font.fetch("title_size"), theme),
          *text_nodes(slide.slot(:text).text, theme),
          image_node(slide.slot(:image))].compact
      when :full_bleed_image
        [image_node(slide.slot(:image))].compact
      when :quote
        [*text_nodes(slide.slot(:quote).text, theme, size: theme.font.fetch("title_size")),
          *text_nodes(slide.slot(:attribution).text, theme, size: theme.font.fetch("body_size"), color: theme.colors.fetch("muted"))]
      when :code
        [text_node(slide.slot(:title).text, theme.font.fetch("title_size"), theme),
          *text_nodes(slide.slot(:code).text, theme, family: "monospace")].compact
      when :blank
        []
      else
        [text_node(slide.slot(:title).text, theme.font.fetch("title_size"), theme),
          *text_nodes(slide.slot(:body).text, theme)].compact
      end
    end

    def text_nodes(text, theme, size: theme.font.fetch("body_size"), color: theme.colors.fetch("text"), family: theme.font.fetch("family"))
      return [] if text.nil? || text.empty?

      text.split(/\n+/).reject(&:empty?).map do |part|
        text_node(part, size, theme, color: color, family: family)
      end
    end

    def text_node(text, size, theme, color: theme.colors.fetch("text"), family: theme.font.fetch("family"))
      return if text.nil? || text.empty?

      node(:text, {text: text, size: size, color: color, family: family}, [])
    end

    def stack(children, gap)
      node(:stack, {gap: gap}, children)
    end

    def node(type, props, children, key = nil)
      Zaniah::Describe::Node.new(type, props, children, key)
    end

    def image_node(slot)
      return if slot.empty?

      path = slot.resolved_image_path
      node(:image, {path: path}, [], "slide-#{slot.slide_index}-#{slot.name}-image")
    end

    def slide_theme(slide) = slide.theme
  end
end
