#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'time'

require 'gte'

ROOT = File.expand_path('..', __dir__)
DEFAULT_CONCURRENCY = 16
DEFAULT_ITERATIONS = 48
THREAD_CANDIDATES = [1, 2, 3, 4, 6, 8].freeze

MODELS = {
  'e5' => {
    'label' => 'E5 multilingual small',
    'env_var' => 'GTE_MODEL_DIR',
    'request_template' => 'query: thread sweep %{idx}'
  },
  'clip' => {
    'label' => 'CLIP ViT-B/32 text encoder',
    'env_var' => 'GTE_CLIP_DIR',
    'request_template' => 'a clip prompt %{idx}'
  },
  'siglip2' => {
    'label' => 'Siglip2 base text encoder',
    'env_var' => 'GTE_SIGLIP2_DIR',
    'request_template' => 'a siglip prompt %{idx}'
  }
}.freeze

def percentile(sorted, p)
  idx = (sorted.length * p).floor
  idx = sorted.length - 1 if idx >= sorted.length
  sorted[idx]
end

def run_once(model, requests, concurrency)
  queue = Queue.new
  requests.each { |text| queue << text }

  latencies = []
  mutex = Mutex.new
  workers = Array.new(concurrency) do
    Thread.new do
      loop do
        text = queue.pop(true)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        model.embed(text)
        elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
        mutex.synchronize { latencies << elapsed_ms }
      rescue ThreadError
        break
      end
    end
  end
  workers.each(&:join)

  sorted = latencies.sort
  {
    'median_ms' => sorted[sorted.length / 2],
    'p95_ms' => percentile(sorted, 0.95),
    'p99_ms' => percentile(sorted, 0.99)
  }
end

options = {
  iterations: DEFAULT_ITERATIONS,
  concurrency: DEFAULT_CONCURRENCY,
  candidates: THREAD_CANDIDATES
}

OptionParser.new do |opts|
  opts.on('--iterations N', Integer) { |value| options[:iterations] = value }
  opts.on('--concurrency N', Integer) { |value| options[:concurrency] = value }
  opts.on('--threads LIST', String) do |value|
    options[:candidates] = value.split(',').map(&:to_i).select(&:positive?).uniq
  end
end.parse!(ARGV)

if options[:iterations] <= 0 || options[:concurrency] <= 0 || options[:candidates].empty?
  warn 'invalid options'
  exit 1
end

puts "Thread sweep (puma-like): concurrency=#{options[:concurrency]} iterations=#{options[:iterations]}"

MODELS.each do |key, cfg|
  dir = ENV.fetch(cfg.fetch('env_var'), nil)
  next if dir.nil? || dir.empty? || !Dir.exist?(dir)

  puts "\n#{cfg.fetch('label')} (#{key})"
  requests = Array.new(options[:iterations]) { |i| format(cfg.fetch('request_template'), idx: i) }

  best = nil
  options[:candidates].each do |threads|
    model = GTE.new(File.expand_path(dir, ROOT), num_threads: threads)
    (options[:concurrency] * 2).times { |i| model.embed(format(cfg.fetch('request_template'), idx: "warmup-#{i}")) }

    stats = run_once(model, requests, options[:concurrency])
    puts format('  threads=%<t>d median=%<m>.2fms p95=%<p95>.2fms p99=%<p99>.2fms',
                t: threads,
                m: stats.fetch('median_ms'),
                p95: stats.fetch('p95_ms'),
                p99: stats.fetch('p99_ms'))
    best = [threads, stats] if best.nil? || stats.fetch('p95_ms') < best[1].fetch('p95_ms')
  end

  puts format('  best: threads=%<t>d p95=%<p95>.2fms', t: best[0], p95: best[1].fetch('p95_ms'))
end
