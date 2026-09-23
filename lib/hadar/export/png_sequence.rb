# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Hadar
  module Export
    class PNGSequence
      MAX_PIXELS = 32_000_000

      def self.write(deck, directory, renderer: Renderer.new, width: 1280, height: 720)
        raise TypeError, "deck must be a Hadar::Deck" unless deck.is_a?(Deck)
        raise Error, "cannot export an empty deck" if deck.empty?
        raise TypeError, "renderer must respond to build" unless renderer.respond_to?(:build)
        raise ArgumentError, "directory must be a nonempty path" unless directory.is_a?(String) && !directory.empty?
        unless [width, height].all? { |dimension| dimension.is_a?(Integer) && dimension.positive? } && width * height <= MAX_PIXELS
          raise ArgumentError, "PNG dimensions must be positive integers totaling at most #{MAX_PIXELS} pixels"
        end

        output = File.expand_path(directory)
        FileUtils.mkdir_p(output)
        digits = [3, deck.length.to_s.length].max
        names = deck.length.times.map { |index| format("slide-%0#{digits}d.png", index + 1) }
        if (existing = names.find { |name| File.exist?(File.join(output, name)) || File.symlink?(File.join(output, name)) })
          raise Error, "PNG sequence output already exists: #{existing}"
        end

        Dir.mktmpdir(".hadar-png-", output) do |staging|
          write_frames(deck, renderer, width, height, staging, names)
          commit_frames(output, staging, names)
        end
        names.map { |name| File.join(output, name) }.freeze
      rescue SystemCallError => error
        raise Error, "cannot write PNG sequence: #{error.message}"
      end

      def self.write_frames(deck, renderer, width, height, staging, names)
        window = Zaniah::Platform.open_window(backend: :headless, width: width, height: height)
        window.text_system = Zaniah::TextSystem::Renderer.new
        deck.slides.each_with_index do |slide, index|
          window.render(renderer.build(slide), clear: slide.theme.colors.fetch("background"))
          window.write_png(File.join(staging, names[index]))
        end
      ensure
        window&.close
      end
      private_class_method :write_frames

      def self.commit_frames(output, staging, names)
        created = []
        names.each do |name|
          target = File.join(output, name)
          File.link(File.join(staging, name), target)
          created << target
        end
      rescue SystemCallError
        created.each { |path| File.unlink(path) if File.file?(path) }
        raise
      end
      private_class_method :commit_frames
    end
  end
end
