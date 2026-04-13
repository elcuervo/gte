#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'optparse'
require 'pathname'
require 'time'

require 'gte'
require_relative 'pure_ruby_runtime'

ROOT = File.expand_path('..', __dir__)
DEFAULT_OUTPUT_DIR = File.expand_path('results', __dir__)
DEFAULT_ITERATIONS = 40
DEFAULT_CONCURRENCY = 16
DEFAULT_RUN_SAMPLES = 3
DEFAULT_MAX_ABS = 1e-5
DEFAULT_MIN_COS = 0.99999
DEFAULT_MIN_P95_RATIO = 1.95

MODELS = {
  'e5' => {
    'label' => 'E5 multilingual small',
    'env_var' => 'GTE_MODEL_DIR',
    'probe_texts' => [
      'query: benchmark validation probe',
      'query: machine learning basics',
      'passage: gradient descent updates model parameters'
    ],
    'request_template' => 'query: puma request %{idx} for e5'
  },
  'clip' => {
    'label' => 'CLIP ViT-B/32 text encoder',
    'env_var' => 'GTE_CLIP_DIR',
    'probe_texts' => [
      'a photo of a cat',
      'a picture of a kitten',
      'a blueprint of a skyscraper'
    ],
    'request_template' => 'a text prompt %{idx} for clip'
  },
  'siglip2' => {
    'label' => 'Siglip2 base text encoder',
    'env_var' => 'GTE_SIGLIP2_DIR',
    'probe_texts' => [
      'a photo of a cat',
      'a photo of a dog',
      'a geometric abstract logo'
    ],
    'request_template' => 'a text prompt %{idx} for siglip2'
  }
}.freeze

def default_output_path
  timestamp = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')
  File.join(DEFAULT_OUTPUT_DIR, "puma_compare_#{timestamp}.json")
end

def resolve_models
  MODELS.each_with_object({}) do |(key, cfg), out|
    dir = ENV.fetch(cfg.fetch('env_var'), nil)
    next if dir.nil? || dir.empty?

    expanded = File.expand_path(dir, ROOT)
    next unless Dir.exist?(expanded)

    out[key] = cfg.merge('dir' => expanded)
  end
end

def cosine_similarity(a, b)
  dot = a.zip(b).sum { |x, y| x * y }
  norm_a = Math.sqrt(a.sum { |v| v * v })
  norm_b = Math.sqrt(b.sum { |v| v * v })
  return 0.0 if norm_a.zero? || norm_b.zero?

  dot / (norm_a * norm_b)
end

def compare_embeddings(actual, reference)
  raise "row count mismatch: #{actual.length} vs #{reference.length}" unless actual.length == reference.length

  max_abs = 0.0
  mean_abs = 0.0
  min_cosine = Float::INFINITY
  count = 0

  actual.zip(reference).each do |act_row, ref_row|
    raise "dimension mismatch: #{act_row.length} vs #{ref_row.length}" unless act_row.length == ref_row.length

    act_row.zip(ref_row).each do |act, ref|
      diff = (act - ref).abs
      max_abs = diff if diff > max_abs
      mean_abs += diff
      count += 1
    end

    cos = cosine_similarity(act_row, ref_row)
    min_cosine = cos if cos < min_cosine
  end

  {
    'max_abs' => max_abs,
    'mean_abs' => (count.zero? ? 0.0 : mean_abs / count),
    'min_cosine' => min_cosine
  }
end

def materialize_embeddings(result)
  return result if result.is_a?(Array)
  return result.to_a if result.respond_to?(:to_a)

  result
end

def percentile(sorted, p)
  idx = (sorted.length * p).floor
  idx = sorted.length - 1 if idx >= sorted.length
  sorted[idx]
end

def latency_summary(samples_ms)
  sorted = samples_ms.sort
  {
    'median_ms' => sorted[sorted.length / 2],
    'p95_ms' => percentile(sorted, 0.95),
    'p99_ms' => percentile(sorted, 0.99),
    'min_ms' => sorted.first,
    'max_ms' => sorted.last
  }
end

def metric_median(samples, path)
  values = samples.map do |sample|
    path.reduce(sample) { |acc, key| acc.fetch(key) }
  end
  values.sort[values.length / 2]
end

def aggregate_samples(samples)
  {
    'response_time' => {
      'median_ms' => metric_median(samples, %w[response_time median_ms]),
      'p95_ms' => metric_median(samples, %w[response_time p95_ms]),
      'p99_ms' => metric_median(samples, %w[response_time p99_ms])
    },
    'service_time' => {
      'median_ms' => metric_median(samples, %w[service_time median_ms]),
      'p95_ms' => metric_median(samples, %w[service_time p95_ms]),
      'p99_ms' => metric_median(samples, %w[service_time p99_ms])
    },
    'throughput_rps' => metric_median(samples, ['throughput_rps']),
    'requests' => metric_median(samples, ['requests'])
  }
end

def benchmark_concurrent(callable, request_texts, concurrency)
  queue = Queue.new
  dispatch_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  request_texts.each_with_index { |text, idx| queue << [idx, text, dispatch_time] }

  service_latencies = []
  response_latencies = []
  mutex = Mutex.new

  start_wall = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  workers = Array.new(concurrency) do
    Thread.new do
      loop do
        idx, text, enqueued_at = queue.pop(true)
        service_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        callable.call(text)
        finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        service_ms = (finished_at - service_start) * 1000.0
        response_ms = (finished_at - enqueued_at) * 1000.0

        mutex.synchronize do
          service_latencies[idx] = service_ms
          response_latencies[idx] = response_ms
        end
      rescue ThreadError
        break
      end
    end
  end
  workers.each(&:join)
  wall_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_wall) * 1000.0

  {
    'response_time' => latency_summary(response_latencies),
    'service_time' => latency_summary(service_latencies),
    'requests' => request_texts.length,
    'wall_ms' => wall_ms,
    'throughput_rps' => request_texts.length / (wall_ms / 1000.0)
  }
end

def generate_requests(template, iterations)
  Array.new(iterations) { |i| format(template, idx: i) }
end

def benchmark_pair_samples(gte_callable, pure_callable, requests, concurrency, run_samples)
  gte_samples = []
  pure_samples = []

  run_samples.times do |idx|
    if idx.even?
      gte_samples << benchmark_concurrent(gte_callable, requests, concurrency)
      pure_samples << benchmark_concurrent(pure_callable, requests, concurrency)
    else
      pure_samples << benchmark_concurrent(pure_callable, requests, concurrency)
      gte_samples << benchmark_concurrent(gte_callable, requests, concurrency)
    end
  end

  {
    'gte' => {
      'samples' => gte_samples,
      'aggregate' => aggregate_samples(gte_samples)
    },
    'pure_ruby' => {
      'samples' => pure_samples,
      'aggregate' => aggregate_samples(pure_samples)
    }
  }
end

options = {
  output: default_output_path,
  iterations: DEFAULT_ITERATIONS,
  concurrency: DEFAULT_CONCURRENCY,
  run_samples: DEFAULT_RUN_SAMPLES,
  max_abs: DEFAULT_MAX_ABS,
  min_cos: DEFAULT_MIN_COS,
  min_p95_ratio: DEFAULT_MIN_P95_RATIO,
  gte_threads: nil,
  exec_providers: nil,
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
  opts.on('--gte-threads N', Integer) { |value| options[:gte_threads] = value }
  opts.on('--exec-providers LIST') { |value| options[:exec_providers] = value.strip }
  opts.on('--enforce-goal') { options[:enforce_goal] = true }
end.parse!(ARGV)

if options[:iterations] <= 0
  warn('iterations must be > 0')
  exit 1
end

if options[:concurrency] <= 0
  warn('concurrency must be > 0')
  exit 1
end

if options[:run_samples] <= 0
  warn('runs must be > 0')
  exit 1
end

if options[:gte_threads] && options[:gte_threads] <= 0
  warn('gte-threads must be > 0')
  exit 1
end

resolved = resolve_models
if resolved.empty?
  warn('no model directories configured via GTE_MODEL_DIR/GTE_CLIP_DIR/GTE_SIGLIP2_DIR')
  exit 1
end

puts 'Puma-like in-process concurrency benchmark (single-request path)'
puts '=' * 72
puts "iterations/model: #{options[:iterations]}"
puts "concurrency: #{options[:concurrency]}"
puts "sample runs: #{options[:run_samples]} (median aggregation)"
puts "gte threads: #{options[:gte_threads] || 'auto'}"
puts "execution providers: #{options[:exec_providers] || ENV['GTE_EXECUTION_PROVIDERS'] || 'xnnpack (runtime default)'}"
puts "thresholds: max_abs<=#{options[:max_abs]} min_cos>=#{options[:min_cos]} response_p95_ratio>=#{options[:min_p95_ratio]}x"

payload = {
  'version' => 2,
  'generated_at' => Time.now.utc.iso8601,
  'ruby_version' => RUBY_VERSION,
  'platform' => RUBY_PLATFORM,
  'gem_version' => File.read(File.expand_path('../VERSION', __dir__)).strip,
  'git_sha' => `git rev-parse --short HEAD`.strip,
  'mode' => 'puma_like_in_process',
  'iterations' => options[:iterations],
  'concurrency' => options[:concurrency],
  'run_samples' => options[:run_samples],
  'runtime_overrides' => {
    'gte_threads' => options[:gte_threads],
    'execution_providers' => options[:exec_providers]
  },
  'thresholds' => {
    'max_abs' => options[:max_abs],
    'min_cos' => options[:min_cos],
    'min_p95_ratio' => options[:min_p95_ratio],
    'goal_metric' => 'response_time_p95',
    'sample_aggregation' => 'median'
  },
  'models' => {}
}

correctness_failures = []
ratio_failures = []

original_exec_providers = ENV.fetch('GTE_EXECUTION_PROVIDERS', nil)
ENV['GTE_EXECUTION_PROVIDERS'] = options[:exec_providers] if options[:exec_providers]

begin
  resolved.each do |key, cfg|
    label = cfg.fetch('label')
    model_dir = cfg.fetch('dir')

    puts "\n#{label} (#{key})"
    puts "  dir: #{Pathname.new(model_dir).relative_path_from(Pathname.new(ROOT))}"

    gte_model = GTE.new(model_dir, num_threads: options[:gte_threads] || 0)
    pure_model = PureRubyTextEmbedding::TextEncoder.new(model_dir: model_dir)

    probe_texts = cfg.fetch('probe_texts')
    gte_embeddings = materialize_embeddings(gte_model.embed(probe_texts))
    pure_embeddings = pure_model.embed(probe_texts)

    correctness = compare_embeddings(pure_embeddings, gte_embeddings)
    correctness['rows'] = probe_texts.length
    correctness['dim'] = pure_embeddings.first&.length || 0

    puts format('  correctness: max_abs=%<max>.9f mean_abs=%<mean>.9f min_cosine=%<cos>.9f',
                max: correctness.fetch('max_abs'),
                mean: correctness.fetch('mean_abs'),
                cos: correctness.fetch('min_cosine'))

    if correctness.fetch('max_abs') > options[:max_abs] || correctness.fetch('min_cosine') < options[:min_cos]
      correctness_failures << "#{key} failed correctness thresholds"
    end

    warmup_text = format(cfg.fetch('request_template'), idx: 'warmup')
    (options[:concurrency] * 2).times do
      gte_model.embed(warmup_text)
      pure_model.embed(warmup_text)
    end

    requests = generate_requests(cfg.fetch('request_template'), options[:iterations])
    pair_stats = benchmark_pair_samples(
      ->(text) { gte_model.embed(text) },
      ->(text) { pure_model.embed(text) },
      requests,
      options[:concurrency],
      options[:run_samples]
    )
    gte_stats = pair_stats.fetch('gte')
    pure_stats = pair_stats.fetch('pure_ruby')

    gte_agg = gte_stats.fetch('aggregate')
    pure_agg = pure_stats.fetch('aggregate')

    ratio_response_p95 = pure_agg.fetch('response_time').fetch('p95_ms') / gte_agg.fetch('response_time').fetch('p95_ms')
    ratio_response_median = pure_agg.fetch('response_time').fetch('median_ms') / gte_agg.fetch('response_time').fetch('median_ms')
    ratio_service_p95 = pure_agg.fetch('service_time').fetch('p95_ms') / gte_agg.fetch('service_time').fetch('p95_ms')

    puts format('  gte:  response_p95=%<rp95>.2fms service_p95=%<sp95>.2fms throughput=%<rps>.2frps',
                rp95: gte_agg.fetch('response_time').fetch('p95_ms'),
                sp95: gte_agg.fetch('service_time').fetch('p95_ms'),
                rps: gte_agg.fetch('throughput_rps'))
    puts format('  pure: response_p95=%<rp95>.2fms service_p95=%<sp95>.2fms throughput=%<rps>.2frps',
                rp95: pure_agg.fetch('response_time').fetch('p95_ms'),
                sp95: pure_agg.fetch('service_time').fetch('p95_ms'),
                rps: pure_agg.fetch('throughput_rps'))
    puts format('  ratios: response_median=%<rm>.2fx response_p95=%<rp95>.2fx service_p95=%<sp95>.2fx',
                rm: ratio_response_median,
                rp95: ratio_response_p95,
                sp95: ratio_service_p95)

    if ratio_response_p95 < options[:min_p95_ratio]
      ratio_failures << "#{key} response_p95 ratio #{ratio_response_p95.round(2)}x < #{options[:min_p95_ratio]}x"
    end

    payload.fetch('models')[key] = {
      'label' => label,
      'dir' => Pathname.new(model_dir).relative_path_from(Pathname.new(ROOT)).to_s,
      'correctness' => correctness,
      'puma_like' => {
        'gte' => gte_stats,
        'pure_ruby' => pure_stats,
        'ratio_pure_over_gte' => {
          'response_median' => ratio_response_median,
          'response_p95' => ratio_response_p95,
          'service_p95' => ratio_service_p95
        }
      }
    }
  end
ensure
  ENV['GTE_EXECUTION_PROVIDERS'] = original_exec_providers
end

FileUtils.mkdir_p(File.dirname(options[:output]))
File.write(options[:output], "#{JSON.pretty_generate(payload)}\n")
puts "\nWrote benchmark results: #{Pathname.new(options[:output]).relative_path_from(Pathname.new(ROOT))}"

if correctness_failures.any?
  warn 'FAIL: correctness threshold failures'
  correctness_failures.each { |f| warn "  - #{f}" }
  exit 1
end

if ratio_failures.any?
  if options[:enforce_goal]
    warn 'FAIL: response-time p95 speed target not met'
    ratio_failures.each { |f| warn "  - #{f}" }
    exit 1
  end
  warn 'WARN: response-time p95 speed target not met'
  ratio_failures.each { |f| warn "  - #{f}" }
  exit 0
end

puts 'PASS: correctness and response-time p95 speed targets satisfied'
