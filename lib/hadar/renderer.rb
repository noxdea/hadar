# frozen_string_literal: true

module Hadar
  class Renderer
    def initialize(font: nil)
      @font_db = nil
      @fonts = {}
      @font_override = font
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
        node :placed, props: {x: :number, y: :number, width: :number, height: :number} do |props, children|
          Zaniah::Element.new.flex_col.style(position: :absolute,
            left: Zaniah.percent(props.fetch(:x)), top: Zaniah.percent(props.fetch(:y)),
            width: Zaniah.percent(props.fetch(:width)), height: Zaniah.percent(props.fetch(:height)))
            .children(children)
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
        node :table, props: {rows: :array, alignments: :array, size: :number,
          family: :string, text_color: :string, header_color: :string, border_color: :string}, children: :none do |props, _children|
          rows = props.fetch(:rows).each_with_index.map do |row, row_index|
            cells = row.each_with_index.map do |value, column|
              alignment = {left: :start, center: :center, right: :end}[props.fetch(:alignments)[column]] || :start
              color = row_index.zero? ? props.fetch(:header_color) : props.fetch(:text_color)
              Zaniah::Text.new(value, size: props.fetch(:size), color: color,
                font: db.send(:font, props.fetch(:family)), wrap: :word, align: alignment)
                .flex_1.p(6).border(1).border_color(props.fetch(:border_color))
            end
            Zaniah::Element.new.flex_row.w_full.children(cells)
          end
          Zaniah::Element.new.flex_col.w_full.children(rows)
        end
        node :code_block, props: {language: :string} do |_props, children|
          Zaniah::Element.new.flex_col.w_full.children(children)
        end
        node :code_line, props: {} do |_props, children|
          Zaniah::Element.new.flex_row.children(children)
        end
        node :code_token, props: {text: :string, color: :string, size: :number}, children: :none do |props, _children|
          Zaniah::Text.new(props.fetch(:text), size: props.fetch(:size), color: props.fetch(:color),
            font: db.send(:font, "monospace"), wrap: :none)
        end
      end
    end

    def font(family)
      return @font_override if @font_override

      @fonts[family] ||= begin
        @font_db ||= Zaniah::TextSystem::FontDB.new
        @font_db.find(family: family == "sans-serif" ? nil : family)
      end
    end

    def content_for(slide)
      theme = slide_theme(slide)
      gap = theme.spacing.fetch("gap")
      case slide.layout
      when :freeform
        slide.placements.map do |name, (x, y, width, height)|
          slot = slide.slot(name)
          entry = slot.nodes.first
          children = if entry.type == :image
            [image_node(slot)]
          elsif entry.type == :heading
            [text_node(slot.text, theme.font.fetch("title_size"), theme),
              *images_in(entry).map { |image| image_node(slot, image: image) }]
          else
            [*render_blocks(slot, theme), *images_in(entry).map { |image| image_node(slot, image: image) }]
          end
          node(:placed, {x: x, y: y, width: width, height: height}, children.compact,
            "slide-#{slide.index}-#{name}")
        end
      when :title
        stack([
          text_node(slide.slot(:title).text, theme.font.fetch("title_size"), theme),
          text_node(slide.slot(:subtitle).text, theme.font.fetch("body_size"), theme, color: theme.colors.fetch("muted"))
        ].reject(&:nil?), gap)
      when :two_column
        heading = text_node(slide.slot(:title).text, theme.font.fetch("title_size"), theme)
        columns = node(:columns, {gap: gap}, [
          stack(render_blocks(slide.slot(:left), theme), gap),
          stack(render_blocks(slide.slot(:right), theme), gap)
        ])
        [heading, columns].compact
      when :image_text
        [text_node(slide.slot(:title).text, theme.font.fetch("title_size"), theme),
          *render_blocks(slide.slot(:text), theme),
          image_node(slide.slot(:image))].compact
      when :full_bleed_image
        [image_node(slide.slot(:image))].compact
      when :quote
        [*text_nodes(slide.slot(:quote).text, theme, size: theme.font.fetch("title_size")),
          *text_nodes(slide.slot(:attribution).text, theme, size: theme.font.fetch("body_size"), color: theme.colors.fetch("muted"))]
      when :code
        [text_node(slide.slot(:title).text, theme.font.fetch("title_size"), theme),
          *render_blocks(slide.slot(:code), theme)].compact
      when :blank
        []
      else
        [text_node(slide.slot(:title).text, theme.font.fetch("title_size"), theme),
          *render_blocks(slide.slot(:body), theme)].compact
      end
    end

    def render_blocks(slot, theme)
      table_index = code_index = 0
      slot.nodes.flat_map do |source_node|
        case source_node.type
        when :table
          result = table_node(slot, source_node, table_index, theme)
          table_index += 1
          [result]
        when :code_block
          result = code_node(slot, source_node, code_index, theme)
          code_index += 1
          [result]
        else
          text_nodes(slot.text_for(source_node), theme)
        end
      end
    end

    def table_node(slot, source_node, index, theme)
      node(:table, {
        rows: slot.table_rows(table: index),
        alignments: source_node.attributes.fetch(:alignments, []),
        size: theme.font.fetch("body_size"),
        family: theme.font.fetch("family"),
        text_color: theme.colors.fetch("text"),
        header_color: theme.colors.fetch("accent"),
        border_color: theme.colors.fetch("muted")
      }, [], "slide-#{slot.slide_index}-table-#{index}")
    end

    def code_node(slot, source_node, index, theme)
      source = slot.text_for(source_node)
      language = source_node.attributes.fetch(:info, "").split.first.to_s
      lines = source.scan(/.*?(?:\r\n|\r|\n|\z)/m).reject(&:empty?)
      lines = [""] if lines.empty?
      lexer = language.empty? ? nil : Rouge::Lexer.find(language)
      rows = code_tokens(lines, lexer)
      line_nodes = rows.each_with_index.map do |tokens, line_index|
        line = lines.fetch(line_index)
        body = line.sub(/\r\n\z|\r\z|\n\z/, "")
        visible_bytes = body.bytesize
        offset = 0
        token_nodes = tokens.filter_map do |kind, text|
          size = [text.bytesize, visible_bytes - offset].min
          offset += text.bytesize
          next if size <= 0

          node(:code_token, {text: text.byteslice(0, size), color: token_color(kind, theme),
            size: theme.font.fetch("body_size")}, [])
        end
        token_nodes << node(:code_token, {text: " ", color: theme.colors.fetch("text"),
          size: theme.font.fetch("body_size")}, []) if token_nodes.empty?
        node(:code_line, {}, token_nodes, "line-#{line_index}")
      end
      node(:code_block, {language: language}, line_nodes, "slide-#{slot.slide_index}-code-#{index}")
    end

    def code_tokens(lines, lexer)
      return lines.map { |line| [[nil, line]] } unless lexer

      lexer_lines = lines.map do |line|
        line.match?(/(?:\r\n|\r|\n)\z/) ? line.sub(/\r\n\z|\r\z|\n\z/, "\n") : line
      end
      highlighter = Antares::Highlighter.new(lexer: lexer.new,
        lines: ->(index) { lexer_lines.fetch(index) }, line_count: -> { lexer_lines.length })
      lexer_lines.each_index.map { |index| highlighter.tokens_for(index) }
    end

    def token_color(kind, theme)
      name = kind&.qualname.to_s
      return theme.colors.fetch("muted") if name.start_with?("Comment")
      return theme.colors.fetch("accent") if name.start_with?("Keyword", "Literal.Number", "Literal.String", "Name.Builtin")

      theme.colors.fetch("text")
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

    def images_in(entry)
      [entry, *entry.children.flat_map { |child| images_in(child) }].select { |node| node.type == :image }
    end

    def image_node(slot, image: nil)
      return if slot.empty?

      path = image ? slot.resolved_image_path_for(image) : slot.resolved_image_path
      node(:image, {path: path}, [], "slide-#{slot.slide_index}-#{slot.name}-image")
    end

    def slide_theme(slide) = slide.theme
  end
end
