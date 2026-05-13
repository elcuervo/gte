# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'gte'
  spec.version       = File.read(File.expand_path('VERSION', __dir__)).strip
  spec.license       = 'MIT'
  spec.summary       = 'General Text Embeddings'
  spec.authors       = ['elcuervo']
  spec.email         = ['elcuervo@elcuervo.net']
  spec.homepage      = 'https://github.com/elcuervo/gte'

  spec.required_ruby_version = '>= 3.4'

  spec.extensions = ['ext/gte/extconf.rb']

  spec.files = Dir[
    'lib/**/*',
    'ext/**/*.{rb,rs,toml}',
    'LICENSE',
    'README.md',
    'Gemfile',
    'Rakefile',
    'VERSION'
  ]

  spec.require_paths = ['lib']

  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rake-compiler'
  # Keep rb_sys pinned so cross-gem's lockfile parser resolves a stable
  # version instead of falling back to the latest remote gem.
  spec.add_dependency 'rb_sys', '= 0.9.126'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rspec-benchmark'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
