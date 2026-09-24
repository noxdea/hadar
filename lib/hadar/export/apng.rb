# frozen_string_literal: true

require "tempfile"

module Hadar
  module Export
    class APNG
      MAX_PIXELS = 32_000_000
      DEFAULT_DURATION_MS = 3_000

      def self.render(deck, renderer: Renderer.new, width: 1280, height: 720,
        duration_ms: DEFAULT_DURATION_MS, loop: 0)
        raise TypeError, "deck must be a Hadar::Deck" unless deck.is_a?(Deck)
        raise Error, "cannot export an empty deck" if deck.empty?
        raise TypeError, "renderer must respond to build" unless renderer.respond_to?(:build)
        unless [width, height].all? { |dimension| dimension.is_a?(Integer) && dimension.positive? } && width * height <= MAX_PIXELS
          raise ArgumentError, "APNG dimensions must be positive integers totaling at most #{MAX_PIXELS} pixels"
        end
        raise ArgumentError, "duration_ms must be a positive Integer" unless duration_ms.is_a?(Integer) && duration_ms.positive?
        if duration_ms / duration_ms.gcd(1_000) > 65_535
          raise ArgumentError, "duration_ms exceeds the APNG frame-delay limit"
        end
        raise ArgumentError, "loop must be a non-negative Integer" unless loop.is_a?(Integer) && loop >= 0

        animation = Wezen::Animation.new(width: width, height: height, loop: loop)
        window = Zaniah::Platform.open_window(backend: :headless, width: width, height: height)
        window.text_system = Zaniah::TextSystem::Renderer.new
        deck.slides.each do |slide|
          window.render(renderer.build(slide), clear: slide.theme.colors.fetch("background"))
          animation.add(window.device.pixels, delay_ms: duration_ms)
        end
        Wezen::APNG.encode(animation)
      ensure
        window&.close
      end

      def self.write(deck, path, overwrite: false, **options)
        raise TypeError, "path must be a String" unless path.is_a?(String)
        raise ArgumentError, "path must not be empty or contain NUL" if path.empty? || path.include?("\0")
        raise TypeError, "overwrite must be true or false" unless overwrite == true || overwrite == false

        target = File.expand_path(path)
        existing = begin
          File.lstat(target)
        rescue Errno::ENOENT
          nil
        end
        raise Error, "refusing to write through a symbolic link" if existing&.symlink?
        raise Error, "APNG target must be a regular file" if existing && !existing.file?
        raise Error, "APNG target already exists; pass overwrite: true to replace it" if existing && !overwrite

        bytes = render(deck, **options)
        mode = existing ? existing.mode & 0o777 : (0o666 & ~File.umask)
        Tempfile.create([".#{File.basename(target)}.", ".tmp"], File.dirname(target)) do |file|
          file.binmode
          file.write(bytes)
          file.flush
          file.chmod(mode)
          file.fsync
          file.close
          overwrite ? File.rename(file.path, target) : File.link(file.path, target)
        end
        path
      rescue SystemCallError => error
        raise Error, "cannot write APNG: #{error.message}"
      end
    end
  end
end
