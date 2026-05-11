# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/extensiontask'
begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  # rspec not available in cross-compile environment
end

spec = Gem::Specification.load('gte.gemspec')
cross_target = ENV.fetch('RUBY_TARGET', nil)

if cross_target == 'arm64-darwin'
  # rb-sys-dock's darwin image can expose an unusable default LIBRARY_PATH.
  # Force the compiler-rt darwin runtime directory so -lclang_rt.osx resolves.
  ENV['LIBRARY_PATH'] = '/usr/lib/llvm-10/lib/clang/10.0.0/lib/darwin'
end

extension_task = Rake::ExtensionTask.new('gte', spec) do |ext|
  ext.lib_dir = 'lib/gte'
  ext.cross_compile = true
  # rb-sys-dock invokes `rake native:$RUBY_TARGET gem` without the `cross` task,
  # so scope platforms during dock builds to avoid host-Ruby fallback copy tasks.
  cross_platforms = if cross_target && !cross_target.empty?
                      [cross_target]
                    else
                      %w[x86_64-linux aarch64-linux arm64-darwin]
                    end
  ext.cross_platform = cross_platforms
end

if cross_target && !cross_target.empty? && ENV.fetch('RUBY_CC_VERSION', nil) && cross_target != 'x86_64-linux'
  ruby_version = ENV['RUBY_CC_VERSION'].split(':').first
  lib_binary_path = File.join(extension_task.lib_dir, File.basename(extension_task.binary(cross_target)))
  copy_task = "copy:gte:#{cross_target}:#{ruby_version}"

  if Rake::Task.task_defined?(lib_binary_path) && Rake::Task.task_defined?(copy_task)
    Rake::Task[lib_binary_path].prerequisites.clear
    Rake::Task[lib_binary_path].enhance([copy_task])
  end
end

task default: %i[compile spec]

def bundler_env
  root = File.expand_path(__dir__)
  {
    'BUNDLE_DISABLE_SHARED_GEMS' => '1',
    'GEM_HOME' => File.join(root, '.bundle-gems'),
    'GEM_PATH' => File.join(root, '.bundle-gems'),
    'BUNDLE_PATH' => File.join(root, 'vendor/bundle')
  }
end

def run_in_nix(*command)
  sh(bundler_env, 'nix', 'develop', '-c', *command)
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

  desc 'Run memory probe for single-instance vs duplicate-instance behavior'
  task :memory_probe do
    run_in_nix(
      'bundle', 'exec', 'ruby', 'bench/memory_probe.rb',
      '--compare-pure'
    )
  end

  desc 'Run Puma benchmark, append RUNS.md entry, and enforce goal checks'
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

  desc 'Validate current Puma benchmark output against 2x goal only'
  task :check_goal do
    run_in_nix(
      'bundle', 'exec', 'ruby', 'bench/runs_ledger.rb', 'check',
      '--result', 'bench/results/puma_compare_latest.json'
    )
  end
end
