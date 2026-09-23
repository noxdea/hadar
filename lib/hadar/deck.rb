# frozen_string_literal: true

require "tempfile"

module Hadar
  class Deck
    attr_reader :document, :slides, :theme, :source_path

    def self.parse(markdown, theme: nil)
      document = Beid::Document.parse(markdown)
      theme ||= theme_from_front_matter(document, Dir.pwd)
      from_document(document, theme: theme)
    end

    def self.open(path, theme: nil)
      source_path = File.realpath(path)
      raise Error, "deck path must be a regular file" unless File.file?(source_path)

      document = Beid::Document.parse(File.read(source_path, encoding: "UTF-8"))
      theme ||= theme_from_front_matter(document, File.dirname(source_path))
      new(document, theme: theme, source_path: source_path)
    end

    def self.from_document(document, theme: nil)
      raise TypeError, "document must be a Beid::Document" unless document.is_a?(Beid::Document)

      theme ||= theme_from_front_matter(document, Dir.pwd)
      new(document, theme: theme)
    end

    def initialize(document, theme: nil, source_path: nil)
      @document = document
      @theme = theme || Theme.default
      if @theme.is_a?(String)
        @theme = %w[minimal dark warm].include?(@theme.downcase) ? Theme.builtin(@theme) : Theme.load(@theme)
      end
      raise TypeError, "theme must be a Hadar::Theme" unless @theme.is_a?(Theme)
      @source_path = source_path
      @saved_source = source_path && document.source.dup.freeze
      @slides = build_slides(document).freeze
    end

    def slide(index) = slides.fetch(index)
    def length = slides.length
    alias size length
    def empty? = slides.empty?

    def replace_text(slot, text)
      validate_slot!(slot)
      raise ArgumentError, "replace_text requires a slot containing exactly one node" unless slot.nodes.one?

      updated_document = Beid::Editing.replace_text(document, slot.nodes.first, text)
      updated_slides = build_slides(updated_document).freeze
      @document, @slides = updated_document, updated_slides
      slide(slot.slide_index).slot(slot.name)
    end

    def replace_rich_text(slot, value)
      validate_slot!(slot)
      raise TypeError, "value must be a Zaniah::UI::RichText" unless value.is_a?(Zaniah::UI::RichText)
      raise Error, "rich text must be editable" unless value.editable?

      updated_document = RichTextProjection.new(slot).replace(value)
      return slot if updated_document.equal?(document)

      updated_slides = build_slides(updated_document).freeze
      updated_slot = updated_slides.fetch(slot.slide_index).slot(slot.name)
      projected = RichTextProjection.new(updated_slot).build(editable: false)
      unless updated_slot.text == value.text && projected.runs == value.runs
        raise Error, "rich text edit cannot be represented without changing untouched Markdown"
      end

      @document, @slides = updated_document, updated_slides
      slide(slot.slide_index).slot(slot.name)
    end

    def save(path = source_path, overwrite: false)
      raise Error, "no save path; open a file or pass a path" unless path
      raise TypeError, "save path must be a String" unless path.is_a?(String)
      raise TypeError, "overwrite must be true or false" unless overwrite == true || overwrite == false
      raise ArgumentError, "save path must not be empty or contain NUL" if path.empty? || path.include?("\0")

      target = File.expand_path(path)
      same_source = source_path && target == source_path
      write_atomically(target, overwrite: overwrite, check_source: same_source && !overwrite)
      @source_path = target
      @saved_source = document.source.dup.freeze
      self
    end

    private

    def validate_slot!(slot)
      raise TypeError, "slot must be a Hadar::Slot" unless slot.is_a?(Slot)
      raise Error, "slot belongs to another deck" unless slot.owned_by?(self)
      raise Error, "slot is stale; retrieve it again from the current deck" unless slot.document.equal?(document)
    end

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

    def build_slides(source_document)
      groups = [[]]
      source_document.root.children.each do |node|
        if node.type == :thematic_break
          groups << []
        else
          groups.last << node
        end
      end
      groups.reject!(&:empty?)
      groups = [[]] if groups.empty? && source_document.source.strip.empty?
      groups.each_with_index.map do |nodes, index|
        requested = nodes.filter_map do |node|
          node.attributes.dig(:values, "layout") if node.type == :directive
        end.first
        Slide.new(index: index, document: source_document, nodes: nodes, layout: requested,
          theme: theme, deck: self)
      end
    end

    def write_atomically(target, overwrite:, check_source:)
      existing = lstat(target)
      raise Error, "refusing to write through a symbolic link" if existing&.symlink?
      raise Error, "save target must be a regular file" if existing && !existing.file?
      if check_source
        verify_unchanged!(target)
      elsif existing && !overwrite
        raise Error, "save target already exists; pass overwrite: true to replace it"
      end

      mode = existing ? existing.mode & 0o777 : (0o666 & ~File.umask)
      directory = File.dirname(target)
      basename = File.basename(target)
      Tempfile.create([".#{basename}.", ".tmp"], directory) do |file|
        file.binmode
        file.write(document.source.b)
        file.flush
        file.chmod(mode)
        file.fsync
        file.close
        verify_unchanged!(target) if check_source
        File.rename(file.path, target)
      end
    end

    def verify_unchanged!(target)
      existing = lstat(target)
      raise Error, "deck file disappeared since it was opened" unless existing&.file? && !existing.symlink?
      return if File.binread(target) == @saved_source.b

      raise Error, "deck file changed since it was opened; refusing to overwrite external edits"
    end

    def lstat(path)
      File.lstat(path)
    rescue Errno::ENOENT
      nil
    end
  end
end
