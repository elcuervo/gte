# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/extensiontask'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

spec = Gem::Specification.load('gte.gemspec')

Rake::ExtensionTask.new('gte', spec) do |ext|
  ext.lib_dir = 'lib/gte'
  ext.cross_compile = true
  ext.cross_platform = %w[x86_64-linux aarch64-linux arm64-darwin]
end

task default: %i[compile spec]

def run_in_nix(*command)
  sh('nix', 'develop', '-c', *command)
end

namespace :bench do
  desc 'Run pure-Ruby (onnxruntime gem) vs GTE benchmark comparison inside nix develop'
  task :pure_compare do
    run_in_nix('bundle', 'exec', 'ruby', 'bench/pure_ruby_compare.rb')
  end

  desc 'Run Puma-like concurrent single-request benchmark (GTE vs pure Ruby)'
  task :puma_compare do
    run_in_nix(
      'bundle', 'exec', 'ruby', 'bench/puma_compare.rb',
      '--output', 'bench/results/puma_compare_latest.json',
      '--iterations', '80',
      '--runs', '3'
    )
  end

  desc 'Sweep execution-provider and thread settings for Puma-like benchmark'
  task :matrix_sweep do
    run_in_nix(
      'bundle', 'exec', 'ruby', 'bench/puma_matrix_sweep.rb',
      '--iterations', '80',
      '--runs', '3'
    )
  end

  desc 'Run Puma benchmark, append RUNS.md entry, and enforce goal/regression checks'
  task :record_run do
    run_in_nix(
      'bundle', 'exec', 'ruby', 'bench/puma_compare.rb',
      '--output', 'bench/results/puma_compare_latest.json',
      '--iterations', '80',
      '--runs', '3'
    )
    run_in_nix(
      'bundle', 'exec', 'ruby', 'bench/runs_ledger.rb', 'append',
      '--result', 'bench/results/puma_compare_latest.json'
    )
    run_in_nix(
      'bundle', 'exec', 'ruby', 'bench/runs_ledger.rb', 'check',
      '--result', 'bench/results/puma_compare_latest.json'
    )
  end

  desc 'Validate current Puma benchmark output against 2x goal and regression policy'
  task :check_goal do
    run_in_nix(
      'bundle', 'exec', 'ruby', 'bench/runs_ledger.rb', 'check',
      '--result', 'bench/results/puma_compare_latest.json'
    )
  end
end
