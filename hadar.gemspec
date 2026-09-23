# frozen_string_literal: true

require_relative "lib/hadar/version"

Gem::Specification.new do |spec|
  spec.name = "hadar"
  spec.version = Hadar::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]
  spec.summary = "Markdown-backed presentation editor and preview"
  spec.description = "Projects Beid Markdown ASTs into template-based slide decks, edits supported source-backed text, and exports PDF or PNG."
  spec.homepage = "https://github.com/noxdea/hadar"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "source_code_uri" => "#{spec.homepage}/tree/main",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }
  spec.files = Dir.chdir(__dir__) do
    Dir["{assets,docs,lib,sig}/**/*", "README.md", "CHANGELOG.md", "LICENSE.txt"]
      .select { |path| File.file?(path) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |path| File.basename(path) }
  spec.require_paths = ["lib"]

  spec.add_dependency "beid", ">= 0.1.0"
  spec.add_dependency "antares", ">= 0.1.0"
  spec.add_dependency "kochab", ">= 0.2.0"
  spec.add_dependency "okab", ">= 0.1.0"
  spec.add_dependency "spica", ">= 0.1.0"
  spec.add_dependency "zaniah", ">= 0.6.0"
end
