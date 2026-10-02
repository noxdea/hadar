# frozen_string_literal: true

require "fileutils"
require "hadar"

markdown = File.read(File.expand_path("../docs/index.md", __dir__))[/```markdown\n(.*?)\n```/m, 1]
deck = Hadar::Deck.parse(markdown)
app = Hadar::Application.new(deck, watch: false)
window = Zaniah::Platform.open_window(backend: :headless, width: 1280, height: 800)

begin
  window.text_system = Zaniah::TextSystem::Renderer.new
  app.attach(main_window: window)
  app.select_slide(1)
  window.tick
  output = File.expand_path("../docs/media/overview.png", __dir__)
  FileUtils.mkdir_p(File.dirname(output))
  window.write_png(output)
  puts output
ensure
  app.close
  window.close
end
