# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/extensiontask"

RSpec::Core::RakeTask.new(:spec)

Rake::ExtensionTask.new("gte") do |ext|
  ext.lib_dir = "lib/gte"
end

task default: [:compile, :spec]

def run_in_nix(*command)
  sh("nix", "develop", "-c", *command)
end

namespace :bench do
  desc "Run pure-Ruby (onnxruntime gem) vs GTE benchmark comparison inside nix develop"
  task :pure_compare do
    run_in_nix("bundle", "exec", "ruby", "bench/pure_ruby_compare.rb")
  end
end
