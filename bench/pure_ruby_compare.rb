#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'pathname'

require_relative 'harness'

ROOT = File.expand_path('..', __dir__)
DEFAULT_ITERATIONS = 20
DEFAULT_MAX_ABS = 1e-5
DEFAULT_MIN_COS = 0.99999

def parse_batch_sizes(value)
  value.split(',').map(&:strip).map(&:to_i).select(&:positive?).uniq
end

options = {
  output: Bench::MultiRuntimeHarness.default_output_path('pure_ruby_vs_gte'),
  iterations: DEFAULT_ITERATIONS,
  batch_sizes: Bench::MultiRuntimeHarness::DEFAULT_BATCH_SIZES,
  max_abs: DEFAULT_MAX_ABS,
  min_cos: DEFAULT_MIN_COS,
  skip_python: false
}

OptionParser.new do |opts|
  opts.on('--output PATH') { |value| options[:output] = File.expand_path(value, ROOT) }
  opts.on('--iterations N', Integer) { |value| options[:iterations] = value }
  opts.on('--batch-sizes LIST') { |value| options[:batch_sizes] = parse_batch_sizes(value) }
  opts.on('--max-abs FLOAT', Float) { |value| options[:max_abs] = value }
  opts.on('--min-cos FLOAT', Float) { |value| options[:min_cos] = value }
  opts.on('--skip-python') { options[:skip_python] = true }
end.parse!(ARGV)

if options[:iterations] <= 0 || options[:batch_sizes].empty?
  warn('iterations must be > 0 and batch sizes must not be empty')
  exit 1
end

models = Bench::MultiRuntimeHarness.resolve_models(root: ROOT)
if models.empty?
  warn('no model directories configured via GTE_MODEL_DIR/GTE_CLIP_DIR/GTE_SIGLIP2_DIR')
  exit 1
end

adapters = [
  Bench::Adapters::Gte.new,
  Bench::Adapters::PureRuby.new
]
adapters << Bench::Adapters::PythonOnnxRuntime.new unless options[:skip_python]

puts 'Batch amortization benchmark'
puts '=' * 60
puts "iterations: #{options[:iterations]}"
puts "batch sizes: #{options[:batch_sizes].join(', ')}"
puts "python adapter: #{options[:skip_python] ? 'disabled' : 'enabled'}"
puts "thresholds: max_abs<=#{options[:max_abs]} min_cos>=#{options[:min_cos]}"

harness = Bench::MultiRuntimeHarness.new(
  models: models,
  adapters: adapters,
  scenarios: ['batch_amortization'],
  thresholds: {
    'max_abs' => options[:max_abs],
    'min_cos' => options[:min_cos],
    'min_p95_ratio' => 1.0
  },
  batch: {
    'iterations' => options[:iterations],
    'batch_sizes' => options[:batch_sizes]
  }
)

result = harness.run
Bench::MultiRuntimeHarness.write_payload(options[:output], result.payload)
puts "\nWrote compare results: #{Pathname.new(options[:output]).relative_path_from(Pathname.new(ROOT))}"

if result.correctness_failures.any?
  warn 'FAIL: correctness threshold failures'
  result.correctness_failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts 'PASS: correctness thresholds satisfied'
