# frozen_string_literal: true

module Hadar
  class RichTextWriteback
    def initialize(projection, value)
      @projection, @document, @text, @segments = projection, projection.document, projection.text, projection.segments
      @value = value
    end

    def replace
      value = @value
      change = diff(value.text)
      level_changes = paragraph_level_changes(value, change)
      if change[:first] == change[:last] && change[:inserted].empty?
        raise Error, "edit one list item level at a time" if level_changes.length > 1
        return apply_list_level_change(level_changes.first) unless level_changes.empty?

        style = style_change(value)
        return @document unless style
        return apply_style_change(style)
      end
      raise Error, "list levels cannot be changed together with text" unless level_changes.empty?

      segment = editable_segment(change[:first], change[:last])
      validate_styles!(value, change, segment)
      local_first = change[:first] - segment.start
      local_last = change[:last] - segment.start
      replacement = segment.text.byteslice(0...local_first).to_s + change[:inserted] +
        segment.text.byteslice(local_last..).to_s

      case segment.node.type
      when :text
        source_text = @document.source.byteslice(segment.node.range)
        raise Error, "escaped Markdown text cannot be edited through rich text yet" unless source_text == segment.text

        first = segment.node.range.begin + local_first
        last = segment.node.range.begin + local_last
        Beid::Editing.edit_range(@document, segment.node, first...last, change[:inserted])
      when :code_span
        Beid::Editing.replace_text(@document, segment.node, replacement)
      when :image
        range = segment.node.attributes.fetch(:label_range)
        source_text = @document.source.byteslice(range)
        raise Error, "escaped image labels cannot be edited through rich text yet" unless source_text == segment.text

        first = range.begin + local_first
        last = range.begin + local_last
        Beid::Editing.edit_range(@document, segment.node, first...last, change[:inserted])
      else
        raise Error, "rich text edit crosses Markdown structure"
      end
    end

    private

    def paragraph_level_changes(value, change)
      if change[:first] != change[:last] || !change[:inserted].empty?
        first_line = @text.byteslice(0...change[:first]).to_s.count("\n")
        last_line = @text.byteslice(0...change[:last]).to_s.count("\n")
        inherited = @projection.paragraph_styles.fetch(first_line, {})
        expected = @projection.paragraph_styles.take(first_line) +
          Array.new(change[:inserted].count("\n") + 1) { inherited } +
          @projection.paragraph_styles.drop(last_line + 1)
        raise Error, "list levels cannot be changed together with text" unless value.paragraph_styles == expected

        return []
      end

      line_starts = [0]
      @text.b.each_byte.with_index { |byte, index| line_starts << index + 1 if byte == 10 }
      changes = {}
      value.paragraph_styles.each_with_index do |style, index|
        raise Error, "only list levels can be written as paragraph styles" unless (style.keys - [:level]).empty?

        offset = line_starts.fetch(index, @text.bytesize)
        segment = @segments.find do |candidate|
          candidate.list_item && candidate.start <= offset && offset < candidate.finish
        end
        if segment
          current = style[:level]
          next if current == segment.list_level
          raise Error, "list level must be a nonnegative integer" unless current.is_a?(Integer) && current >= 0

          key = segment.list_item.object_id
          change = {item: segment.list_item, level: current}
          if changes.key?(key) && changes[key][:level] != current
            raise Error, "one list item cannot have multiple levels"
          end
          changes[key] = change
        elsif style.key?(:level)
          raise Error, "list level can only be changed on an existing list item"
        end
      end
      changes.values
    end

    def apply_list_level_change(change)
      item = change.fetch(:item)
      context = @projection.list_context.fetch(item.object_id)
      current_level = context.fetch(:level)
      target_level = change.fetch(:level)
      unless (target_level - current_level).abs == 1
        raise Error, "change list level one step at a time"
      end

      source = @document.source.b
      line_start = physical_line_start(source, item.range.begin)
      item_range = line_start...item.range.end
      prefix = source.byteslice(line_start...item.range.begin).to_s
      raise Error, "list item indentation is not whitespace" unless prefix.match?(/\A[ \t]*\z/)

      target_indent = if target_level > current_level
        previous = context[:previous] || raise(Error, "a list item needs a previous sibling before it can be indented")
        list_item_content_indent(source, previous)
      else
        parent = context[:parent] || raise(Error, "a top-level list item cannot be outdented")
        parent_start = physical_line_start(source, parent.range.begin)
        indentation_columns(source.byteslice(parent_start...parent.range.begin).to_s)
      end
      target_parent_line = if target_level > current_level
        source_line(context.fetch(:previous).range.begin, source)
      else
        parent_context = @projection.list_context.fetch(context.fetch(:parent).object_id)
        parent_context[:parent] && source_line(parent_context[:parent].range.begin, source)
      end
      delta = target_indent - indentation_columns(prefix)
      raise Error, "list level change has no source indentation change" if delta.zero?

      replacement = shift_list_item(source.byteslice(item_range).to_s, delta)
      updated = Beid::Editing.edit_range(@document, context.fetch(:list), item_range, replacement)
      new_prefix = replacement[/\A[ \t]*/].to_s
      updated_item, actual_level = find_list_item(updated.root, line_start + new_prefix.bytesize)
      unless updated_item && actual_level == target_level && updated_item.marker == item.marker
        raise Error, "list level change could not be represented without changing Markdown structure"
      end
      unless list_item_structure(updated.root, updated.source) ==
          expected_list_item_structure(item, line_start, item_range.end, target_level - current_level, target_parent_line)
        raise Error, "list level change would alter a neighboring list item"
      end

      updated
    end

    def physical_line_start(source, offset)
      newline = source.rindex("\n".b, offset - 1)
      newline ? newline + 1 : 0
    end

    def source_line(offset, source)
      source.byteslice(0...offset).count("\n")
    end

    def list_item_content_indent(source, item)
      line_start = physical_line_start(source, item.range.begin)
      line_end = source.index("\n".b, item.range.begin) || source.bytesize
      line = source.byteslice(line_start...line_end).to_s
      marker = /\A[ \t]*(?:[-+*]|\d{1,9}[.)])[ \t]+/.match(line)
      raise Error, "list item marker cannot be indented safely" unless marker

      indentation_columns(marker[0])
    end

    def indentation_columns(prefix)
      prefix.each_char.reduce(0) { |column, character| character == "\t" ? (column / 4 + 1) * 4 : column + 1 }
    end

    def shift_list_item(text, delta)
      text.each_line.map do |line|
        body = line.sub(/(?:\r\n|\r|\n)\z/, "")
        next line if body.match?(/\A[ \t]*\z/)
        next (" " * delta) + line if delta.positive?

        remove_indent(line, -delta)
      end.join
    end

    def remove_indent(line, columns)
      prefix = line[/\A[ \t]*/].to_s
      removed_columns = 0
      removed_bytes = 0
      prefix.each_char do |character|
        width = character == "\t" ? (removed_columns / 4 + 1) * 4 - removed_columns : 1
        raise Error, "list item indentation cannot be removed evenly" if removed_columns + width > columns

        removed_columns += width
        removed_bytes += character.bytesize
        break if removed_columns == columns
      end
      raise Error, "list item has a continuation line with insufficient indentation" unless removed_columns == columns

      line.byteslice(removed_bytes..).to_s
    end

    def find_list_item(node, offset, level = 0)
      if %i[list ordered_list].include?(node.type)
        node.children.each do |item|
          return [item, level] if item.type == :list_item && item.range.begin == offset

          item.children.each do |child|
            found = find_list_item(child, offset, level + 1)
            return found if found
          end
        end
      else
        node.children.each do |child|
          found = find_list_item(child, offset, level)
          return found if found
        end
      end
      nil
    end

    def list_item_structure(root, source)
      items = {}
      collect_list_item_structure(root, source, 0, nil, items)
      items.transform_values { |entry| {level: entry[:level], parent: entry[:parent]} }
    end

    def expected_list_item_structure(item, line_start, item_end, level_delta, target_parent_line)
      source = @document.source.b
      original = {}
      collect_list_item_structure(@document.root, source, 0, nil, original)
      selected_line = source_line(item.range.begin, source)
      original.to_h do |line, entry|
        inside_item = entry[:offset] >= line_start && entry[:offset] < item_end
        expected = {level: entry[:level] + (inside_item ? level_delta : 0), parent: entry[:parent]}
        expected[:parent] = target_parent_line if line == selected_line
        [line, expected]
      end.tap do |depths|
        raise Error, "list item is not part of its projected source" unless depths.key?(selected_line)
      end
    end

    def collect_list_item_structure(node, source, level, parent_line, items)
      if %i[list ordered_list].include?(node.type)
        node.children.each do |item|
          line = source_line(item.range.begin, source)
          items[line] = {level: level, parent: parent_line, offset: item.range.begin}
          item.children.each { |child| collect_list_item_structure(child, source, level + 1, line, items) }
        end
      else
        node.children.each { |child| collect_list_item_structure(child, source, level, parent_line, items) }
      end
    end

    def diff(value)
      raise ArgumentError, "rich text must be valid UTF-8" unless value.is_a?(String) && value.valid_encoding?

      old_clusters, new_clusters = @text.scan(/\X/), value.scan(/\X/)
      prefix = 0
      prefix += 1 while prefix < old_clusters.length && prefix < new_clusters.length &&
        old_clusters[prefix] == new_clusters[prefix]
      suffix = 0
      suffix += 1 while suffix < old_clusters.length - prefix && suffix < new_clusters.length - prefix &&
        old_clusters[-suffix - 1] == new_clusters[-suffix - 1]
      first = old_clusters.take(prefix).sum(&:bytesize)
      last = old_clusters.take(old_clusters.length - suffix).sum(&:bytesize)
      inserted_finish = new_clusters.take(new_clusters.length - suffix).sum(&:bytesize)
      {first: first, last: last, inserted: value.byteslice(first...inserted_finish).to_s,
        old_clusters: old_clusters, new_clusters: new_clusters, prefix: prefix, suffix: suffix}
    end

    def editable_segment(first, last)
      candidates = @segments.select do |segment|
        segment.node && if first == last
          segment.start < first && first <= segment.finish
        else
          segment.start <= first && last <= segment.finish
        end
      end
      candidates = @segments.select { |segment| segment.node && segment.start <= first && first < segment.finish } if candidates.empty? && first == last
      segment = candidates.first
      raise Error, "rich text edit must stay within one Markdown text run" unless segment
      unless %i[text code_span image].include?(segment.node.type)
        raise Error, "rich text edit crosses Markdown structure"
      end

      segment
    end

    def style_change(value)
      clusters = @text.scan(/\X/)
      changes = []
      clusters.each_with_index do |cluster, index|
        offset = cluster_offset(clusters, index)
        original = old_style_at(offset)
        current = rich_style_at(value, offset)
        delta = (original.keys | current.keys).each_with_object({}) do |key, result|
          result[key] = [original[key], current[key]] unless original[key] == current[key]
        end
        next if delta.empty?

        finish = offset + cluster.bytesize
        if changes.last && changes.last[:finish] == offset && changes.last[:delta] == delta
          changes.last[:finish] = finish
        else
          changes << {first: offset, finish: finish, delta: delta}
        end
      end
      return if changes.empty?
      raise Error, "rich text style changes must target one source run" unless changes.one?

      changes.first
    end

    def apply_style_change(change)
      segment = editable_segment(change[:first], change[:finish])
      raise Error, "only Markdown text runs can be restyled" unless segment.node.type == :text
      source_text = @document.source.byteslice(segment.node.range)
      raise Error, "escaped Markdown text cannot be restyled through rich text yet" unless source_text == segment.text

      formats = change[:delta]
      raise Error, "only bold and italic styles can be written to Markdown" unless (formats.keys - %i[bold italic]).empty?
      additions = formats.select { |_key, (old, new)| new == true && old != true }.keys
      removals = formats.select { |_key, (old, new)| old == true && new.nil? }.keys
      raise Error, "rich text style changes cannot be represented by Markdown" unless additions.length + removals.length == formats.length
      raise Error, "combine only one Markdown style change at a time" if additions.any? && removals.any?

      if additions.any?
        first = segment.node.range.begin + change[:first] - segment.start
        last = segment.node.range.begin + change[:finish] - segment.start
        selected = source_text.byteslice((first - segment.node.range.begin)...(last - segment.node.range.begin))
        opening = (additions.include?(:bold) ? "**" : "") + (additions.include?(:italic) ? "_" : "")
        closing = (additions.include?(:italic) ? "_" : "") + (additions.include?(:bold) ? "**" : "")
        return Beid::Editing.edit_range(@document, segment.node, first...last, opening + selected + closing)
      end

      raise Error, "remove one Markdown style at a time" unless removals.one?
      key = removals.first
      wrapper = segment.wrappers.reverse.find do |style, node|
        style == key && node.children == [segment.node] &&
          segment.start == change[:first] && segment.finish == change[:finish]
      end&.last
      raise Error, "removing a style requires selecting its complete Markdown run" unless wrapper

      marker_size = wrapper.marker.bytesize
      inner = @document.source.byteslice((wrapper.range.begin + marker_size)...(wrapper.range.end - marker_size))
      Beid::Editing.edit_range(@document, wrapper, wrapper.range, inner)
    end

    def rich_style_at(value, offset)
      value.spans.find { |span| offset >= span.start && offset < span.finish }&.style || {}
    end

    def validate_styles!(value, change, segment)
      old_clusters = change[:old_clusters]
      new_clusters = change[:new_clusters]
      old_end = old_clusters.length - change[:suffix]
      new_end = new_clusters.length - change[:suffix]
      change[:prefix].times do |index|
        check_style!(value, new_clusters, index, old_style_at(cluster_offset(old_clusters, index)))
      end
      change[:suffix].times do |index|
        old_index = old_end + index
        new_index = new_end + index
        check_style!(value, new_clusters, new_index, old_style_at(cluster_offset(old_clusters, old_index)))
      end
      (change[:prefix]...new_end).each do |index|
        check_style!(value, new_clusters, index, segment.style)
      end
    end

    def check_style!(value, clusters, index, expected)
      offset = cluster_offset(clusters, index)
      actual = rich_style_at(value, offset)
      raise Error, "rich-text style changes cannot yet be written back to Markdown" unless actual == expected
    end

    def old_style_at(offset)
      @segments.find { |segment| offset >= segment.start && offset < segment.finish }&.style || {}
    end

    def cluster_offset(clusters, index)
      clusters.take(index).sum(&:bytesize)
    end
  end
end
