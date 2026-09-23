# frozen_string_literal: true

require_relative "hadar/version"

require "beid"
require "kochab"
require "zaniah"

require_relative "hadar/layout"
require_relative "hadar/slot"
require_relative "hadar/slide"
require_relative "hadar/theme"
require_relative "hadar/deck"
require_relative "hadar/renderer"
require_relative "hadar/slide_list"

module Hadar
  class Error < StandardError; end
end
