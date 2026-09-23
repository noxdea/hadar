# frozen_string_literal: true

require_relative "hadar/version"

require "beid"
require "antares"
require "kochab"
require "okab"
require "xamidimura"
require "zaniah"
require "zaniah/ui"

require_relative "hadar/layout"
require_relative "hadar/slot"
require_relative "hadar/rich_text_projection"
require_relative "hadar/rich_text_writeback"
require_relative "hadar/slide"
require_relative "hadar/theme"
require_relative "hadar/deck"
require_relative "hadar/deck_watcher"
require_relative "hadar/renderer"
require_relative "hadar/slide_list"
require_relative "hadar/presenter"
require_relative "hadar/application"

module Hadar
  class Error < StandardError; end
end

require_relative "hadar/export/pdf"
require_relative "hadar/export/png_sequence"
