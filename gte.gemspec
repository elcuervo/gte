# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "gte"
  spec.version       = File.read(File.expand_path("VERSION", __dir__)).strip
  spec.license       = "MIT"
  spec.summary       = "General Text Embeddings"
  spec.authors       = ["elcuervo"]
  spec.email         = ["elcuervo@elcuervo.net"]
  spec.homepage      = "https://github.com/elcuervo/gte"

  spec.required_ruby_version = ">= 3.2"

  spec.extensions = ["ext/gte/extconf.rb"]

  spec.files = Dir[
    "lib/**/*",
    "ext/**/*.{rb,rs,toml}",
    "LICENSE",
    "README.md",
    "Gemfile",
    "Rakefile",
    "VERSION"
  ]

  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake"
  spec.add_development_dependency "rake-compiler"
  spec.add_development_dependency "rb_sys"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rspec-benchmark"
end
