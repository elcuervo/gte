#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'optparse'
require 'open3'
require 'rbconfig'
require 'time'

ROOT = File.expand_path('..', __dir__)
DEFAULT_OUTPUT_DIR = File.expand_path('results', __dir__)
DEFAULT_ITERATIONS = 80
DEFAULT_CONCURRENCY = 16
DEFAULT_RUN_SAMPLES = 3
DEFAULT_THREADS = 'auto,1,2'
DEFAULT_PROVIDERS = 'cpu;xnnpack,coreml'
MODELS = %w[e5 clip siglip2].freeze

def default_output_path
  timestamp = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')
  File.join(DEFAULT_OUTPUT_DIR, "puma_matrix_#{timestamp}.json")
end

def parse_thread_values(raw)
  raw.split(',').map(&:strip).reject(&:empty?).map do |entry|
    next 'auto' if entry == 'auto'

    num = Integer(entry, 10)
    raise ArgumentError, "invalid thread value '#{entry}' (must be auto or positive integer)" if num <= 0

    num
  rescue ArgumentError
    raise ArgumentError, "invalid thread value '#{entry}' (must be auto or positive integer)"
  end.uniq
end

def parse_provider_values(raw)
  raw.split(';').map(&:strip).reject(&:empty?).uniq
end

def model_stats(result, model)
  result.fetch('models').fetch(model).fetch('scenarios').fetch('puma_like_single_request')
end

def model_p95(result, model)
  model_stats(result, model).fetch('by_adapter').fetch('gte').fetch('aggregate').fetch('response_time').fetch('p95_ms')
end

def model_ratio(result, model)
  model_stats(result, model).fetch('gate').fetch('minimum_ratio_over_gte')
end

options = {
  output: default_output_path,
  tmp_dir: '/tmp',
  iterations: DEFAULT_ITERATIONS,
  concurrency: DEFAULT_CONCURRENCY,
  run_samples: DEFAULT_RUN_SAMPLES,
  threads: parse_thread_values(DEFAULT_THREADS),
  providers: parse_provider_values(DEFAULT_PROVIDERS)
}

OptionParser.new do |opts|
  opts.on('--output PATH') { |value| options[:output] = File.expand_path(value, ROOT) }
  opts.on('--tmp-dir PATH') { |value| options[:tmp_dir] = File.expand_path(value, ROOT) }
  opts.on('--iterations N', Integer) { |value| options[:iterations] = value }
  opts.on('--concurrency N', Integer) { |value| options[:concurrency] = value }
  opts.on('--runs N', Integer) { |value| options[:run_samples] = value }
  opts.on('--threads LIST', String) { |value| options[:threads] = parse_thread_values(value) }
  opts.on('--providers LIST', String) { |value| options[:providers] = parse_provider_values(value) }
end.parse!(ARGV)

if options[:iterations] <= 0 || options[:concurrency] <= 0 || options[:run_samples] <= 0
  warn('iterations, concurrency, and runs must be > 0')
  exit 1
end

if options[:threads].empty? || options[:providers].empty?
  warn('threads and providers must contain at least one value')
  exit 1
end

FileUtils.mkdir_p(options[:tmp_dir])

configs = options[:providers].flat_map do |provider|
  options[:threads].map { |threads| [provider, threads] }
end

puts 'Puma matrix sweep'
puts '=' * 60
puts "iterations/model: #{options[:iterations]}"
puts "concurrency: #{options[:concurrency]}"
puts "sample runs: #{options[:run_samples]}"
puts "providers: #{options[:providers].join(', ')}"
puts "threads: #{options[:threads].join(', ')}"

runs = []

configs.each_with_index do |(provider, threads), idx|
  label = "cfg#{idx + 1}: providers=#{provider} threads=#{threads}"
  output_path = File.join(
    options[:tmp_dir],
    "puma_matrix_run_#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}_#{idx + 1}.json"
  )

  cmd = [
    RbConfig.ruby, File.expand_path('puma_compare.rb', __dir__),
    '--output', output_path,
    '--iterations', options[:iterations].to_s,
    '--concurrency', options[:concurrency].to_s,
    '--runs', options[:run_samples].to_s
  ]
  cmd += ['--exec-providers', provider] unless provider == 'cpu'
  cmd += ['--gte-threads', threads.to_s] unless threads == 'auto'

  puts "\n#{label}"
  stdout, stderr, status = Open3.capture3(*cmd)
  print stdout unless stdout.empty?
  warn stderr unless stderr.empty?

  run = {
    'provider' => provider,
    'threads' => threads,
    'output_path' => output_path,
    'command' => cmd,
    'status' => status.success? ? 'ok' : 'failed'
  }

  if status.success? && File.exist?(output_path)
    result = JSON.parse(File.read(output_path))
    run['result'] = result
    run['models'] = MODELS.to_h do |model|
      [model, {
        'gte_response_p95_ms' => model_p95(result, model),
        'response_ratio_p95' => model_ratio(result, model)
      }]
    end
  else
    run['error'] = 'command failed'
  end

  runs << run
end

successful = runs.select { |r| r['status'] == 'ok' && r['result'] }

best_by_model = {}
MODELS.each do |model|
  best = successful.min_by { |r| model_p95(r.fetch('result'), model) }
  next unless best

  best_by_model[model] = {
    'provider' => best.fetch('provider'),
    'threads' => best.fetch('threads'),
    'gte_response_p95_ms' => model_p95(best.fetch('result'), model),
    'response_ratio_p95' => model_ratio(best.fetch('result'), model),
    'source_output_path' => best.fetch('output_path')
  }
end

summary = {
  'kind' => 'puma_matrix_sweep',
  'generated_at' => Time.now.utc.iso8601,
  'ruby_version' => RUBY_VERSION,
  'platform' => RUBY_PLATFORM,
  'iterations' => options[:iterations],
  'concurrency' => options[:concurrency],
  'run_samples' => options[:run_samples],
  'config_space' => {
    'providers' => options[:providers],
    'threads' => options[:threads]
  },
  'runs' => runs.map do |r|
    slim = r.slice('provider', 'threads', 'status', 'output_path')
    slim['models'] = r['models'] if r['models']
    slim['error'] = r['error'] if r['error']
    slim
  end,
  'best_by_model' => best_by_model
}

FileUtils.mkdir_p(File.dirname(options[:output]))
File.write(options[:output], "#{JSON.pretty_generate(summary)}\n")
puts "\nWrote sweep summary: #{options[:output]}"

if successful.empty?
  warn 'FAIL: all matrix runs failed'
  exit 1
end
