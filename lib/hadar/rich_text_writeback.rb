# frozen_string_literal: true

module Hadar
  class RichTextWriteback
    def initialize(projection, value)
      @document, @text, @segments = projection.document, projection.text, projection.segments
      @value = value
    end

    def replace
      value = @value
      raise Error, "rich text paragraph styles cannot be written to Markdown" if value.paragraph_styles.any? { |style| !style.empty? }

      change = diff(value.text)
      if change[:first] == change[:last] && change[:inserted].empty?
        style = style_change(value)
        return @document unless style
        return apply_style_change(style)
      end

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
