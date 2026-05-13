#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'pathname'

require_relative 'harness'

ROOT = File.expand_path('..', __dir__)
DEFAULT_ITERATIONS = 40
DEFAULT_CONCURRENCY = 16
DEFAULT_RUN_SAMPLES = 3
DEFAULT_MAX_ABS = 1e-5
DEFAULT_MIN_COS = 0.99999
DEFAULT_MIN_P95_RATIO = 1.0
DEFAULT_MIN_SERVICE_RATIO = 0.0

options = {
  output: Bench::MultiRuntimeHarness.default_output_path('puma_compare'),
  iterations: DEFAULT_ITERATIONS,
  concurrency: DEFAULT_CONCURRENCY,
  run_samples: DEFAULT_RUN_SAMPLES,
  max_abs: DEFAULT_MAX_ABS,
  min_cos: DEFAULT_MIN_COS,
  min_p95_ratio: DEFAULT_MIN_P95_RATIO,
  min_service_ratio: DEFAULT_MIN_SERVICE_RATIO,
  exec_providers: 'cpu',
  python_worker_pool: 1,
  skip_python: false,
  enforce_goal: false
}

OptionParser.new do |opts|
  opts.on('--output PATH') { |value| options[:output] = File.expand_path(value, ROOT) }
  opts.on('--iterations N', Integer) { |value| options[:iterations] = value }
  opts.on('--concurrency N', Integer) { |value| options[:concurrency] = value }
  opts.on('--runs N', Integer) { |value| options[:run_samples] = value }
  opts.on('--max-abs FLOAT', Float) { |value| options[:max_abs] = value }
  opts.on('--min-cos FLOAT', Float) { |value| options[:min_cos] = value }
  opts.on('--min-p95-ratio FLOAT', Float) { |value| options[:min_p95_ratio] = value }
  opts.on('--min-service-ratio FLOAT', Float) { |value| options[:min_service_ratio] = value }
  opts.on('--exec-providers LIST') { |value| options[:exec_providers] = value.strip }
  opts.on('--python-worker-pool N', Integer) { |value| options[:python_worker_pool] = value }
  opts.on('--skip-python') { options[:skip_python] = true }
  opts.on('--enforce-goal') { options[:enforce_goal] = true }
end.parse!(ARGV)

if options[:iterations] <= 0 || options[:concurrency] <= 0 || options[:run_samples] <= 0
  warn('iterations, concurrency, and runs must be > 0')
  exit 1
end

if options[:python_worker_pool] <= 0
  warn('python-worker-pool must be > 0')
  exit 1
end

models = Bench::MultiRuntimeHarness.resolve_models(root: ROOT)
if models.empty?
  warn('no model directories configured via GTE_MODEL_DIR/GTE_CLIP_DIR/GTE_SIGLIP2_DIR')
  exit 1
end

adapters = [
  Bench::Adapters::Gte.new(profile: {
                             'execution_providers' => options[:exec_providers]
                           }),
  Bench::Adapters::PureRuby.new
]
unless options[:skip_python]
  adapters << Bench::Adapters::PythonOnnxRuntime.new(profile: {
                                                       'worker_pool' => options[:python_worker_pool],
                                                       'intra_threads' => 1,
                                                       'inter_threads' => 1
                                                     })
end

puts 'Puma-like in-process concurrency benchmark (single-request path)'
puts '=' * 72
puts "iterations/model: #{options[:iterations]}"
puts "concurrency: #{options[:concurrency]}"
puts "sample runs: #{options[:run_samples]} (median aggregation)"
puts "execution providers: #{options[:exec_providers]}"
puts "python adapter: #{options[:skip_python] ? 'disabled' : "enabled (pool=#{options[:python_worker_pool]})"}"
puts "thresholds: max_abs<=#{options[:max_abs]} min_cos>=#{options[:min_cos]} response_p95_ratio>=#{options[:min_p95_ratio]}x service_p95_ratio>=#{options[:min_service_ratio]}x"

harness = Bench::MultiRuntimeHarness.new(
  models: models,
  adapters: adapters,
  scenarios: ['puma_like_single_request'],
  thresholds: {
    'max_abs' => options[:max_abs],
    'min_cos' => options[:min_cos],
    'min_p95_ratio' => options[:min_p95_ratio],
    'min_service_ratio' => options[:min_service_ratio]
  },
  puma: {
    'iterations' => options[:iterations],
    'concurrency' => options[:concurrency],
    'run_samples' => options[:run_samples]
  }
)

result = harness.run
result.payload['puma_like'] = {
  'iterations' => options[:iterations],
  'concurrency' => options[:concurrency],
  'run_samples' => options[:run_samples]
}

Bench::MultiRuntimeHarness.write_payload(options[:output], result.payload)
puts "\nWrote benchmark results: #{Pathname.new(options[:output]).relative_path_from(Pathname.new(ROOT))}"

if result.correctness_failures.any?
  warn 'FAIL: correctness threshold failures'
  result.correctness_failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

if result.goal_failures.any?
  if options[:enforce_goal]
    warn 'FAIL: performance goals not met'
    result.goal_failures.each { |failure| warn "  - #{failure}" }
    exit 1
  end
  warn 'WARN: performance goals not met'
  result.goal_failures.each { |failure| warn "  - #{failure}" }
  exit 0
end

puts 'PASS: correctness, response-time p95, and service-time p95 goals satisfied'
