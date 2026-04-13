#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'

require 'gte'
require_relative 'pure_ruby_runtime'

ROOT = File.expand_path('..', __dir__)
DEFAULT_THREADS = 16
DEFAULT_BURST = 32

def rss_kb
  `ps -o rss= -p #{Process.pid}`.to_i
end

def report(label)
  GC.start(full_mark: true, immediate_sweep: true)
  sleep 0.03
  puts format('%-30s rss=%d KB', label, rss_kb)
end

def burst(label, workers:, requests:)
  queue = Queue.new
  requests.each { |text| queue << text }
  threads = Array.new(workers) do
    Thread.new do
      loop do
        text = queue.pop(true)
        yield(text)
      rescue ThreadError
        break
      end
    end
  end
  threads.each(&:join)
  report(label)
end

options = {
  model_dir: File.expand_path(ENV.fetch('GTE_MODEL_DIR', 'models/e5'), ROOT),
  workers: DEFAULT_THREADS,
  burst: DEFAULT_BURST,
  compare_pure: false
}

OptionParser.new do |opts|
  opts.on('--model-dir PATH') { |v| options[:model_dir] = File.expand_path(v, ROOT) }
  opts.on('--workers N', Integer) { |v| options[:workers] = v }
  opts.on('--burst N', Integer) { |v| options[:burst] = v }
  opts.on('--compare-pure') { options[:compare_pure] = true }
end.parse!(ARGV)

unless Dir.exist?(options[:model_dir])
  warn "model directory not found: #{options[:model_dir]}"
  exit 1
end

puts 'GTE memory probe'
puts '=' * 60
puts "pid=#{Process.pid} model_dir=#{options[:model_dir]}"
puts "workers=#{options[:workers]} burst=#{options[:burst]}"
puts

report('boot')

gte_a = GTE.fetch(options[:model_dir], num_threads: 0)
report('gte fetch #1')
gte_a.embed('query: warmup')
report('gte warmup')

gte_b = GTE.fetch(options[:model_dir], num_threads: 0)
report('gte fetch #2 (same key)')
puts "same_instance=#{gte_a.equal?(gte_b)}"

texts = Array.new(options[:burst]) { |i| "query: memory probe #{i}" }
burst('gte thread burst', workers: options[:workers], requests: texts) { |text| gte_a.embed(text) }

gte_new = GTE.new(options[:model_dir], num_threads: 0)
report('gte new #2 (same key)')
puts "new_reuses_instance=#{gte_new.equal?(gte_a)}"

gte_new_threads = GTE.new(options[:model_dir], num_threads: 1)
report('gte new (different key)')
puts "different_key_distinct=#{!gte_new_threads.equal?(gte_a)}"
burst('gte two-key burst', workers: options[:workers], requests: texts) do |text|
  (text.hash.even? ? gte_a : gte_new_threads).embed(text)
end

if options[:compare_pure]
  pure = PureRubyTextEmbedding::TextEncoder.new(model_dir: options[:model_dir])
  report('pure new')
  pure.embed(['query: warmup'])
  report('pure warmup')
  burst('pure thread burst', workers: options[:workers], requests: texts) { |text| pure.embed([text]) }
end
