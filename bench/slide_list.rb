# frozen_string_literal: true

require "benchmark"
require "hadar"

slides = Array.new(100) { |index| "# Slide #{index + 1}\n\nA short preview paragraph." }
deck = Hadar::Deck.parse(slides.join("\n\n---\n\n"))
window = Zaniah::Platform.open_window(backend: :headless, width: 640, height: 720)
list = Hadar::SlideList.new(deck).build(width: 320, height: 720)

begin
  10.times do |index|
    list.scroll_y = (index * 9 % 90) * 180
    window.render(list, present: false)
  end
  samples = 100.times.map do |index|
    list.scroll_y = (index * 9 % 90) * 180
    Benchmark.realtime { window.render(list, present: false) } * 1000
  end
  median_ms = samples.sort.fetch(50)
  puts "100-slide thumbnail layout/scene median: #{median_ms.round(2)} ms"
  raise "slide thumbnail layout budget exceeded" if ENV["BUDGET"] == "1" && median_ms > 16.7
ensure
  window.close
end
