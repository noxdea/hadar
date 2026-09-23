# frozen_string_literal: true

require "tempfile"
require "pathname"
require "uri"

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

    def replace_image(slot, path)
      validate_slot!(slot)
      unless slot.nodes.one? && slot.nodes.first.type == :image
        raise ArgumentError, "replace_image requires a slot containing exactly one image"
      end

      destination = image_destination(path)
      updated_document = Beid::Editing.set_attribute(document, slot.nodes.first, :destination, destination)
      update_image_document(slot, updated_document)
    end

    def insert_image(slot, path, alt: nil)
      validate_slot!(slot)
      raise ArgumentError, "insert_image requires an empty image slot" unless slot.empty?
      raise TypeError, "alt must be a String or nil" unless alt.nil? || alt.is_a?(String)
      raise ArgumentError, "alt must not contain newlines or NUL" if alt&.match?(/[\r\n\0]/)

      slide = self.slide(slot.slide_index)
      unless Layout.fetch(slide.layout).slots.include?(:image)
        raise Error, "image insertion requires an image layout slot"
      end
      anchor = slide.nodes.last
      raise Error, "image insertion requires a source node in the slide" unless anchor

      destination = image_destination(path)
      alt ||= File.basename(URI::DEFAULT_PARSER.unescape(destination))
      updated_document = Beid::Editing.insert_after(document, anchor, image_markdown(destination, alt))
      update_image_document(slot, updated_document)
    end

    def resolve_image_path(path)
      raise TypeError, "image path must be a String" unless path.is_a?(String)
      raise ArgumentError, "image path must not be empty or contain NUL" if path.empty? || path.include?("\0")

      if path.match?(/\Ahttps?:\/\//i)
        raise Error, "remote image URLs are not supported in slide preview: #{path}"
      end
      has_uri_scheme = path.match?(/\A[a-z][a-z0-9.+-]*:/i) && !path.match?(/\A[a-z]:[\\\/]/i)
      if has_uri_scheme
        raise Error, "image URI schemes are not supported in slide preview: #{path}"
      end

      directory = source_path ? File.dirname(source_path) : Dir.pwd
      resolved = File.realpath(File.expand_path(path, directory))
      raise Error, "image path is not a regular file: #{path}" unless File.file?(resolved)
      raise Error, "image file is not readable: #{path}" unless File.readable?(resolved)

      resolved
    rescue Errno::ENOENT, Errno::ENOTDIR
      raise Error, "image file not found: #{path}"
    rescue Errno::EACCES
      raise Error, "image file is not readable: #{path}"
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

    def image_destination(path)
      raise TypeError, "image path must be a String" unless path.is_a?(String)
      raise ArgumentError, "image path must not be empty or contain NUL/newlines" if path.empty? || path.match?(/[\0\r\n]/)

      path = relative_image_path(path) if Pathname.new(path).absolute?
      return path if path.match?(/\Ahttps?:\/\//i)

      URI::DEFAULT_PARSER.escape(path, /[^A-Za-z0-9\-._~\/]/)
    end

    def relative_image_path(path)
      raise Error, "absolute image paths require an opened deck" unless source_path

      absolute_path = Pathname.new(File.realpath(path))
      raise Error, "image path must be a regular file" unless absolute_path.file?

      absolute_path.relative_path_from(Pathname.new(File.dirname(source_path))).to_s
    rescue Errno::ENOENT
      raise Error, "image file does not exist"
    rescue ArgumentError => error
      raise Error, "image path cannot be made relative to the deck: #{error.message}"
    end

    def image_markdown(destination, alt)
      template = Beid::Document.parse("![image](placeholder)")
      image = first_image(template.root.children)
      template = Beid::Editing.set_attribute(template, image, :destination, destination)
      image = first_image(template.root.children)
      template = Beid::Editing.replace_text(template, image, alt)
      image = first_image(template.root.children)
      unless image && image.attributes.fetch(:destination) == destination
        raise Error, "image markup cannot be represented by Beid"
      end

      template.source
    end

    def first_image(nodes)
      nodes.each do |node|
        return node if node.type == :image

        nested = first_image(node.children)
        return nested if nested
      end
      nil
    end

    def update_image_document(slot, updated_document)
      updated_slides = build_slides(updated_document).freeze
      updated_slot = updated_slides.fetch(slot.slide_index).slot(slot.name)
      raise Error, "image edit did not produce an image node" if updated_slot.empty?

      @document, @slides = updated_document, updated_slides
      updated_slot
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
