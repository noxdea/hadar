# frozen_string_literal: true

module Hadar
  class DeckWatcher
    attr_reader :deck

    def initialize(deck, latency: 0.05, on_reload: nil)
      raise TypeError, "deck must be a Hadar::Deck" unless deck.is_a?(Deck)
      raise Error, "file watching requires a deck opened from a path" unless deck.source_path
      raise TypeError, "on_reload must be callable" if on_reload && !on_reload.respond_to?(:call)

      @deck, @on_reload, @closed = deck, on_reload, false
      @watcher = Zaniah::Platform.watch(deck.source_path, latency: latency)
    end

    def poll(timeout: 0)
      return false if @closed

      @watcher.poll(timeout: timeout)
      return false unless deck.reload_if_changed

      @on_reload&.call(deck)
      true
    end

    def close
      return if @closed

      @closed = true
      @watcher.close
    end
  end
end
