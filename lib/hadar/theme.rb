# frozen_string_literal: true

module Hadar
  class Theme
    DEFAULTS = {
      "name" => "Minimal",
      "colors" => {"background" => "#ffffff", "text" => "#18212b", "muted" => "#5c6875", "accent" => "#315b7c"},
      "font" => {"family" => "sans-serif", "title_size" => 44, "body_size" => 26},
      "spacing" => {"margin" => 64, "gap" => 24}
    }.freeze
    COLOR_KEYS = %w[background text muted accent].freeze
    FONT_KEYS = %w[family title_size body_size].freeze
    SPACING_KEYS = %w[margin gap].freeze

    attr_reader :name, :colors, :font, :spacing

    def self.default = builtin("minimal")

    def self.builtin(name)
      key = name.to_s.downcase
      raise Error, "unknown built-in theme: #{name.inspect}" unless %w[minimal dark warm].include?(key)

      load(File.expand_path("../../assets/themes/#{key}.jsonc", __dir__))
    end

    def self.load(path)
      raise Error, "theme exceeds 256 KiB" if File.size(path) > 262_144

      document = Kochab.parse(File.read(path, encoding: "UTF-8"))
      raise Error, "invalid theme JSONC: #{document.errors.map(&:message).join('; ')}" unless document.valid?
      raise Error, "theme must be a JSON object" unless document.value.is_a?(Hash)

      new(document.value)
    rescue Kochab::ParseError, SystemCallError => error
      raise Error, error.message
    end

    def initialize(value)
      raise TypeError, "theme must be a Hash" unless value.is_a?(Hash)

      data = DEFAULTS.merge(value)
      reject_unknown!(data, DEFAULTS.keys, "theme")
      @name = data.fetch("name")
      raise Error, "theme name must be a non-empty String" unless @name.is_a?(String) && !@name.strip.empty?
      @name = @name.dup.freeze
      @colors = section(data, "colors", COLOR_KEYS)
      COLOR_KEYS.each do |key|
        color = @colors.fetch(key)
        raise Error, "invalid theme color #{key.inspect}" unless color.is_a?(String) && color.match?(/\A#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?\z/)
      end
      @font = section(data, "font", FONT_KEYS)
      raise Error, "font family must be a String" unless @font.fetch("family").is_a?(String) && !@font.fetch("family").empty?
      %w[title_size body_size].each do |key|
        value = @font.fetch(key)
        raise Error, "#{key} must be between 8 and 160" unless value.is_a?(Numeric) && value.finite? && value.between?(8, 160)
      end
      @spacing = section(data, "spacing", SPACING_KEYS)
      SPACING_KEYS.each do |key|
        value = @spacing.fetch(key)
        raise Error, "#{key} must be between 0 and 512" unless value.is_a?(Numeric) && value.finite? && value.between?(0, 512)
      end
      [@colors, @font, @spacing].each do |section|
        section.each { |key, value| section[key] = value.dup.freeze if value.is_a?(String) }
        section.freeze
      end
      freeze
    end

    private

    def section(data, key, allowed)
      value = data.fetch(key, {})
      raise Error, "#{key} must be a JSON object" unless value.is_a?(Hash)

      reject_unknown!(value, allowed, key)
      DEFAULTS.fetch(key).merge(value)
    end

    def reject_unknown!(hash, allowed, section)
      unknown = hash.keys - allowed
      raise Error, "unknown #{section} keys: #{unknown.join(', ')}" unless unknown.empty?
    end
  end
end
