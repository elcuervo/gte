# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/extensiontask"
require "shellwords"

RSpec::Core::RakeTask.new(:spec)

Rake::ExtensionTask.new("gte") do |ext|
  ext.lib_dir = "lib/gte"
end

task default: [:compile, :spec]

def run_in_nix(*command)
  sh("nix", "develop", "-c", *command)
end

PARITY_BASELINE_PATH = "bench/baselines/parity_reference.json"
PERFORMANCE_BASELINE_PATH = "bench/baselines/performance_baseline.json"
MANAGED_MODEL_ENV = {
  "GTE_MODEL_DIR" => "tmp/models/e5",
  "GTE_CLIP_DIR" => "tmp/models/clip",
  "GTE_SIGLIP2_DIR" => "tmp/models/siglip2"
}.freeze

namespace :models do
  desc "List managed text embedding fixtures"
  task :list do
    ruby "bench/text_embedding_harness.rb", "list"
  end

  desc "Download managed text embedding fixtures"
  task :download do
    ruby "bench/text_embedding_harness.rb", "download"
  end

  desc "Validate text embedding compatibility across compile, tests, and parity"
  task :validate do
    ruby "bench/text_embedding_harness.rb", "validate"
  end

  desc "Run the full validation flow, downloading fixtures first"
  task :validate_all do
    ruby "bench/text_embedding_harness.rb", "validate", "--download"
  end

  desc "Regenerate committed parity baseline from managed fixtures"
  task :refresh_parity_baseline do
    ruby "bench/text_embedding_harness.rb", "download"
    sh(
      MANAGED_MODEL_ENV,
      "python3",
      "bench/benchmark_python.py",
      "--emit-reference",
      PARITY_BASELINE_PATH
    )
  end

  desc "Regenerate committed performance baseline from managed fixtures"
  task :refresh_performance_baseline do
    ruby "bench/text_embedding_harness.rb", "download"
    Rake::Task[:compile].invoke
    sh(
      MANAGED_MODEL_ENV,
      "bundle",
      "exec",
      "ruby",
      "bench/performance_baseline.rb",
      "capture",
      "--output",
      PERFORMANCE_BASELINE_PATH
    )
  end

  desc "Check current performance against committed baseline (15% regression margin)"
  task :check_performance_baseline do
    sh(
      MANAGED_MODEL_ENV,
      "bundle",
      "exec",
      "ruby",
      "bench/performance_baseline.rb",
      "check",
      "--baseline",
      PERFORMANCE_BASELINE_PATH,
      "--max-regression",
      "0.15"
    )
  end
end

namespace :bench do
  desc "Run Ruby embedding benchmarks inside nix develop"
  task :ruby do
    run_in_nix("bundle", "exec", "ruby", "bench/text_embedding_harness.rb", "benchmark", "--ruby-only")
  end

  desc "Run Python ORT embedding benchmarks inside nix develop"
  task :python do
    run_in_nix("bundle", "exec", "ruby", "bench/text_embedding_harness.rb", "benchmark", "--python-only", "--skip-compile")
  end

  desc "Download fixtures, compile, and run the full benchmark suite inside nix develop"
  task :full do
    run_in_nix("bundle", "exec", "ruby", "bench/text_embedding_harness.rb", "benchmark", "--download")
  end

  desc "Run pure-Ruby (onnxruntime gem) vs GTE benchmark comparison inside nix develop"
  task :pure_compare do
    run_in_nix(
      "bundle",
      "exec",
      "ruby",
      "bench/text_embedding_harness.rb",
      "benchmark",
      "--compare-pure-ruby",
      "--skip-compile"
    )
  end
end
